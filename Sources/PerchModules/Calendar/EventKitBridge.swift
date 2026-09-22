import EventKit
import Foundation
import PerchCore

/// The only file in Perch that touches EventKit.
///
/// Everything above it works on `CalendarEvent`, which is a value and is
/// testable without a calendar (`docs/TEST-PLAN.md` § CAL is a unit block
/// for exactly that reason). This half is the part that cannot be tested on
/// CI, so it is kept as small as it can be: ask, read, convert, notify.
///
/// **Access is requested on enable, never at launch** (`CLAUDE.md` §5.3,
/// TC-PRV-002). Constructing an `EKEventStore` does not prompt; only
/// `requestAccess` does, and nothing here calls it until `requestAccess()`
/// is called from `CalendarService.activate`.
@MainActor
final class EventKitBridge {

    enum Access: Equatable {
        case notDetermined
        case denied
        case restricted

        /// macOS 14 and later can grant write-only access, which is useless
        /// here — Perch reads. Treated as denied, and the settings pane says
        /// which one it is so that "I did grant it" has an answer
        /// (TC-CAL-001).
        case writeOnly
        case granted
    }

    /// Created lazily. An `EKEventStore` that exists has already registered
    /// for change notifications with the daemon, and a module that is
    /// switched off must hold nothing at all (`CLAUDE.md` §5.1).
    private var store: EKEventStore?
    private var observer: NSObjectProtocol?

    /// How far ahead events are read. Two days covers the agenda list's
    /// "today and tomorrow" with room for a late-night event to still be
    /// running at midnight.
    private let window: TimeInterval = 2 * 24 * 3_600

    /// Called when EventKit says something changed. The store does not say
    /// *what* changed, so this is a signal to re-read, not a diff.
    var onChange: (() -> Void)?

    // MARK: - Access

    var access: Access {
        Self.access(for: EKEventStore.authorizationStatus(for: .event))
    }

    var remindersAccess: Access {
        Self.access(for: EKEventStore.authorizationStatus(for: .reminder))
    }

    private static func access(for status: EKAuthorizationStatus) -> Access {
        switch status {
        case .notDetermined: .notDetermined
        case .restricted: .restricted
        case .denied: .denied
        case .fullAccess: .granted
        case .writeOnly: .writeOnly
        // `.authorized` is the macOS 13 spelling of full access. It is
        // deprecated on 14 and later, which is why both appear.
        case .authorized: .granted
        @unknown default: .denied
        }
    }

    /// Asks for calendar access, prompting only the first time.
    ///
    /// Returns the resulting state rather than throwing: a refusal is a
    /// normal outcome the module has a UI for, not an error.
    func requestAccess() async -> Access {
        let store = makeStore()

        do {
            if #available(macOS 14.0, *) {
                _ = try await store.requestFullAccessToEvents()
            } else {
                _ = try await store.requestAccess(to: .event)
            }
        } catch {
            // The only documented failure is the user saying no, which
            // `authorizationStatus` already tells us more precisely.
        }

        return access
    }

    /// Asks for reminders access. Separate, and only when the reminders row
    /// is switched on — the calendar half works perfectly without it, and
    /// two prompts at once is what makes an app feel grabby.
    func requestRemindersAccess() async -> Access {
        let store = makeStore()

        do {
            if #available(macOS 14.0, *) {
                _ = try await store.requestFullAccessToReminders()
            } else {
                _ = try await store.requestAccess(to: .reminder)
            }
        } catch {}

        return remindersAccess
    }

    // MARK: - Reading

    /// Every event in the window, converted.
    ///
    /// Empty when access has not been granted. Never an error: a module
    /// without permission shows its explanation, and the island shows
    /// nothing (TC-CAL-001).
    func events(from date: Date = Date()) -> [CalendarEvent] {
        guard access == .granted, let store else { return [] }

        let predicate = store.predicateForEvents(
            withStart: date.addingTimeInterval(-6 * 3_600),
            end: date.addingTimeInterval(window),
            calendars: nil
        )

        return store.events(matching: predicate).map(CalendarEvent.init(_:))
    }

    /// Incomplete reminders due within the window, soonest first.
    ///
    /// `fetchReminders` is callback-based and has no async form, so it is
    /// bridged here rather than at every call site.
    func reminders(from date: Date = Date()) async -> [CalendarReminder] {
        guard remindersAccess == .granted, let store else { return [] }

        // `EKEventStore` is documented as safe to use from any thread and is
        // not annotated `Sendable` in the macOS 14 SDK, so handing it to
        // `withCheckedContinuation` — whose closure is `sending` — reads as a
        // data race there. It is not one: the store outlives the call, and
        // `fetchReminders` is its own asynchronous API.
        nonisolated(unsafe) let reader = store

        let predicate = reader.predicateForIncompleteReminders(
            withDueDateStarting: nil,
            ending: date.addingTimeInterval(window),
            calendars: nil
        )

        // Converted inside the callback, which is not on the main actor: an
        // `EKReminder` is not `Sendable` and must not cross back. The value
        // type is what leaves.
        let fetched: [CalendarReminder] = await withCheckedContinuation { continuation in
            reader.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: (reminders ?? []).map(CalendarReminder.init(_:)))
            }
        }

        return fetched.sorted { lhs, rhs in
            switch (lhs.dueDate, rhs.dueDate) {
            case let (left?, right?): left < right
            case (nil, _): false
            case (_, nil): true
            }
        }
    }

    /// Marks a reminder done. Returns false if it could not be saved, which
    /// the view shows rather than silently ticking a box that stays unticked.
    @discardableResult
    func complete(_ reminder: CalendarReminder) -> Bool {
        guard remindersAccess == .granted, let store else { return false }
        guard let stored = store.calendarItem(withIdentifier: reminder.id) as? EKReminder else {
            return false
        }

        stored.isCompleted = true
        stored.completionDate = Date()

        do {
            try store.save(stored, commit: true)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Lifecycle

    /// Starts watching. Genuine push — EventKit posts this when anything in
    /// any calendar changes, so there is no polling here (`CLAUDE.md` §5.1).
    func start() {
        let store = makeStore()

        guard observer == nil else { return }

        observer = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: store,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.onChange?()
            }
        }
    }

    /// Releases the store itself, not only the observer.
    ///
    /// An `EKEventStore` keeps a connection to `calaccessd` open for as long
    /// as it exists. Dropping the observer and keeping the store would leave
    /// a switched-off module holding a system resource, which is the exact
    /// thing `CLAUDE.md` §5.1 forbids.
    func stop() {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
        observer = nil
        store = nil
    }

    private func makeStore() -> EKEventStore {
        if let store { return store }
        let created = EKEventStore()
        store = created
        return created
    }
}

// MARK: - Conversion

extension CalendarEvent {

    /// Flattens an `EKEvent` at the moment it is read.
    ///
    /// `EKEvent` is a live object over a store that changes underneath it;
    /// reading one later is undefined and reading one off the main actor is
    /// worse. Everything the island needs is copied out here, once.
    init(_ event: EKEvent) {
        self.init(
            id: event.eventIdentifier ?? UUID().uuidString,
            title: event.title ?? String(localized: "Busy"),
            startDate: event.startDate ?? Date(),
            endDate: event.endDate ?? event.startDate ?? Date(),
            isAllDay: event.isAllDay,
            isCancelled: event.status == .canceled,
            isTentative: event.status == .tentative,
            calendarTitle: event.calendar?.title ?? "",
            calendarColor: event.calendar?.color.flatMap { RGBColor($0.cgColor) },
            location: event.location,
            notes: event.notes,
            url: event.url,
            attendeeCount: event.attendees?.count ?? 0
        )
    }
}

extension RGBColor {

    /// EventKit hands back an `NSColor` in whatever space the calendar was
    /// created in. Converting to sRGB can fail for an exotic profile, and a
    /// calendar with no dot beats a crash.
    init?(_ color: CGColor) {
        guard
            let converted = color.converted(
                to: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                intent: .defaultIntent,
                options: nil
            ),
            let components = converted.components,
            components.count >= 3
        else { return nil }

        self.init(
            red: Double(components[0]),
            green: Double(components[1]),
            blue: Double(components[2]),
            alpha: Double(converted.alpha)
        )
    }
}

/// A reminder, flattened for the same reason events are.
struct CalendarReminder: Equatable, Sendable, Identifiable {
    let id: String
    let title: String
    let dueDate: Date?
    let isOverdue: Bool

    init(id: String, title: String, dueDate: Date?, isOverdue: Bool) {
        self.id = id
        self.title = title
        self.dueDate = dueDate
        self.isOverdue = isOverdue
    }

    init(_ reminder: EKReminder) {
        let due = reminder.dueDateComponents?.date
        self.init(
            id: reminder.calendarItemIdentifier,
            title: reminder.title ?? String(localized: "Reminder"),
            dueDate: due,
            isOverdue: due.map { $0 < Date() } ?? false
        )
    }
}
