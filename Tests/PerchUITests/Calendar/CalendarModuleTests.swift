import AppKit
import PerchCore
import SwiftUI
import XCTest

@testable import PerchUI

/// Covers `TEST-PLAN.md` § CAL for the parts that need the real module.
///
/// Calendar access is never granted on a CI machine, and asking for it would
/// hang the suite behind a system prompt. That is not a gap: TC-CAL-001 says
/// a refused module keeps the app working, and these are exactly the tests
/// that prove it. The countdown rules themselves are values and live in
/// `AgendaTests`.
@MainActor
final class CalendarModuleTests: XCTestCase {

    nonisolated(unsafe) private var clock = Date(timeIntervalSinceReferenceDate: 12 * 3_600)

    override func setUp() {
        super.setUp()
        clock = Date(timeIntervalSinceReferenceDate: 12 * 3_600)
    }

    private struct Harness {
        let calendar: CalendarService
        let island: IslandController
    }

    private func makeService() -> Harness {
        let island = IslandController(sleep: { _ in try await Task.sleep(for: .seconds(86_400)) })
        let service = CalendarService(island: island, now: { [self] in clock })
        return Harness(calendar: service, island: island)
    }

    // MARK: - TC-CAL-001

    func test_TC_CAL_001_withoutAccessTheModuleStillActivatesAndShowsNothing() {
        let harness = makeService()
        harness.calendar.activate()

        XCTAssertTrue(harness.calendar.isActive)
        XCTAssertTrue(harness.calendar.agenda.events.isEmpty)
        XCTAssertNil(harness.island.presented)

        harness.calendar.deactivate()
    }

    func test_TC_CAL_001_actionsAreInertWithoutAnEventRatherThanCrashing() {
        let harness = makeService()
        harness.calendar.activate()

        // Every one of these is reachable from a keyboard shortcut, which
        // fires whether or not anything is on the island.
        harness.calendar.joinCurrent()
        harness.calendar.toggleMute()
        harness.calendar.toggleCamera()
        harness.calendar.leaveMeeting()

        XCTAssertNil(harness.island.presented)
        harness.calendar.deactivate()
    }

    // MARK: - TC-CAL-013

    func test_TC_CAL_013_switchingTheModuleOffLeavesNothingBehind() {
        let harness = makeService()
        harness.calendar.activate()
        harness.calendar.deactivate()

        XCTAssertFalse(harness.calendar.isActive)
        XCTAssertTrue(harness.calendar.agenda.events.isEmpty)
        XCTAssertTrue(harness.calendar.reminders.isEmpty)
        XCTAssertNil(harness.island.presented)
    }

    func test_TC_CAL_013_deactivatingTwiceIsSafe() {
        let harness = makeService()
        harness.calendar.activate()
        harness.calendar.deactivate()
        harness.calendar.deactivate()

        XCTAssertFalse(harness.calendar.isActive)
    }

    func test_TC_CAL_013_theModuleSurvivesBeingSwitchedOnAndOffRepeatedly() {
        let harness = makeService()

        for _ in 0..<5 {
            harness.calendar.activate()
            harness.calendar.deactivate()
        }

        XCTAssertFalse(harness.calendar.isActive)
        XCTAssertNil(harness.island.presented)
    }

    /// Refreshing while switched off must do nothing at all. The wake-up
    /// task and EventKit's notification can both arrive after `deactivate`,
    /// and a module that is off holds nothing (`CLAUDE.md` §5.1).
    func test_TC_CAL_013_refreshingWhileOffIsANoOp() {
        let harness = makeService()
        harness.calendar.refresh()

        XCTAssertTrue(harness.calendar.agenda.events.isEmpty)
        XCTAssertNil(harness.island.presented)
    }

    // MARK: - Configuration

    func test_configurationSurvivesTheModuleBeingSwitchedOff() {
        let harness = makeService()
        harness.calendar.activate()

        var configuration = Agenda.Configuration()
        configuration.leadTime = .seconds(15 * 60)
        harness.calendar.setConfiguration(configuration)

        XCTAssertEqual(harness.calendar.agenda.configuration.leadTime, .seconds(15 * 60))

        harness.calendar.deactivate()
        harness.calendar.activate()

        XCTAssertEqual(harness.calendar.agenda.configuration.leadTime, .seconds(15 * 60))
        harness.calendar.deactivate()
    }

    /// The exclusion list is stored by calendar title, and the titles offered
    /// in Preferences come from what was actually read — never a hardcoded
    /// list, and never an empty one that looks like a bug.
    func test_calendarTitlesAreEmptyWithoutAccessRatherThanWrong() {
        let harness = makeService()
        harness.calendar.activate()

        XCTAssertTrue(harness.calendar.calendarTitles.isEmpty)
        harness.calendar.deactivate()
    }
}
