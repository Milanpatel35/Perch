import XCTest

@testable import PerchCore

/// Covers `TEST-PLAN.md` § FOC for the counting half — TC-FOC-005, which is
/// the rule people notice when it is wrong.
final class FocusStreakTests: XCTestCase {

    /// A pinned calendar. A streak that breaks when somebody flies to another
    /// country is a bug that gets reported and never reproduced.
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }()

    private let epoch = Date(timeIntervalSinceReferenceDate: 0)

    private func day(_ offset: Int, hour: Int = 10) -> Date {
        epoch
            .addingTimeInterval(Double(offset) * 86_400)
            .addingTimeInterval(Double(hour) * 3_600)
    }

    // MARK: - TC-FOC-005

    func test_TC_FOC_005_theStreakCountsDaysNotSessions() {
        var streak = FocusStreak()

        for hour in [9, 11, 14, 16] {
            streak.recordCompletedSession(at: day(0, hour: hour), calendar: calendar)
        }

        XCTAssertEqual(streak.totalSessions, 4)
        XCTAssertEqual(streak.sessions(on: day(0), calendar: calendar), 4)
        XCTAssertEqual(streak.streak(on: day(0), calendar: calendar), 1)
    }

    func test_TC_FOC_005_consecutiveDaysBuildTheStreak() {
        var streak = FocusStreak()

        for offset in 0..<5 {
            streak.recordCompletedSession(at: day(offset), calendar: calendar)
        }

        XCTAssertEqual(streak.streak(on: day(4), calendar: calendar), 5)
        XCTAssertEqual(streak.totalSessions, 5)
    }

    func test_TC_FOC_005_aMissedDayStartsTheStreakAgain() {
        var streak = FocusStreak()

        streak.recordCompletedSession(at: day(0), calendar: calendar)
        streak.recordCompletedSession(at: day(1), calendar: calendar)
        XCTAssertEqual(streak.streak(on: day(1), calendar: calendar), 2)

        // Nothing on day 2.
        streak.recordCompletedSession(at: day(3), calendar: calendar)
        XCTAssertEqual(streak.streak(on: day(3), calendar: calendar), 1)
        XCTAssertEqual(streak.totalSessions, 3)
    }

    /// Not having started yet this morning has not broken yesterday's streak.
    func test_TC_FOC_005_aStreakSurvivesUntilTheDayAfterIsOver() {
        var streak = FocusStreak()
        streak.recordCompletedSession(at: day(0), calendar: calendar)

        XCTAssertEqual(streak.streak(on: day(0), calendar: calendar), 1)
        XCTAssertEqual(streak.streak(on: day(1), calendar: calendar), 1)
        XCTAssertEqual(streak.streak(on: day(2), calendar: calendar), 0)
    }

    /// `sessionsToday` is stored, so it has to be read through the date — at
    /// one minute past midnight the stored number is yesterday's, and nobody
    /// wants to be told they have already done four sessions today.
    func test_TC_FOC_005_todaysCountIsZeroOnANewDay() {
        var streak = FocusStreak()
        streak.recordCompletedSession(at: day(0), calendar: calendar)
        streak.recordCompletedSession(at: day(0, hour: 15), calendar: calendar)

        XCTAssertEqual(streak.sessions(on: day(0), calendar: calendar), 2)
        XCTAssertEqual(streak.sessions(on: day(1), calendar: calendar), 0)
    }

    func test_aFreshStreakCountsNothing() {
        let streak = FocusStreak()

        XCTAssertEqual(streak.totalSessions, 0)
        XCTAssertEqual(streak.streak(on: day(0), calendar: calendar), 0)
        XCTAssertEqual(streak.sessions(on: day(0), calendar: calendar), 0)
    }

    /// The clock going backwards is a new streak rather than a negative one.
    func test_aClockThatGoesBackwardsDoesNotProduceANegativeStreak() {
        var streak = FocusStreak()
        streak.recordCompletedSession(at: day(5), calendar: calendar)
        streak.recordCompletedSession(at: day(0), calendar: calendar)

        XCTAssertEqual(streak.streak(on: day(0), calendar: calendar), 1)
        XCTAssertEqual(streak.totalSessions, 2)
    }

    /// It is persisted, so it has to survive the round trip.
    func test_itSurvivesEncodingAndDecoding() throws {
        var streak = FocusStreak()
        streak.recordCompletedSession(at: day(0), calendar: calendar)
        streak.recordCompletedSession(at: day(1), calendar: calendar)

        let data = try JSONEncoder().encode(streak)
        let decoded = try JSONDecoder().decode(FocusStreak.self, from: data)

        XCTAssertEqual(decoded, streak)
        XCTAssertEqual(decoded.streak(on: day(1), calendar: calendar), 2)
    }
}
