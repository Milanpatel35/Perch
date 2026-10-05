import Foundation

/// The days a calendar view draws, and which events fall on each.
///
/// Pure date arithmetic on a `Calendar` that is passed in, so the first day
/// of the week, the time zone and the month lengths are the user's — and
/// so every rule here is a unit test with a fixed calendar rather than
/// whatever the CI runner's locale happens to be.
public struct CalendarGrid: Equatable, Sendable {

    /// Week shows seven days and their events; Month shows the grid.
    public enum Mode: String, CaseIterable, Codable, Sendable {
        case week
        case month
    }

    public struct Day: Equatable, Sendable, Identifiable {
        public let date: Date
        /// False for the days before and after the month that fill out the
        /// first and last weeks of a month grid. Always true in a week.
        public let isInPeriod: Bool

        public var id: Date { date }
    }

    public let mode: Mode
    /// Every day drawn: 7 for a week, a whole number of weeks for a month.
    public let days: [Day]
    /// The first instant drawn and the instant after the last, for fetching
    /// exactly the events the grid can show.
    public let interval: DateInterval

    public init(mode: Mode, containing date: Date, calendar: Calendar) {
        self.mode = mode

        switch mode {
        case .week:
            let start = Self.startOfWeek(containing: date, calendar: calendar)
            let days = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
            self.days = days.map { Day(date: $0, isInPeriod: true) }

        case .month:
            let monthStart =
                calendar.date(from: calendar.dateComponents([.year, .month], from: date))
                ?? calendar.startOfDay(for: date)
            let month = calendar.component(.month, from: monthStart)
            let start = Self.startOfWeek(containing: monthStart, calendar: calendar)

            var days: [Day] = []
            var day = start
            // Whole weeks, until the month is covered.
            repeat {
                for _ in 0..<7 {
                    days.append(
                        Day(date: day, isInPeriod: calendar.component(.month, from: day) == month))
                    day = calendar.date(byAdding: .day, value: 1, to: day) ?? day
                }
            } while calendar.component(.month, from: day) == month
            self.days = days
        }

        let first = days.first?.date ?? calendar.startOfDay(for: date)
        let end =
            days.last.flatMap { calendar.date(byAdding: .day, value: 1, to: $0.date) }
            ?? first
        self.interval = DateInterval(start: first, end: end)
    }

    /// The same view one period earlier or later — a week, or a month.
    public static func shifting(
        _ date: Date,
        by periods: Int,
        mode: Mode,
        calendar: Calendar
    ) -> Date {
        switch mode {
        case .week: calendar.date(byAdding: .weekOfYear, value: periods, to: date) ?? date
        case .month: calendar.date(byAdding: .month, value: periods, to: date) ?? date
        }
    }

    /// The events on one day, in the order they start, all-day ones first.
    /// An event that spans several days is on each of them.
    public static func events(
        _ events: [CalendarEvent],
        on day: Date,
        calendar: Calendar
    ) -> [CalendarEvent] {
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }

        return
            events
            .filter { !$0.isCancelled && $0.startDate < end && $0.endDate > start }
            .sorted { lhs, rhs in
                if lhs.isAllDay != rhs.isAllDay { return lhs.isAllDay }
                return lhs.startDate < rhs.startDate
            }
    }

    private static func startOfWeek(containing date: Date, calendar: Calendar) -> Date {
        let day = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: day)
        let back = (weekday - calendar.firstWeekday + 7) % 7
        return calendar.date(byAdding: .day, value: -back, to: day) ?? day
    }
}
