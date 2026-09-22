import AppKit
import PerchCore
import SwiftUI
import XCTest

@testable import PerchUI

/// Covers `TEST-PLAN.md` § NTF for the parts that need the real module.
///
/// Accessibility is never granted to a test runner, so the watcher never
/// attaches here. That is the point of these: TC-NTF-008 says a module
/// without permission explains itself and leaves the rest of the app alone,
/// and TC-NTF-009 says one that is switched off holds nothing at all.
@MainActor
final class NotificationModuleTests: XCTestCase {

    private struct Harness {
        let notifications: NotificationService
        let island: IslandController
    }

    private func makeService() -> Harness {
        let island = IslandController(sleep: { _ in try await Task.sleep(for: .seconds(86_400)) })
        return Harness(notifications: NotificationService(island: island), island: island)
    }

    // MARK: - TC-NTF-008

    func test_TC_NTF_008_withoutAccessibilityTheModuleActivatesAndMirrorsNothing() {
        let harness = makeService()
        harness.notifications.activate()

        XCTAssertTrue(harness.notifications.isActive)
        XCTAssertFalse(harness.notifications.isWatching)
        XCTAssertNil(harness.island.presented)

        harness.notifications.deactivate()
    }

    func test_TC_NTF_008_replyingWithoutABannerFailsRatherThanCrashing() {
        let harness = makeService()
        harness.notifications.activate()

        XCTAssertFalse(harness.notifications.reply(with: "on my way"))

        harness.notifications.deactivate()
    }

    func test_TC_NTF_008_openAndDismissAreInertWithNothingOnTheIsland() {
        let harness = makeService()
        harness.notifications.activate()

        harness.notifications.open()
        harness.notifications.dismiss()

        XCTAssertNil(harness.island.presented)
        harness.notifications.deactivate()
    }

    // MARK: - TC-NTF-009

    func test_TC_NTF_009_switchingTheModuleOffLeavesNothingBehind() {
        let harness = makeService()
        harness.notifications.activate()
        harness.notifications.deactivate()

        XCTAssertFalse(harness.notifications.isActive)
        XCTAssertFalse(harness.notifications.isWatching)
        XCTAssertNil(harness.notifications.policy.current)
        XCTAssertTrue(harness.notifications.policy.held.isEmpty)
        XCTAssertNil(harness.island.presented)
    }

    func test_TC_NTF_009_deactivatingTwiceIsSafe() {
        let harness = makeService()
        harness.notifications.activate()
        harness.notifications.deactivate()
        harness.notifications.deactivate()

        XCTAssertFalse(harness.notifications.isActive)
    }

    func test_TC_NTF_009_theModuleSurvivesBeingSwitchedOnAndOffRepeatedly() {
        let harness = makeService()

        for _ in 0..<5 {
            harness.notifications.activate()
            harness.notifications.deactivate()
        }

        XCTAssertFalse(harness.notifications.isActive)
        XCTAssertNil(harness.island.presented)
    }

    func test_TC_NTF_009_releasingHeldNotificationsWhileOffIsANoOp() {
        let harness = makeService()
        harness.notifications.releaseHeldNotifications()

        XCTAssertNil(harness.island.presented)
    }

    // MARK: - Configuration

    func test_configurationSurvivesTheModuleBeingSwitchedOff() {
        let harness = makeService()
        harness.notifications.activate()

        var configuration = NotificationPolicy.Configuration()
        configuration.mode = .allowListedOnly
        configuration.apps = ["com.apple.MobileSMS"]
        harness.notifications.setConfiguration(configuration)

        harness.notifications.deactivate()
        harness.notifications.activate()

        XCTAssertEqual(harness.notifications.policy.configuration.mode, .allowListedOnly)
        harness.notifications.deactivate()
    }

    /// The app list fills itself in from what has actually arrived. Empty is
    /// the honest starting state, not a bug.
    func test_theKnownAppListStartsEmpty() {
        let harness = makeService()
        harness.notifications.activate()

        XCTAssertTrue(harness.notifications.knownApps.isEmpty)
        harness.notifications.deactivate()
    }

    // MARK: - The focus link

    /// The two modules are joined by `PerchModuleRegistry`, never by each
    /// other. Un-wired, the notification module must behave as though no
    /// session is ever running rather than reaching for a module that may
    /// not be switched on.
    func test_theFocusHookDefaultsToNoSessionRunning() {
        let harness = makeService()
        XCTAssertFalse(harness.notifications.isFocusSessionRunning())
    }
}
