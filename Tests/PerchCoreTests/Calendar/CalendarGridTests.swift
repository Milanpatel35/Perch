import XCTest

@testable import PerchCore

/// Covers `TEST-PLAN.md` TC-CAL-020 … 022 — the days the island's calendar
/// draws, and which events land on each.
final class CalendarGridTests: XCTestCase {

    /// Monday-first, UTC, Gregorian: fixed, so no runner's locale decides.
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        calendar.firstWeekday = 2
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))
            ?? Date()
    }

    private func event(
        _ id: String, _ start: Date, _ end: Date, allDay: Bool = false
    ) -> CalendarEvent {
        CalendarEvent(id: id, title: id, startDate: start, endDate: end, isAllDay: allDay)
    }

    // MARK: - TC-CAL-020

    func test_TC_CAL_020_aWeekIsSevenDaysFromTheUsersFirstWeekday() {
        // Sunday 4 October 2026 sits at the end of a Monday-first week.
        let grid = CalendarGrid(mode: .week, containing: date(2026, 10, 4, 14), calendar: calendar)

        XCTAssertEqual(grid.days.count, 7)
        XCTAssertEqual(grid.days.first?.date, date(2026, 9, 28))
        XCTAssertEqual(grid.days.last?.date, date(2026, 10, 4))
        XCTAssertTrue(grid.days.allSatisfy(\.isInPeriod))
        XCTAssertEqual(
            grid.interval, DateInterval(start: date(2026, 9, 28), end: date(2026, 10, 5)))
    }

    func test_TC_CAL_020_aSundayFirstCalendarStartsOnSunday() {
        var sunday = calendar
        sunday.firstWeekday = 1
        let grid = CalendarGrid(mode: .week, containing: date(2026, 10, 7), calendar: sunday)

        XCTAssertEqual(grid.days.first?.date, date(2026, 10, 4))
    }

    // MARK: - TC-CAL-021

    func test_TC_CAL_021_aMonthIsWholeWeeksCoveringEveryDayOfIt() {
        let grid = CalendarGrid(mode: .month, containing: date(2026, 10, 15), calendar: calendar)

        XCTAssertEqual(grid.days.count % 7, 0)
        XCTAssertEqual(grid.days.filter(\.isInPeriod).count, 31)
        // October 2026 begins on a Thursday: three September days lead in.
        XCTAssertEqual(grid.days.first?.date, date(2026, 9, 28))
        XCTAssertFalse(grid.days[0].isInPeriod)
        XCTAssertTrue(grid.days[3].isInPeriod)
    }

    func test_TC_CAL_021_aMonthStartingOnTheFirstWeekdayHasNoLeadIn() {
        // June 2026 begins on a Monday.
        let grid = CalendarGrid(mode: .month, containing: date(2026, 6, 20), calendar: calendar)

        XCTAssertEqual(grid.days.first?.date, date(2026, 6, 1))
        XCTAssertTrue(grid.days[0].isInPeriod)
    }

    func test_TC_CAL_021_shiftingMovesByAWeekOrAMonth() {
        let day = date(2026, 1, 31)

        XCTAssertEqual(
            CalendarGrid.shifting(day, by: 1, mode: .week, calendar: calendar), date(2026, 2, 7))
        XCTAssertEqual(
            CalendarGrid.shifting(day, by: 1, mode: .month, calendar: calendar), date(2026, 2, 28))
        XCTAssertEqual(
            CalendarGrid.shifting(day, by: -1, mode: .month, calendar: calendar), date(2025, 12, 31)
        )
    }

    // MARK: - TC-CAL-022

    func test_TC_CAL_022_eventsOnADayAreAllDayFirstThenByStart() {
        let day = date(2026, 10, 5)
        let events = [
            event("late", date(2026, 10, 5, 16), date(2026, 10, 5, 17)),
            event("early", date(2026, 10, 5, 9), date(2026, 10, 5, 10)),
            event("birthday", day, date(2026, 10, 6), allDay: true),
            event("tomorrow", date(2026, 10, 6, 9), date(2026, 10, 6, 10))
        ]

        XCTAssertEqual(
            CalendarGrid.events(events, on: day, calendar: calendar).map(\.id),
            ["birthday", "early", "late"]
        )
    }

    func test_TC_CAL_022_aMultiDayEventIsOnEachDayAndCancelledOnesOnNone() {
        let trip = event("trip", date(2026, 10, 5, 12), date(2026, 10, 7, 12))
        let cancelled = CalendarEvent(
            id: "off", title: "off",
            startDate: date(2026, 10, 6, 9), endDate: date(2026, 10, 6, 10),
            isCancelled: true
        )

        for day in [5, 6, 7] {
            XCTAssertEqual(
                CalendarGrid.events([trip, cancelled], on: date(2026, 10, day), calendar: calendar)
                    .map(\.id),
                ["trip"]
            )
        }
        XCTAssertTrue(
            CalendarGrid.events([trip], on: date(2026, 10, 8), calendar: calendar).isEmpty)
    }
}
