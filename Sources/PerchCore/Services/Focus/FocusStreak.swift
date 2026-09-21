import Foundation

/// How many focus sessions, and how many days in a row.
///
/// The counting rule is the whole of TC-FOC-005, and it is the one thing
/// people notice when it is wrong: **the streak counts days, not sessions.**
/// Four sessions on Tuesday is one day of streak, not four.
public struct FocusStreak: Equatable, Sendable, Codable {

    /// Completed work sessions, all time. Breaks are not sessions.
    public private(set) var totalSessions = 0

    /// Completed work sessions today.
    public private(set) var sessionsToday = 0

    /// Consecutive days with at least one completed work session.
    public private(set) var streakDays = 0

    /// The day the last session was completed, normalised to its start.
    public private(set) var lastSessionDay: Date?

    public init() {}

    /// Records one completed work session.
    ///
    /// The calendar is injected rather than taken from `.current` so that the
    /// tests can pin a time zone. A streak that breaks when somebody flies to
    /// another country is a bug people report and nobody can reproduce.
    public mutating func recordCompletedSession(
        at date: Date,
        calendar: Calendar = .current
    ) {
        let today = calendar.startOfDay(for: date)
        totalSessions += 1

        guard let lastSessionDay else {
            streakDays = 1
            sessionsToday = 1
            self.lastSessionDay = today
            return
        }

        let daysBetween =
            calendar.dateComponents(
                [.day],
                from: lastSessionDay,
                to: today
            ).day ?? 0

        switch daysBetween {
        case 0:
            // Same day. More sessions, same streak — TC-FOC-005.
            sessionsToday += 1
        case 1:
            streakDays += 1
            sessionsToday = 1
        default:
            // A missed day, or the clock went backwards. Either way this is
            // the first day of a new streak rather than a continuation.
            streakDays = 1
            sessionsToday = 1
        }

        self.lastSessionDay = today
    }

    /// Today's count, as of a given moment.
    ///
    /// `sessionsToday` is stored rather than derived, so it has to be read
    /// through this: at one minute past midnight the stored number is
    /// yesterday's, and nobody wants to be told they have already done four
    /// sessions today.
    public func sessions(on date: Date, calendar: Calendar = .current) -> Int {
        guard
            let lastSessionDay,
            calendar.isDate(lastSessionDay, inSameDayAs: date)
        else { return 0 }

        return sessionsToday
    }

    /// The streak, as of a given moment.
    ///
    /// A streak survives today and yesterday — you have not broken it by not
    /// having started yet this morning — and is gone by the day after.
    public func streak(on date: Date, calendar: Calendar = .current) -> Int {
        guard let lastSessionDay else { return 0 }

        let daysBetween =
            calendar.dateComponents(
                [.day],
                from: lastSessionDay,
                to: calendar.startOfDay(for: date)
            ).day ?? 0

        return daysBetween <= 1 ? streakDays : 0
    }
}
