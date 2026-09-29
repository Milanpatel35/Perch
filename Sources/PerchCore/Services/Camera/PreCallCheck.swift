import Foundation

/// "You're on mute / your hair" — the preview that opens by itself just
/// before a meeting starts.
///
/// `docs/FEATURES.md` §9 records this as the camera module's one original
/// idea, and `docs/COMPARISON.md` records that nobody in the paid field has
/// it. It is also the one place two modules meet, so the rule about *when*
/// it fires is a value with no clock and no camera (TC-CAM-014).
public struct PreCallCheck: Equatable, Sendable {

    public struct Configuration: Equatable, Sendable, Codable {
        public var isEnabled = true

        /// How long before the meeting the preview opens.
        ///
        /// Forty-five seconds. Long enough to do something about what you
        /// see, short enough that it is not a second countdown — the
        /// calendar module already owns that job.
        public var lead: Duration = .seconds(45)

        /// How long it stays up if you do nothing.
        public var duration: Duration = .seconds(12)

        /// Only for meetings with a join link.
        ///
        /// On, because a check before a phone call or a desk booking is
        /// noise. Off is for people whose meetings are all in person and who
        /// still want the mirror.
        public var requiresMeetingLink = true

        public init() {}
    }

    public private(set) var configuration: Configuration

    /// Events already checked, so the preview opens once per meeting rather
    /// than every time the calendar refreshes.
    private var checked: Set<String> = []

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    public mutating func setConfiguration(_ configuration: Configuration) {
        self.configuration = configuration
    }

    /// Whether to open the preview for a meeting starting at this moment.
    ///
    /// Takes the facts rather than the event, so the camera module needs to
    /// know nothing about `CalendarEvent` — and so this still answers
    /// correctly when the calendar module is switched off, which is
    /// TC-CAM-015: nothing calls it, and nothing breaks.
    public mutating func shouldCheck(
        eventID: String,
        startsAt: Date,
        hasMeetingLink: Bool,
        now: Date
    ) -> Bool {
        guard configuration.isEnabled else { return false }
        guard !configuration.requiresMeetingLink || hasMeetingLink else { return false }
        guard !checked.contains(eventID) else { return false }

        let untilStart = startsAt.timeIntervalSince(now)

        // Inside the lead, and not already started. A check that fires two
        // minutes into a call is somebody's camera turning on unasked.
        guard untilStart > 0, untilStart <= configuration.lead.seconds else { return false }

        checked.insert(eventID)
        return true
    }

    /// Forgets what has been checked. Called when the module is switched
    /// off, so switching it back on does not silently skip the next meeting.
    public mutating func reset() {
        checked.removeAll()
    }

    /// Bounded, for the same reason the notification policy's seen list is:
    /// a set that only grows in a module that runs all day is a leak.
    public mutating func forget(before date: Date, keeping limit: Int = 32) {
        guard checked.count > limit else { return }
        checked.removeAll()
    }
}
