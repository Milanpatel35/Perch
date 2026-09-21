import AppKit
import PerchCore
import SwiftUI
import XCTest

@testable import PerchUI

/// The battery's views, rendered for real and checked by drawn pixels.
///
/// Same approach as the shelf's and Now Playing's view tests, and for the
/// same reason: SwiftUI renders leaf content straight into the hosting view's
/// layer, so counting `subviews` proves nothing.
@MainActor
final class BatteryViewTests: XCTestCase {

    private func hosted(_ view: AnyView) -> AnyView {
        let island = IslandController(sleep: { _ in try await Task.sleep(for: .seconds(86_400)) })
        let modules = ModuleHost(switchboard: ModuleSwitchboard(), island: island)
        return AnyView(view.environmentObject(modules))
    }

    private func drawnPixels(_ view: AnyView, size: CGSize) -> Int {
        let host = NSHostingView(rootView: hosted(view))
        host.frame = CGRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()

        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            XCTFail("could not make a bitmap for a \(size) view")
            return 0
        }
        host.cacheDisplay(in: host.bounds, to: rep)

        guard let data = rep.bitmapData else { return 0 }
        let samples = rep.samplesPerPixel
        var drawn = 0
        for pixel in 0..<(rep.pixelsWide * rep.pixelsHigh)
        where data[(pixel * samples) + (samples - 1)] > 0 {
            drawn += 1
        }
        return drawn
    }

    private func laptop(
        _ percentage: Int = 80,
        _ source: PowerSnapshot.Source = .wall
    ) -> PowerSnapshot {
        PowerSnapshot(
            isPresent: true,
            percentage: percentage,
            source: source,
            isCharging: source == .wall,
            isCharged: false,
            timeRemaining: .seconds(95 * 60)
        )
    }

    private func airPods() -> AccessoryBattery {
        AccessoryBattery(
            id: "00-11-22",
            name: "AirPods Pro",
            kind: .earbuds,
            levels: .init(left: 72, right: 68, caseLevel: 90)
        )
    }

    // MARK: - TC-BAT-003

    func test_TC_BAT_003_theListDrawsTheMacAndEveryAccessory() {
        let view = AnyView(
            BatteryStatusList(
                power: laptop(),
                accessories: [
                    airPods(),
                    AccessoryBattery(
                        id: "aa",
                        name: "Magic Mouse",
                        kind: .mouse,
                        levels: .init(single: 45)
                    )
                ]
            )
        )

        let size = CGSize(
            width: 380,
            height: BatteryStatusList.height(macBattery: true, accessories: 2)
        )
        XCTAssertGreaterThan(drawnPixels(view, size: size), 500)
    }

    // MARK: - TC-BAT-005

    /// A desktop Mac draws no battery row and still draws its accessories —
    /// the row is absent, not a zero.
    func test_TC_BAT_005_aDesktopMacDrawsAccessoriesAndNoBatteryRow() {
        let size = CGSize(width: 380, height: 160)

        let withMac = drawnPixels(
            AnyView(BatteryStatusList(power: laptop(), accessories: [airPods()])),
            size: size
        )
        let withoutMac = drawnPixels(
            AnyView(BatteryStatusList(power: .absent, accessories: [airPods()])),
            size: size
        )

        XCTAssertGreaterThan(withoutMac, 0)
        XCTAssertLessThan(withoutMac, withMac)
    }

    /// Nothing at all to report still draws a sentence rather than a blank
    /// box — the same rule the empty shelf follows.
    func test_anEmptyListSaysSoRatherThanDrawingNothing() {
        let view = AnyView(BatteryStatusList(power: .absent, accessories: []))
        XCTAssertGreaterThan(drawnPixels(view, size: CGSize(width: 380, height: 120)), 100)
    }

    // MARK: - Announcements

    func test_everyAnnouncementDrawsWithoutTrapping() {
        let reasons: [BatteryActivity.Reason] = [
            .pluggedIn(80), .unplugged(80), .low(8), .charged
        ]

        for reason in reasons {
            let activity = BatteryActivity(reason: reason, power: laptop())
            let drawn = drawnPixels(activity.peekView(), size: activity.peekSize)
            XCTAssertGreaterThan(drawn, 50, "\(reason) drew nothing")
        }
    }

    /// Hovering an announcement opens into the full list — the thing you want
    /// after "battery low" is "how low, and what else is flat".
    func test_anAnnouncementExpandsIntoTheFullList() {
        let activity = BatteryActivity(
            reason: .low(8),
            power: laptop(8, .battery),
            accessories: [airPods()]
        )

        XCTAssertGreaterThan(
            drawnPixels(activity.expandedView(), size: activity.expandedSize),
            300
        )
    }

    // MARK: - The gauge

    /// The gauge is drawn rather than taken from SF Symbols so the fill
    /// tracks the real level instead of snapping to the nearest 25%.
    func test_theGaugeFillTracksTheLevel() {
        let size = CGSize(width: 30, height: 14)

        let empty = drawnPixels(AnyView(BatteryGauge(percentage: 2)), size: size)
        let half = drawnPixels(AnyView(BatteryGauge(percentage: 50)), size: size)
        let full = drawnPixels(AnyView(BatteryGauge(percentage: 100)), size: size)

        XCTAssertLessThan(empty, half)
        XCTAssertLessThan(half, full)
    }
}
