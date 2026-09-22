import Foundation

/// One event, flattened out of EventKit.
///
/// `EKEvent` is a class, it is not `Sendable`, and reading one after its
/// store has changed underneath you is undefined. Everything that decides
/// *what to say about an event* works on this value instead, which is why
/// the agenda rules can be tested without a calendar — and CI has none.
///
/// The module layer builds these in `EventKitBridge`; nothing else may.
public struct CalendarEvent: Equatable, Sendable, Identifiable {

    /// EventKit's `eventIdentifier`. Stable across a refresh, which is what
    /// lets the island update a countdown in place rather than pushing a
    /// second one (TC-CAL-002).
    ///
    /// A recurring event shares one identifier across every occurrence, so
    /// the activity id is built from this *and* the start date.
    public let id: String

    public let title: String
    public let startDate: Date
    public let endDate: Date

    /// All-day events never get a countdown (TC-CAL-003). "Alice's birthday
    /// starts in 4 hours" is noise, and it is noise that would hold the
    /// island for most of a working day.
    public let isAllDay: Bool

    /// EventKit's status. A cancelled event is withdrawn rather than merely
    /// stopped from appearing, because it may already be on screen when the
    /// organiser calls it off (TC-CAL-007).
    public let isCancelled: Bool

    /// Set for an event you were invited to and have not answered. Shown in
    /// the agenda, but never given a countdown — you have not said you are
    /// going.
    public let isTentative: Bool

    /// The calendar it came from, for the agenda's colour dot and for the
    /// per-calendar filter in Preferences.
    public let calendarTitle: String

    /// sRGB components of the calendar's colour, 0–1. Not an `NSColor`:
    /// Core may not import AppKit (`CLAUDE.md` §3).
    public let calendarColor: RGBColor?

    public let location: String?

    /// Where a meeting link may be hiding. All three are searched, in the
    /// order EventKit fills them in reliably — see `MeetingLink.detect`.
    public let notes: String?
    public let url: URL?

    public let attendeeCount: Int

    public init(
        id: String,
        title: String,
        startDate: Date,
        endDate: Date,
        isAllDay: Bool = false,
        isCancelled: Bool = false,
        isTentative: Bool = false,
        calendarTitle: String = "",
        calendarColor: RGBColor? = nil,
        location: String? = nil,
        notes: String? = nil,
        url: URL? = nil,
        attendeeCount: Int = 0
    ) {
        self.id = id
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.isAllDay = isAllDay
        self.isCancelled = isCancelled
        self.isTentative = isTentative
        self.calendarTitle = calendarTitle
        self.calendarColor = calendarColor
        self.location = location
        self.notes = notes
        self.url = url
        self.attendeeCount = attendeeCount
    }

    /// The meeting this event joins, if it has one. Computed rather than
    /// stored so that a change to the detector's rules applies to events
    /// already in memory.
    public var meeting: MeetingLink? {
        MeetingLink.detect(location: location, notes: notes, url: url)
    }

    public var duration: Duration {
        .seconds(endDate.timeIntervalSince(startDate))
    }

    public func isRunning(at date: Date) -> Bool {
        startDate <= date && date < endDate
    }

    /// Whether the event can hold the island at all.
    ///
    /// Three rules in one place, because "which events are eligible" is
    /// asked by the countdown, by the pre-call camera check (module 9) and
    /// by the agenda's own "next" marker, and they must not drift apart.
    public var isCountdownEligible: Bool {
        !isAllDay && !isCancelled && !isTentative
    }
}

/// A colour without AppKit.
///
/// `PerchCore` may not import AppKit, and an `NSColor` is the only thing
/// EventKit will give you for a calendar. The module converts; Core stores
/// the four numbers.
public struct RGBColor: Equatable, Sendable, Hashable, Codable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public let alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }
}
