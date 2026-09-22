import XCTest

@testable import PerchCore

/// Covers `TEST-PLAN.md` § CAM for the pre-call check — TC-CAM-014 and
/// TC-CAM-015.
///
/// `PreCallCheck` takes facts rather than a `CalendarEvent`, which is why
/// TC-CAM-015 is almost free: with the calendar module switched off nothing
/// calls this, and nothing here depends on it existing.
final class PreCallCheckTests: XCTestCase {

    private let noon = Date(timeIntervalSinceReferenceDate: 12 * 3_600)

    // MARK: - TC-CAM-014

    func test_TC_CAM_014_firesInsideTheLead() {
        var check = PreCallCheck()

        XCTAssertTrue(
            check.shouldCheck(
                eventID: "standup",
                startsAt: noon.addingTimeInterval(30),
                hasMeetingLink: true,
                now: noon
            )
        )
    }

    func test_TC_CAM_014_doesNotFireBeforeTheLead() {
        var check = PreCallCheck()

        XCTAssertFalse(
            check.shouldCheck(
                eventID: "standup",
                startsAt: noon.addingTimeInterval(5 * 60),
                hasMeetingLink: true,
                now: noon
            )
        )
    }

    /// A check that fires two minutes into a call is somebody's camera
    /// turning on unasked.
    func test_TC_CAM_014_doesNotFireOnceTheMeetingHasStarted() {
        var check = PreCallCheck()

        XCTAssertFalse(
            check.shouldCheck(
                eventID: "standup",
                startsAt: noon.addingTimeInterval(-120),
                hasMeetingLink: true,
                now: noon
            )
        )
    }

    /// The calendar refreshes whenever anything in any calendar changes. A
    /// check that fired on each refresh would open the camera repeatedly.
    func test_TC_CAM_014_firesOncePerMeetingNoMatterHowOftenItIsAsked() {
        var check = PreCallCheck()
        let start = noon.addingTimeInterval(30)

        XCTAssertTrue(
            check.shouldCheck(eventID: "s", startsAt: start, hasMeetingLink: true, now: noon)
        )

        for second in 1...20 {
            XCTAssertFalse(
                check.shouldCheck(
                    eventID: "s",
                    startsAt: start,
                    hasMeetingLink: true,
                    now: noon.addingTimeInterval(Double(second))
                )
            )
        }
    }

    func test_TC_CAM_014_aDifferentMeetingGetsItsOwnCheck() {
        var check = PreCallCheck()
        let start = noon.addingTimeInterval(30)

        XCTAssertTrue(
            check.shouldCheck(eventID: "one", startsAt: start, hasMeetingLink: true, now: noon)
        )
        XCTAssertTrue(
            check.shouldCheck(eventID: "two", startsAt: start, hasMeetingLink: true, now: noon)
        )
    }

    /// A check before a phone call or a desk booking is noise. Off is for
    /// people whose meetings are all in person and who still want it.
    func test_TC_CAM_014_anEventWithNoLinkIsSkippedUnlessAskedFor() {
        var strict = PreCallCheck()
        XCTAssertFalse(
            strict.shouldCheck(
                eventID: "lunch",
                startsAt: noon.addingTimeInterval(30),
                hasMeetingLink: false,
                now: noon
            )
        )

        var configuration = PreCallCheck.Configuration()
        configuration.requiresMeetingLink = false
        var relaxed = PreCallCheck(configuration: configuration)

        XCTAssertTrue(
            relaxed.shouldCheck(
                eventID: "lunch",
                startsAt: noon.addingTimeInterval(30),
                hasMeetingLink: false,
                now: noon
            )
        )
    }

    func test_TC_CAM_014_switchedOffItNeverFires() {
        var configuration = PreCallCheck.Configuration()
        configuration.isEnabled = false
        var check = PreCallCheck(configuration: configuration)

        XCTAssertFalse(
            check.shouldCheck(
                eventID: "standup",
                startsAt: noon.addingTimeInterval(30),
                hasMeetingLink: true,
                now: noon
            )
        )
    }

    func test_aLongerLeadOpensItSooner() {
        var configuration = PreCallCheck.Configuration()
        configuration.lead = .seconds(5 * 60)
        var check = PreCallCheck(configuration: configuration)

        XCTAssertTrue(
            check.shouldCheck(
                eventID: "standup",
                startsAt: noon.addingTimeInterval(4 * 60),
                hasMeetingLink: true,
                now: noon
            )
        )
    }

    /// Switching the module off and on again must not silently skip the
    /// meeting that was coming up.
    func test_resetForgetsWhatWasChecked() {
        var check = PreCallCheck()
        let start = noon.addingTimeInterval(30)

        XCTAssertTrue(
            check.shouldCheck(eventID: "s", startsAt: start, hasMeetingLink: true, now: noon)
        )
        check.reset()
        XCTAssertTrue(
            check.shouldCheck(eventID: "s", startsAt: start, hasMeetingLink: true, now: noon)
        )
    }
}
