import Foundation

/// Which event the island is showing, and when to look again.
///
/// Every rule about the countdown lives here and nowhere else: what counts
/// as "next", when the countdown appears, what happens to the two events
/// that overlap, and what a cancellation does to one already on screen
/// (TC-CAL-002, TC-CAL-003, TC-CAL-006, TC-CAL-007).
///
/// It is a value, and it has no clock of its own. The module asks it
/// questions with a date; `nextChange(after:)` is what lets the service run
/// on one scheduled wake-up rather than a ticking timer (`CLAUDE.md` §5.1).
public struct Agenda: Equatable, Sendable {

    public struct Configuration: Equatable, Sendable, Codable {

        /// How long before an event starts the countdown appears.
        ///
        /// Five minutes by default: long enough to walk to a meeting room,
        /// short enough that it is not sitting in the notch all morning.
        public var leadTime: Duration = .seconds(5 * 60)

        /// Whether the island keeps the event up while it runs.
        ///
        /// On, because the running event is what carries the mute and leave
        /// controls. Off leaves the countdown as an alert that vanishes at
        /// the moment the meeting starts, which several people will prefer.
        public var showsDuringEvent = true

        /// Calendars the module ignores entirely, by title.
        ///
        /// Titles rather than identifiers: an identifier is stable but
        /// unreadable, and this set is written straight into the defaults
        /// where a person may well go and look at it.
        public var excludedCalendars: Set<String> = []

        /// Whether tentative invitations appear in the agenda list. They are
        /// never given a countdown either way — see
        /// `CalendarEvent.isCountdownEligible`.
        public var showsTentative = true

        public init() {}
    }

    public private(set) var configuration: Configuration

    /// Every event in the window the bridge fetched, ascending by start.
    /// All-day and cancelled events are kept: the agenda list shows them,
    /// and only the countdown rules exclude them.
    public private(set) var events: [CalendarEvent] = []

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    public mutating func setConfiguration(_ configuration: Configuration) {
        self.configuration = configuration
    }

    /// Replaces the whole set. EventKit hands back a snapshot rather than a
    /// diff, and so does this — trying to merge two snapshots by identifier
    /// is how a deleted event survives a refresh.
    public mutating func replace(with events: [CalendarEvent]) {
        self.events =
            events
            .filter { !configuration.excludedCalendars.contains($0.calendarTitle) }
            .sorted { lhs, rhs in
                lhs.startDate == rhs.startDate
                    ? lhs.title < rhs.title
                    : lhs.startDate < rhs.startDate
            }
    }

    // MARK: - What is on the island

    /// The event the island should be showing, if any.
    ///
    /// A running event wins over one that has not started, which is what
    /// settles TC-CAL-006: two meetings that overlap show the one you are
    /// already in, and the other waits its turn rather than covering it.
    public func presented(at date: Date) -> CalendarEvent? {
        if configuration.showsDuringEvent, let running = running(at: date) {
            return running
        }
        return upcoming(at: date).first { withinLeadTime($0, at: date) }
    }

    /// Everything eligible that is not the one being presented, in order.
    /// The island's stack badge counts these (TC-CAL-006).
    public func queued(at date: Date) -> [CalendarEvent] {
        guard let presented = presented(at: date) else { return [] }

        return
            eligible
            .filter { $0.endDate > date }
            .filter { $0.id != presented.id || $0.startDate != presented.startDate }
    }

    /// The earliest running event, if you are in one.
    ///
    /// Earliest rather than latest: the call you joined first is the call
    /// you are on, even when a 30-minute block starts inside a 60-minute one.
    public func running(at date: Date) -> CalendarEvent? {
        eligible.first { $0.isRunning(at: date) }
    }

    /// Eligible events that have not started, soonest first.
    public func upcoming(at date: Date) -> [CalendarEvent] {
        eligible.filter { $0.startDate > date }
    }

    /// What the expanded island lists: today and tomorrow, all-day events
    /// included, in the order they happen (`docs/FEATURES.md` §5).
    public func peek(at date: Date, calendar: Calendar = .current) -> [CalendarEvent] {
        let start = calendar.startOfDay(for: date)
        guard let end = calendar.date(byAdding: .day, value: 2, to: start) else { return events }

        return events.filter { event in
            guard !event.isCancelled else { return false }
            guard configuration.showsTentative || !event.isTentative else { return false }
            // An event already over is not agenda, it is history — except an
            // all-day one, which is "today" for the whole of today.
            let hasPassed = event.endDate <= date && !event.isAllDay
            return !hasPassed && event.startDate < end
        }
    }

    // MARK: - When to look again

    /// The next moment the answer to `presented(at:)` could change.
    ///
    /// This is the whole of the no-timer design. The service sleeps until
    /// this date, re-reads, and sleeps again; between two events it is not
    /// running any code at all. `nil` means nothing is scheduled and there
    /// is nothing to wake up for.
    ///
    /// Three kinds of moment qualify: an event's lead time beginning, an
    /// event starting, and an event ending. A date that has already passed
    /// is never returned, because a wake-up in the past is a busy loop.
    public func nextChange(after date: Date) -> Date? {
        var candidates: [Date] = []

        for event in eligible {
            let leadsAt = event.startDate.addingTimeInterval(-configuration.leadTime.seconds)
            candidates.append(contentsOf: [leadsAt, event.startDate, event.endDate])
        }

        return candidates.filter { $0 > date }.min()
    }

    // MARK: - Plumbing

    private var eligible: [CalendarEvent] {
        events.filter(\.isCountdownEligible)
    }

    private func withinLeadTime(_ event: CalendarEvent, at date: Date) -> Bool {
        event.startDate.timeIntervalSince(date) <= configuration.leadTime.seconds
    }
}
