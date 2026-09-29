import AppKit
import Defaults
import PerchCore
import XCTest

@testable import PerchUI

/// Covers `TEST-PLAN.md` § HID for the parts that need the real module: what
/// exists while it is on, and that nothing does once it is off.
///
/// A CI runner has one display with no notch, so by default no strip is
/// drawn there. The tests that need a strip ask for one on that display by
/// its UUID, which is the same per-display path a user takes (TC-HID-003).
@MainActor
final class HideNotchModuleTests: XCTestCase {

    private struct Harness {
        let hideNotch: HideNotchService
        let island: IslandController
    }

    private var saved = HideNotchConfiguration()

    override func setUp() async throws {
        saved = Defaults[.hideNotch]
        Defaults[.hideNotch] = HideNotchConfiguration()
    }

    override func tearDown() async throws {
        Defaults[.hideNotch] = saved
    }

    private func makeService() -> Harness {
        let island = IslandController(sleep: { _ in try await Task.sleep(for: .seconds(86_400)) })
        return Harness(hideNotch: HideNotchService(island: island), island: island)
    }

    /// Asks for a strip on every attached display.
    private func everyDisplayOn(_ configuration: HideNotchConfiguration) -> HideNotchConfiguration {
        var updated = configuration
        for screen in NSScreen.screens {
            if let id = screen.displayUUID { updated.displayChoices[id] = true }
        }
        return updated
    }

    // MARK: - TC-HID-001

    func test_TC_HID_001_blackoutDrawsAStripOnEveryChosenDisplay() throws {
        let barred = NSScreen.screens.filter { $0.displayUUID != nil && $0.menuBarHeight > 0 }
        try XCTSkipIf(barred.isEmpty, "no display with a menu bar attached")

        let harness = makeService()
        harness.hideNotch.activate()
        harness.hideNotch.setConfiguration(everyDisplayOn(harness.hideNotch.configuration))

        XCTAssertEqual(harness.hideNotch.stripCount, barred.count)
        XCTAssertTrue(harness.hideNotch.isObservingScreens)

        harness.hideNotch.deactivate()
    }

    // MARK: - TC-HID-002

    /// The wallpaper watcher exists only while the strip is set to match
    /// the wallpaper. A black strip has nothing to re-match.
    func test_TC_HID_002_onlyTheWallpaperFillWatchesTheWallpaper() {
        let harness = makeService()
        harness.hideNotch.activate()
        XCTAssertFalse(harness.hideNotch.isWatchingWallpaper)

        var configuration = harness.hideNotch.configuration
        configuration.fill = .wallpaper
        harness.hideNotch.setConfiguration(configuration)
        XCTAssertTrue(harness.hideNotch.isWatchingWallpaper)

        configuration.fill = .black
        harness.hideNotch.setConfiguration(configuration)
        XCTAssertFalse(harness.hideNotch.isWatchingWallpaper)

        harness.hideNotch.deactivate()
    }

    // MARK: - TC-HID-003

    func test_TC_HID_003_switchingADisplayOffRemovesOnlyItsStrip() throws {
        let barred = NSScreen.screens.compactMap { screen in
            screen.menuBarHeight > 0 ? screen.displayUUID : nil
        }
        try XCTSkipIf(barred.isEmpty, "no display with a menu bar attached")
        let first = barred[0]

        let harness = makeService()
        harness.hideNotch.activate()
        harness.hideNotch.setConfiguration(everyDisplayOn(harness.hideNotch.configuration))
        let before = harness.hideNotch.stripCount

        harness.hideNotch.setShowsStrip(false, onDisplay: first)

        XCTAssertEqual(harness.hideNotch.stripCount, before - 1)
        XCTAssertEqual(harness.hideNotch.configuration.displayChoices[first], false)
        XCTAssertEqual(
            Defaults[.hideNotch].displayChoices[first], false, "the choice is remembered")

        harness.hideNotch.deactivate()
    }

    // MARK: - TC-HID-005

    func test_TC_HID_005_turningBlackoutOffRemovesEveryStripAtOnce() {
        let harness = makeService()
        harness.hideNotch.activate()
        harness.hideNotch.setConfiguration(everyDisplayOn(harness.hideNotch.configuration))

        var configuration = harness.hideNotch.configuration
        configuration.isBlackoutEnabled = false
        harness.hideNotch.setConfiguration(configuration)

        XCTAssertEqual(harness.hideNotch.stripCount, 0)
        XCTAssertFalse(harness.hideNotch.isObservingScreens)

        harness.hideNotch.deactivate()
    }

    // MARK: - TC-HID-006

    func test_TC_HID_006_invisibleModeIsRaisedOnTheIslandAndLoweredWithTheModule() {
        let harness = makeService()
        harness.hideNotch.activate()
        XCTAssertFalse(harness.island.hidesIdleIsland)

        var configuration = harness.hideNotch.configuration
        configuration.isInvisibleWhenIdle = true
        harness.hideNotch.setConfiguration(configuration)
        XCTAssertTrue(harness.island.hidesIdleIsland)

        harness.hideNotch.deactivate()
        XCTAssertFalse(
            harness.island.hidesIdleIsland,
            "an island left invisible by a module that is off is an island nobody can find"
        )
    }

    // MARK: - TC-HID-007

    /// **Off means nothing.** No window, no screen observer, no wallpaper
    /// watch — whatever the settings were (`CLAUDE.md` §4).
    func test_TC_HID_007_switchingTheModuleOffLeavesNothingBehind() {
        let harness = makeService()

        var configuration = everyDisplayOn(HideNotchConfiguration())
        configuration.fill = .wallpaper
        configuration.isInvisibleWhenIdle = true
        harness.hideNotch.setConfiguration(configuration)

        harness.hideNotch.activate()
        harness.hideNotch.deactivate()

        XCTAssertFalse(harness.hideNotch.isActive)
        XCTAssertEqual(harness.hideNotch.stripCount, 0)
        XCTAssertFalse(harness.hideNotch.isObservingScreens)
        XCTAssertFalse(harness.hideNotch.isWatchingWallpaper)
        XCTAssertFalse(harness.island.hidesIdleIsland)
    }

    func test_TC_HID_007_settingsChangedWhileOffStartNothing() {
        let harness = makeService()

        var configuration = everyDisplayOn(HideNotchConfiguration())
        configuration.fill = .wallpaper
        configuration.isInvisibleWhenIdle = true
        harness.hideNotch.setConfiguration(configuration)

        XCTAssertEqual(harness.hideNotch.stripCount, 0)
        XCTAssertFalse(harness.hideNotch.isObservingScreens)
        XCTAssertFalse(harness.hideNotch.isWatchingWallpaper)
        XCTAssertFalse(harness.island.hidesIdleIsland)
    }

    /// With blackout off and the island visible, the module is on and holds
    /// nothing at all.
    func test_TC_HID_007_onWithNothingToDoHoldsNothing() {
        let harness = makeService()
        var configuration = HideNotchConfiguration()
        configuration.isBlackoutEnabled = false
        harness.hideNotch.setConfiguration(configuration)

        harness.hideNotch.activate()

        XCTAssertEqual(harness.hideNotch.stripCount, 0)
        XCTAssertFalse(harness.hideNotch.isObservingScreens)
        XCTAssertFalse(harness.hideNotch.isWatchingWallpaper)

        harness.hideNotch.deactivate()
    }

    func test_deactivatingTwiceIsSafe() {
        let harness = makeService()
        harness.hideNotch.activate()
        harness.hideNotch.deactivate()
        harness.hideNotch.deactivate()

        XCTAssertFalse(harness.hideNotch.isActive)
    }

    /// The module puts nothing on the island. Ever.
    func test_theModuleNeverPresentsAnything() {
        let harness = makeService()
        var configuration = everyDisplayOn(HideNotchConfiguration())
        configuration.isInvisibleWhenIdle = true
        harness.hideNotch.setConfiguration(configuration)

        harness.hideNotch.activate()
        XCTAssertNil(harness.island.presented)
        XCTAssertTrue(harness.island.queued.isEmpty)

        harness.hideNotch.deactivate()
    }
}
