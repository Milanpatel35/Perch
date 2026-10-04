import XCTest

@testable import PerchCore

/// Covers `TEST-PLAN.md` § HOM — which modules get a button on the home
/// surface, and what the focus button says.
final class HomeLauncherTests: XCTestCase {

    // MARK: - TC-HOM-001

    func test_TC_HOM_001_listsOnlyModulesThatAreOnInFixedOrder() {
        let switchedOn: Set<ModuleID> = [.calendar, .clipboard, .battery, .shelf]

        XCTAssertEqual(HomeLauncher.entries(isOn: switchedOn.contains), [.clipboard, .calendar])
    }

    func test_TC_HOM_001_switchingOneOnDoesNotMoveTheOthers() {
        let two: Set<ModuleID> = [.clipboard, .camera]
        let three: Set<ModuleID> = [.clipboard, .camera, .focus]

        let before = HomeLauncher.entries(isOn: two.contains)
        let after = HomeLauncher.entries(isOn: three.contains)

        XCTAssertEqual(before, [.clipboard, .camera])
        XCTAssertEqual(after, [.clipboard, .focus, .camera])
    }

    // MARK: - TC-HOM-002

    func test_TC_HOM_002_nothingToOpenMeansNoRow() {
        let passive: Set<ModuleID> = [.shelf, .hud, .notifications, .nowPlaying, .battery]

        XCTAssertTrue(HomeLauncher.entries(isOn: passive.contains).isEmpty)
    }

    // MARK: - TC-HOM-003

    func test_TC_HOM_003_focusButtonSaysWhatItWillDo() {
        var timer = PomodoroTimer()
        XCTAssertEqual(HomeLauncher.FocusAction(timer), .start)

        timer.start(.work, now: Date())
        XCTAssertEqual(HomeLauncher.FocusAction(timer), .pause)

        timer.pause(now: Date())
        XCTAssertEqual(HomeLauncher.FocusAction(timer), .resume)
    }
}
