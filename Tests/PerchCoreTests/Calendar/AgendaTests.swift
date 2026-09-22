import XCTest

@testable import PerchCore

/// Covers `TEST-PLAN.md` § CAL for the countdown rules — TC-CAL-002,
/// TC-CAL-003, TC-CAL-006 and TC-CAL-007.
///
/// No clock and no calendar permission: `Agenda` is a value, and every
/// question it answers takes the date as an argument. That is what makes
/// these run on a CI machine with no calendars at all.
final class AgendaTests: XCTestCase {

    private let noon = Date(timeIntervalSinceReferenceDate: 12 * 3_600)

    private func event(
        _ id: String,
        startsIn minutes: Double,
        lasting duration: Double = 30,
        isAllDay: Bool = false,
        isCancelled: Bool = false,
        isTentative: Bool = false,
        calendar: String = "Work"
    ) -> CalendarEvent {
        let start = noon.addingTimeInterval(minutes * 60)
        return CalendarEvent(
            id: id,
            title: id,
            startDate: start,
            endDate: start.addingTimeInterval(duration * 60),
            isAllDay: isAllDay,
            isCancelled: isCancelled,
            isTentative: isTentative,
            calendarTitle: calendar
        )
    }

    // MARK: - TC-CAL-002

    func test_TC_CAL_002_theCountdownFiresAtTheConfiguredLeadTime() {
        var agenda = Agenda()
        agenda.replace(with: [event("standup", startsIn: 10)])

        XCTAssertNil(agenda.presented(at: noon), "ten minutes out is outside the five-minute lead")

        let fiveMinutesBefore = noon.addingTimeInterval(5 * 60)
        XCTAssertEqual(agenda.presented(at: fiveMinutesBefore)?.id, "standup")
    }

    func test_TC_CAL_002_aLongerLeadTimeShowsItSooner() {
        var configuration = Agenda.Configuration()
        configuration.leadTime = .seconds(15 * 60)

        var agenda = Agenda(configuration: configuration)
        agenda.replace(with: [event("standup", startsIn: 10)])

        XCTAssertEqual(agenda.presented(at: noon)?.id, "standup")
    }

    /// The whole of the no-timer design: the service sleeps until this date
    /// and runs no code in between (`CLAUDE.md` §5.1).
    func test_TC_CAL_002_nextChangeIsTheLeadTimeThenTheStartThenTheEnd() throws {
        var agenda = Agenda()
        agenda.replace(with: [event("standup", startsIn: 10, lasting: 30)])

        let lead = try XCTUnwrap(agenda.nextChange(after: noon))
        XCTAssertEqual(lead.timeIntervalSince(noon), 5 * 60, accuracy: 0.001)

        let start = try XCTUnwrap(agenda.nextChange(after: lead))
        XCTAssertEqual(start.timeIntervalSince(noon), 10 * 60, accuracy: 0.001)

        let end = try XCTUnwrap(agenda.nextChange(after: start))
        XCTAssertEqual(end.timeIntervalSince(noon), 40 * 60, accuracy: 0.001)

        XCTAssertNil(
            agenda.nextChange(after: noon.addingTimeInterval(60 * 60)),
            "nothing left to wake up for"
        )
    }

    func test_TC_CAL_002_nextChangeNeverReturnsAMomentAlreadyPast() {
        var agenda = Agenda()
        agenda.replace(with: [event("over", startsIn: -120, lasting: 30)])

        XCTAssertNil(agenda.nextChange(after: noon))
    }

    // MARK: - TC-CAL-003

    func test_TC_CAL_003_anAllDayEventNeverGetsACountdown() {
        var agenda = Agenda()
        agenda.replace(with: [event("birthday", startsIn: 1, lasting: 1_440, isAllDay: true)])

        XCTAssertNil(agenda.presented(at: noon))
        XCTAssertNil(agenda.nextChange(after: noon))
    }

    func test_TC_CAL_003_anAllDayEventStillAppearsInTheAgendaList() {
        var agenda = Agenda()
        agenda.replace(with: [event("birthday", startsIn: 1, lasting: 1_440, isAllDay: true)])

        XCTAssertEqual(agenda.peek(at: noon).map(\.id), ["birthday"])
    }

    func test_TC_CAL_003_aTentativeInvitationGetsNoCountdownEither() {
        var agenda = Agenda()
        agenda.replace(with: [event("maybe", startsIn: 2, isTentative: true)])

        XCTAssertNil(agenda.presented(at: noon))
        XCTAssertEqual(agenda.peek(at: noon).map(\.id), ["maybe"])
    }

    // MARK: - TC-CAL-006

    func test_TC_CAL_006_theEarliestIsShownAndTheOtherIsQueued() {
        var agenda = Agenda()
        agenda.replace(with: [
            event("second", startsIn: 4),
            event("first", startsIn: 2)
        ])

        XCTAssertEqual(agenda.presented(at: noon)?.id, "first")
        XCTAssertEqual(agenda.queued(at: noon).map(\.id), ["second"])
    }

    /// A meeting you are already in beats one that has not started. The
    /// running call carries the mute and leave controls; losing it to a
    /// countdown for the next thing is exactly backwards.
    func test_TC_CAL_006_aRunningEventBeatsAnUpcomingOne() {
        var agenda = Agenda()
        agenda.replace(with: [
            event("running", startsIn: -10, lasting: 60),
            event("next", startsIn: 3)
        ])

        XCTAssertEqual(agenda.presented(at: noon)?.id, "running")
        XCTAssertEqual(agenda.queued(at: noon).map(\.id), ["next"])
    }

    func test_TC_CAL_006_theEarliestOfTwoRunningEventsWins() {
        var agenda = Agenda()
        agenda.replace(with: [
            event("outer", startsIn: -30, lasting: 60),
            event("inner", startsIn: -5, lasting: 30)
        ])

        XCTAssertEqual(agenda.presented(at: noon)?.id, "outer")
    }

    func test_TC_CAL_006_showsDuringEventOffDropsTheRunningEvent() {
        var configuration = Agenda.Configuration()
        configuration.showsDuringEvent = false

        var agenda = Agenda(configuration: configuration)
        agenda.replace(with: [event("running", startsIn: -10, lasting: 60)])

        XCTAssertNil(agenda.presented(at: noon))
    }

    // MARK: - TC-CAL-007

    func test_TC_CAL_007_aCancelledEventIsNotPresented() {
        var agenda = Agenda()
        agenda.replace(with: [event("standup", startsIn: 2)])
        XCTAssertEqual(agenda.presented(at: noon)?.id, "standup")

        // The organiser calls it off and the store hands back a new snapshot.
        agenda.replace(with: [event("standup", startsIn: 2, isCancelled: true)])

        XCTAssertNil(agenda.presented(at: noon))
        XCTAssertTrue(agenda.peek(at: noon).isEmpty)
    }

    func test_TC_CAL_007_aDeletedEventDoesNotSurviveARefresh() {
        var agenda = Agenda()
        agenda.replace(with: [event("standup", startsIn: 2)])
        agenda.replace(with: [])

        XCTAssertNil(agenda.presented(at: noon))
    }

    // MARK: - Filtering

    func test_anExcludedCalendarIsDroppedEntirely() {
        var configuration = Agenda.Configuration()
        configuration.excludedCalendars = ["Holidays"]

        var agenda = Agenda(configuration: configuration)
        agenda.replace(with: [
            event("standup", startsIn: 2, calendar: "Work"),
            event("diwali", startsIn: 2, calendar: "Holidays")
        ])

        XCTAssertEqual(agenda.events.map(\.id), ["standup"])
    }

    func test_thePeekListCoversTodayAndTomorrowOnly() {
        var agenda = Agenda()
        agenda.replace(with: [
            event("today", startsIn: 60),
            event("tomorrow", startsIn: 25 * 60),
            event("next week", startsIn: 7 * 24 * 60)
        ])

        XCTAssertEqual(agenda.peek(at: noon).map(\.id), ["today", "tomorrow"])
    }

    func test_thePeekListDropsWhatIsAlreadyOver() {
        var agenda = Agenda()
        agenda.replace(with: [
            event("finished", startsIn: -120, lasting: 30),
            event("later", startsIn: 60)
        ])

        XCTAssertEqual(agenda.peek(at: noon).map(\.id), ["later"])
    }
}
