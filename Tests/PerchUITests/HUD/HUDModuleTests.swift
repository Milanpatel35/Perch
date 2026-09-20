import AppKit
import PerchCore
import SwiftUI
import XCTest

@testable import PerchUI

/// Covers `TEST-PLAN.md` § HUD for the parts that need the real module.
///
/// The rules themselves are `HUDPolicyTests`, in Core, where they can be
/// tested without hardware. What is here is the contract that holds on every
/// Mac: what the island is told, what the module holds while it is off, and
/// that the stock overlay comes back.
@MainActor
final class HUDModuleTests: XCTestCase {

    private struct Harness {
        let hud: HUDService
        let island: IslandController
    }

    private func makeService() -> Harness {
        let island = IslandController(sleep: { _ in try await Task.sleep(for: .seconds(86_400)) })
        return Harness(hud: HUDService(island: island), island: island)
    }

    // MARK: - Lifecycle

    func test_activatingTwiceIsNotTwiceTheWork() {
        let harness = makeService()

        harness.hud.activate()
        harness.hud.activate()
        XCTAssertTrue(harness.hud.isActive)

        harness.hud.deactivate()
        XCTAssertFalse(harness.hud.isActive)
    }

    func test_deactivatingWhenAlreadyOffIsSafe() {
        let harness = makeService()

        harness.hud.deactivate()
        harness.hud.deactivate()
        XCTAssertFalse(harness.hud.isActive)
    }

    /// Six watchers switched on at once must not fire six HUDs. The state is
    /// recorded as a baseline and nothing is shown.
    func test_TC_HUD_003_switchingOnShowsNothing() {
        let harness = makeService()

        harness.hud.activate()

        XCTAssertNil(harness.island.presented)
        XCTAssertTrue(harness.island.state.presentation.isIdle)
    }

    /// TC-HUD-003 proper: the stock HUD comes back the moment the module goes
    /// off, and nothing is left on the island.
    func test_TC_HUD_009_switchingOffRestoresTheStockHUDAndLeavesNothingBehind() {
        let harness = makeService()

        harness.hud.activate()
        harness.hud.deactivate()

        XCTAssertFalse(harness.hud.isSuppressingStockHUD)
        XCTAssertFalse(harness.hud.isActive)
        XCTAssertNil(harness.island.presented)
    }

    /// Restoring must be safe when nothing was ever suspended — which is the
    /// common case, because `OSDUIHelper` is launched on demand and is
    /// usually not running when the module comes up (TC-HUD-010).
    func test_TC_HUD_010_restoringWithoutHavingSuppressedIsSafe() {
        let harness = makeService()

        harness.hud.setSuppressesStockHUD(false)
        harness.hud.activate()
        XCTAssertFalse(harness.hud.isSuppressingStockHUD)

        harness.hud.deactivate()
        XCTAssertFalse(harness.hud.isSuppressingStockHUD)
    }

    // MARK: - TC-HUD-004

    /// A HUD is ambient: it composes with whatever is on the island rather
    /// than fighting it. A volume change during a low-battery warning must
    /// not push the warning off.
    func test_TC_HUD_004_aHUDDoesNotPreEmptSomethingMoreImportant() {
        let hud = HUDActivity(
            reading: HUDReading(kind: .volume, level: 0.5, title: "Volume")
        )

        XCTAssertEqual(hud.priority, .ambient)
        XCTAssertLessThan(hud.priority, ActivityPriority.nowPlaying)
        XCTAssertLessThan(hud.priority, ActivityPriority.systemAlert)
    }

    /// Your hand is on the keyboard, not the trackpad. Hovering a HUD must
    /// not open it into a surface.
    func test_TC_HUD_004_aHUDIsNotExpandable() {
        let hud = HUDActivity(reading: HUDReading(kind: .volume, title: "Volume"))
        XCTAssertFalse(hud.isExpandable)
    }

    // MARK: - TC-HUD-002

    /// Every kind shares one identifier, so turning the volume up while the
    /// brightness HUD is still on screen replaces it rather than queueing
    /// behind it — which is what makes a held key look like one smooth HUD.
    func test_TC_HUD_002_everyKindSharesOneIdentifierSoTheyReplaceEachOther() {
        let harness = makeService()
        harness.hud.activate()

        harness.island.submit(
            HUDActivity(reading: HUDReading(kind: .brightness, level: 0.4, title: "Brightness"))
        )
        harness.island.submit(
            HUDActivity(reading: HUDReading(kind: .volume, level: 0.8, title: "Volume"))
        )

        XCTAssertEqual(harness.island.queued.filter { $0.source == .hud }.count, 1)
        XCTAssertEqual(harness.island.presented?.id, HUDActivity.identifier)
    }

    /// Matching the stock overlay is the point: this is a replacement, not a
    /// new thing to learn.
    func test_aHUDStaysUpForAboutAsLongAsTheStockOne() {
        let hud = HUDActivity(reading: HUDReading(kind: .volume, title: "Volume"))

        let seconds = hud.timeToLive?.seconds ?? 0
        XCTAssertGreaterThan(seconds, 1.0)
        XCTAssertLessThan(seconds, 2.5)
    }

    // MARK: - TC-HUD-008

    func test_TC_HUD_008_switchingOneHUDOffLeavesTheRestOn() {
        let harness = makeService()
        harness.hud.activate()

        harness.hud.setEnabled(.volume, false)

        XCTAssertFalse(harness.hud.policy.isEnabled(.volume))
        for kind in HUDKind.allCases where kind != .volume {
            XCTAssertTrue(harness.hud.policy.isEnabled(kind), "\(kind) was switched off too")
        }
    }

    // MARK: - TC-HUD-007

    func test_TC_HUD_007_aChangePerchMakesIsNotAnnouncedBack() {
        let harness = makeService()
        harness.hud.activate()

        harness.hud.expectSelfInflictedChange(to: .focus)

        var policy = harness.hud.policy
        XCTAssertFalse(policy.admit(HUDReading(kind: .focus, title: "Do Not Disturb")))
    }

    // MARK: - TC-HUD-005

    /// The charging HUD shares module 7's rule, and shares the type that
    /// implements it rather than a second copy: a charger attached but not
    /// taking charge must not repeat the HUD.
    func test_TC_HUD_005_theChargingHUDUsesTheSameRuleAsTheBatteryModule() {
        var alerts = BatteryAlerts()

        func snapshot(
            _ percentage: Int,
            _ source: PowerSnapshot.Source,
            charging: Bool
        ) -> PowerSnapshot {
            PowerSnapshot(
                isPresent: true,
                percentage: percentage,
                source: source,
                isCharging: charging,
                isCharged: false,
                timeRemaining: nil
            )
        }

        _ = alerts.ingest(snapshot(50, .battery, charging: false))
        XCTAssertEqual(
            alerts.ingest(snapshot(50, .wall, charging: true)),
            [.pluggedIn(50)]
        )

        // Battery-health hold: charging flips, the cable has not moved.
        XCTAssertTrue(alerts.ingest(snapshot(80, .wall, charging: false)).isEmpty)
        XCTAssertTrue(alerts.ingest(snapshot(80, .wall, charging: true)).isEmpty)
    }

    // MARK: - Presentation

    /// Counts pixels at or above an alpha threshold.
    ///
    /// The threshold matters for the level bar: its track spans the full
    /// width at 22% opacity, so counting *any* non-zero alpha returns the
    /// same number whatever the fill is doing. `minimumAlpha: 200` counts the
    /// fill and ignores the track.
    private func drawnPixels(
        _ view: AnyView,
        size: CGSize,
        minimumAlpha: UInt8 = 1
    ) -> Int {
        let island = IslandController(sleep: { _ in try await Task.sleep(for: .seconds(86_400)) })
        let modules = ModuleHost(switchboard: ModuleSwitchboard(), island: island)
        let host = NSHostingView(rootView: AnyView(view.environmentObject(modules)))
        host.frame = CGRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()

        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return 0 }
        host.cacheDisplay(in: host.bounds, to: rep)

        guard let data = rep.bitmapData else { return 0 }
        let samples = rep.samplesPerPixel
        var drawn = 0
        for pixel in 0..<(rep.pixelsWide * rep.pixelsHigh)
        where data[(pixel * samples) + (samples - 1)] >= minimumAlpha {
            drawn += 1
        }
        return drawn
    }

    func test_everyKindOfHUDDrawsWithoutTrapping() {
        for kind in HUDKind.allCases {
            let reading = HUDReading(
                kind: kind,
                level: kind.showsLevel ? 0.5 : nil,
                title: kind.displayName,
                detail: "Detail"
            )
            let activity = HUDActivity(reading: reading)

            XCTAssertGreaterThan(
                drawnPixels(activity.peekView(), size: activity.peekSize),
                50,
                "\(kind) drew nothing"
            )
        }
    }

    /// The bar is drawn rather than taken from a `ProgressView` so the fill
    /// tracks the value exactly.
    func test_theLevelBarTracksTheValue() {
        let size = CGSize(width: 100, height: 10)

        let quiet = drawnPixels(AnyView(HUDLevelBar(level: 0.1)), size: size, minimumAlpha: 200)
        let half = drawnPixels(AnyView(HUDLevelBar(level: 0.5)), size: size, minimumAlpha: 200)
        let loud = drawnPixels(AnyView(HUDLevelBar(level: 1.0)), size: size, minimumAlpha: 200)

        XCTAssertGreaterThan(half, quiet)
        XCTAssertGreaterThan(loud, half)

        // The track is always the full width, so the total drawn area does
        // not move with the level — which is the point of measuring the fill.
        XCTAssertEqual(
            drawnPixels(AnyView(HUDLevelBar(level: 0.1)), size: size),
            drawnPixels(AnyView(HUDLevelBar(level: 1.0)), size: size)
        )
    }

    /// Muted at 40% is not 0%: the bar still shows where the volume will come
    /// back to, dimmed.
    func test_mutedStillShowsWhereTheVolumeWillComeBackTo() {
        let size = CGSize(width: 100, height: 10)

        let muted = drawnPixels(AnyView(HUDLevelBar(level: 0.4, isMuted: true)), size: size)
        let unmuted = drawnPixels(AnyView(HUDLevelBar(level: 0.4)), size: size)

        // Same geometry either way; muted only dims the fill.
        XCTAssertGreaterThan(muted, 0)
        XCTAssertEqual(muted, unmuted)
        XCTAssertLessThan(
            drawnPixels(
                AnyView(HUDLevelBar(level: 0.4, isMuted: true)),
                size: size,
                minimumAlpha: 200
            ),
            drawnPixels(AnyView(HUDLevelBar(level: 0.4)), size: size, minimumAlpha: 200)
        )
    }
}
