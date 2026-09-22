import AppKit
import Combine
import Defaults
import KeyboardShortcuts
import PerchCore
import SwiftUI

/// Module 5 — calendar and meetings.
///
/// **Nothing ticks.** EventKit pushes a notification when any calendar
/// changes, and the only other thing that can change the answer is time
/// passing — which `Agenda.nextChange(after:)` computes exactly. The module
/// sleeps until that moment, re-reads, and sleeps again. Between two
/// meetings it is running no code at all (`CLAUDE.md` §5.1).
///
/// The one thing it re-reads on a schedule is the meeting control state,
/// and only while a call is actually running and the island is showing it —
/// the same rule the system stats sampler follows.
@MainActor
final class CalendarService: ObservableObject, PerchModule {

    static let moduleID: ModuleID = .calendar

    @Published private(set) var agenda = Agenda()
    @Published private(set) var access: EventKitBridge.Access = .notDetermined
    @Published private(set) var remindersAccess: EventKitBridge.Access = .notDetermined
    @Published private(set) var reminders: [CalendarReminder] = []

    private(set) var isActive = false

    private let island: IslandController
    private let bridge = EventKitBridge()
    private let controls = MeetingControls()

    /// The single scheduled wake-up. One at a time, cancelled and replaced
    /// whenever the agenda changes — the focus timer made the same call for
    /// the same reason.
    private var wakeUp: Task<Void, Never>?

    /// Refreshes the mute and camera state while a call is running.
    ///
    /// The one repeating timer in the module, and it exists only while
    /// there is a running meeting with drivable controls on screen. Reading
    /// the menu bar is how the island stays in step with a mute pressed
    /// inside the meeting app (TC-CAL-009), and there is no notification for
    /// that — the same bind the clipboard is in (ADR 0003).
    private var controlPoll: Task<Void, Never>?

    /// Which event, if any, already had its "starting now" alert. A meeting
    /// announces itself once; re-announcing on every refresh would put it
    /// back on screen every time a calendar syncs.
    private var announced: Set<String> = []

    /// The activity currently on the island, so a change of event can
    /// withdraw the one it replaces.
    private var presentedID: ActivityID?

    /// Called on every refresh with the event that is coming up, if any.
    ///
    /// The camera module's pre-call check hangs off this
    /// (`docs/FEATURES.md` §9). Wired by `PerchModuleRegistry`, so neither
    /// module knows the other exists — and with the camera switched off it
    /// is simply nil.
    var onMeetingApproaching: (@MainActor (CalendarEvent) -> Void)?

    private var observers: [NSObjectProtocol] = []

    private let now: @MainActor () -> Date

    init(island: IslandController, now: @escaping @MainActor () -> Date = { Date() }) {
        self.island = island
        self.now = now
        self.agenda = Agenda(configuration: Defaults[.agendaConfiguration])
    }

    // MARK: - PerchModule

    func activate() {
        guard !isActive else { return }
        isActive = true

        access = bridge.access
        remindersAccess = bridge.remindersAccess

        bridge.onChange = { [weak self] in
            self?.refresh()
        }

        // Permission is requested here — on enable, with the module's own
        // explanation already on screen — and never at launch (TC-PRV-002).
        Task { [weak self] in
            guard let self else { return }
            if bridge.access == .notDetermined {
                access = await bridge.requestAccess()
            }
            guard isActive else { return }
            bridge.start()
            refresh()
        }

        registerShortcut()
        observeWake()
    }

    func deactivate() {
        guard isActive else { return }
        isActive = false

        wakeUp?.cancel()
        wakeUp = nil
        controlPoll?.cancel()
        controlPoll = nil

        bridge.onChange = nil
        bridge.stop()

        for observer in observers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observers.removeAll()

        KeyboardShortcuts.disable(.joinMeeting)
        onMeetingApproaching = nil

        agenda.replace(with: [])
        reminders = []
        announced.removeAll()
        presentedID = nil

        island.withdrawAll(from: .calendar)
    }

    // MARK: - Reading

    /// Re-reads the store and puts the answer on the island.
    ///
    /// Called by EventKit's change notification, by the scheduled wake-up,
    /// and on waking from sleep. All three are the same work, and doing it
    /// twice is harmless — `submit` updates in place.
    func refresh() {
        guard isActive else { return }

        access = bridge.access
        agenda.replace(with: bridge.events(from: now()))

        present()
        schedule()
        refreshReminders()
    }

    private func refreshReminders() {
        remindersAccess = bridge.remindersAccess
        guard remindersAccess == .granted else {
            reminders = []
            return
        }

        Task { [weak self] in
            guard let self else { return }
            let fetched = await bridge.reminders(from: now())
            guard isActive else { return }
            reminders = fetched
        }
    }

    // MARK: - Presenting

    private func present() {
        guard isActive else { return }

        guard let event = agenda.presented(at: now()) else {
            island.withdrawAll(from: .calendar)
            presentedID = nil
            stopControlPolling()
            return
        }

        let isRunning = event.isRunning(at: now())
        let state = isRunning ? controls.state(for: event.meeting) : MeetingControlState()

        // Before it starts, and only then. The camera decides whether that
        // is close enough to be worth opening for; this only reports.
        if !isRunning {
            onMeetingApproaching?(event)
        }

        // The one interruption: the moment it starts, announced once.
        if isRunning, !announced.contains(announcementKey(for: event)) {
            announced.insert(announcementKey(for: event))
            island.submit(MeetingStartingActivity(event: event))
        }

        let activity = CalendarActivity(
            event: event,
            queuedCount: agenda.queued(at: now()).count,
            isRunning: isRunning,
            controls: state
        )

        // The activity id carries the event in it, so a different event is a
        // different activity rather than an update in place. Withdrawing the
        // previous one by name is what stops yesterday's countdown sitting in
        // the queue for ever; `withdrawAll` would take the announcement with
        // it, which is why this is done one id at a time.
        if let presentedID, presentedID != activity.id {
            island.withdraw(presentedID)
        }
        presentedID = activity.id

        island.submit(activity)

        if state.isActionable {
            startControlPolling()
        } else {
            stopControlPolling()
        }
    }

    private func announcementKey(for event: CalendarEvent) -> String {
        "\(event.id).\(event.startDate.timeIntervalSince1970)"
    }

    // MARK: - The single wake-up

    private func schedule() {
        wakeUp?.cancel()
        wakeUp = nil

        guard isActive, let next = agenda.nextChange(after: now()) else { return }

        let delay = max(0, next.timeIntervalSince(now()))
        wakeUp = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }

    /// A Mac asleep through the start of a meeting wakes to the right
    /// answer: `Task.sleep` does not run while the machine is asleep, so
    /// waking re-reads rather than waiting out a delay computed yesterday.
    private func observeWake() {
        let center = NSWorkspace.shared.notificationCenter
        observers.append(
            center.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.refresh()
                }
            }
        )
    }

    // MARK: - Meeting controls

    /// Two seconds. Fast enough that pressing mute in the Zoom window and
    /// glancing at the island agree, slow enough to be invisible in Activity
    /// Monitor — it is one AX query against one already-running app.
    private static let controlInterval: Duration = .seconds(2)

    private func startControlPolling() {
        guard controlPoll == nil else { return }

        controlPoll = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.controlInterval)
                guard !Task.isCancelled else { return }
                self?.refreshControls()
            }
        }
    }

    private func stopControlPolling() {
        controlPoll?.cancel()
        controlPoll = nil
    }

    /// Re-reads the menu bar and updates the activity in place. Withdraws
    /// the whole thing if the call has ended, which is TC-CAL-010: leaving
    /// from the island collapses it because the menu it was driving is gone.
    private func refreshControls() {
        guard isActive, let event = agenda.presented(at: now()), event.isRunning(at: now()) else {
            stopControlPolling()
            return
        }

        let state = controls.state(for: event.meeting)

        island.submit(
            CalendarActivity(
                event: event,
                queuedCount: agenda.queued(at: now()).count,
                isRunning: true,
                controls: state
            )
        )

        if !state.isActionable {
            stopControlPolling()
        }
    }

    // MARK: - Actions

    /// Opens the meeting. The native client where there is one, the browser
    /// where there is not — `MeetingLink.launchURL` decides.
    func join(_ event: CalendarEvent) {
        guard let meeting = event.meeting else { return }
        NSWorkspace.shared.open(meeting.launchURL)
        island.send(.collapseRequested)
    }

    /// Joins whatever is on the island. Bound to the global shortcut, so it
    /// works without the island being open at all.
    func joinCurrent() {
        guard isActive, let event = agenda.presented(at: now()) else { return }
        join(event)
    }

    func toggleMute() {
        withRunningMeeting { controls.toggleMute(for: $0) }
    }

    func toggleCamera() {
        withRunningMeeting { controls.toggleCamera(for: $0) }
    }

    func leaveMeeting() {
        withRunningMeeting { controls.leave(for: $0) }
    }

    /// Asks for Accessibility, then re-reads immediately so the buttons come
    /// alive without the person having to press anything again.
    func requestAccessibility() {
        controls.requestTrust()
        refreshControls()
    }

    func enableReminders() {
        Task { [weak self] in
            guard let self else { return }
            remindersAccess = await bridge.requestRemindersAccess()
            refreshReminders()
        }
    }

    func complete(_ reminder: CalendarReminder) {
        guard bridge.complete(reminder) else { return }
        reminders.removeAll { $0.id == reminder.id }
    }

    func setConfiguration(_ configuration: Agenda.Configuration) {
        agenda.setConfiguration(configuration)
        Defaults[.agendaConfiguration] = configuration
        refresh()
    }

    /// Every calendar the store knows about, for the exclusion list in
    /// Preferences. Titles, because that is what the configuration stores.
    var calendarTitles: [String] {
        Array(Set(agenda.events.map(\.calendarTitle))).filter { !$0.isEmpty }.sorted()
    }

    private func withRunningMeeting(_ body: (MeetingLink) -> Bool) {
        guard
            isActive,
            let event = agenda.presented(at: now()),
            event.isRunning(at: now()),
            let meeting = event.meeting
        else { return }

        _ = body(meeting)
        refreshControls()
    }

    private func registerShortcut() {
        KeyboardShortcuts.onKeyUp(for: .joinMeeting) { [weak self] in
            MainActor.assumeIsolated {
                self?.joinCurrent()
            }
        }
        KeyboardShortcuts.enable(.joinMeeting)
    }
}

extension KeyboardShortcuts.Name {
    /// No default. A module that claims a global hotkey nobody asked for
    /// collides with something, and the collision is silent — the clipboard
    /// picker and the focus timer both made the same call.
    static let joinMeeting = Self("joinMeeting")
}
