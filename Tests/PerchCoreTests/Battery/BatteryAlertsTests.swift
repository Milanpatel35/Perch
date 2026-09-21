import XCTest

@testable import PerchCore

/// Covers `TEST-PLAN.md` § BAT at unit level — when the battery is worth
/// interrupting someone for, with no battery in the loop. CI runners do not
/// have one, which is exactly why these rules live in a pure type.
final class BatteryAlertsTests: XCTestCase {

    private func snapshot(
        _ percentage: Int,
        _ source: PowerSnapshot.Source,
        charging: Bool = false,
        charged: Bool = false
    ) -> PowerSnapshot {
        PowerSnapshot(
            isPresent: true,
            percentage: percentage,
            source: source,
            isCharging: charging,
            isCharged: charged,
            timeRemaining: nil
        )
    }

    /// Settles the baseline without asserting on it. The first reading never
    /// announces anything, which every test here relies on.
    private func primed(
        at percentage: Int = 80,
        _ source: PowerSnapshot.Source = .battery,
        threshold: Int = 20
    ) -> BatteryAlerts {
        var alerts = BatteryAlerts(lowThreshold: threshold)
        XCTAssertTrue(alerts.ingest(snapshot(percentage, source)).isEmpty)
        return alerts
    }

    // MARK: - TC-BAT-001

    func test_TC_BAT_001_chargingFiresOnceNotRepeatedly() {
        var alerts = primed(at: 50, .battery)

        XCTAssertEqual(alerts.ingest(snapshot(50, .wall, charging: true)), [.pluggedIn(50)])

        // Six more readings at the wall. IOPS sends one per percentage point,
        // and none of them is news.
        for level in 51...56 {
            XCTAssertEqual(alerts.ingest(snapshot(level, .wall, charging: true)), [])
        }
    }

    /// The fluctuation case, and the reason `sourceChange` is keyed on
    /// `source` rather than on `isCharging` (TC-HUD-005 says the same thing
    /// about the HUD). Observed on the machine this module was written on,
    /// sitting at 80% on the wall with `isCharging` false.
    func test_TC_BAT_007_chargingThatStopsAndStartsAtTheWallSaysNothing() {
        var alerts = primed(at: 50, .battery)
        XCTAssertEqual(alerts.ingest(snapshot(50, .wall, charging: true)), [.pluggedIn(50)])

        // macOS holds at 80% for battery health: charging goes false, the
        // cable has not moved.
        XCTAssertEqual(alerts.ingest(snapshot(80, .wall, charging: false)), [])
        XCTAssertEqual(alerts.ingest(snapshot(80, .wall, charging: true)), [])
        XCTAssertEqual(alerts.ingest(snapshot(80, .wall, charging: false)), [])
    }

    func test_unpluggingIsAnnouncedToo() {
        var alerts = primed(at: 90, .wall)
        XCTAssertEqual(alerts.ingest(snapshot(90, .battery)), [.unplugged(90)])
    }

    // MARK: - TC-BAT-002

    func test_TC_BAT_002_lowBatteryFiresOncePerDischargeCycle() {
        var alerts = primed(at: 40, .battery)

        XCTAssertEqual(alerts.ingest(snapshot(20, .battery)), [.low(20)])

        // Still draining. Already said.
        for level in [19, 18, 17, 12, 8, 5, 3] {
            XCTAssertEqual(alerts.ingest(snapshot(level, .battery)), [])
        }
    }

    /// A battery under load does not fall monotonically — it crosses the
    /// threshold, recovers a point when a core parks, and crosses it again.
    /// Rearming on the level would warn every time it did.
    func test_TC_BAT_002_recoveringAcrossTheThresholdDoesNotRearmTheWarning() {
        var alerts = primed(at: 25, .battery)

        XCTAssertEqual(alerts.ingest(snapshot(19, .battery)), [.low(19)])
        XCTAssertEqual(alerts.ingest(snapshot(21, .battery)), [])
        XCTAssertEqual(alerts.ingest(snapshot(18, .battery)), [])
    }

    func test_TC_BAT_002_pluggingInRearmsTheWarningForTheNextCycle() {
        var alerts = primed(at: 40, .battery)
        XCTAssertEqual(alerts.ingest(snapshot(15, .battery)), [.low(15)])

        XCTAssertEqual(alerts.ingest(snapshot(15, .wall, charging: true)), [.pluggedIn(15)])
        XCTAssertEqual(alerts.ingest(snapshot(90, .wall, charging: true)), [])

        // Second cycle. This one gets its own warning.
        XCTAssertEqual(alerts.ingest(snapshot(90, .battery)), [.unplugged(90)])
        XCTAssertEqual(alerts.ingest(snapshot(19, .battery)), [.low(19)])
    }

    func test_TC_BAT_002_thresholdIsConfigurable() {
        var alerts = primed(at: 60, .battery, threshold: 50)
        XCTAssertEqual(alerts.ingest(snapshot(50, .battery)), [.low(50)])
    }

    /// Enabling the module at 12% must not then warn at 11% as though it had
    /// just watched it fall. The baseline seeds the flag instead.
    func test_enablingTheModuleBelowTheThresholdDoesNotWarnOnTheNextPoint() {
        var alerts = primed(at: 12, .battery)
        XCTAssertEqual(alerts.ingest(snapshot(11, .battery)), [])
    }

    // MARK: - Charged

    func test_fullyChargedIsAnnouncedOnce() {
        var alerts = primed(at: 95, .wall)

        XCTAssertEqual(alerts.ingest(snapshot(100, .wall, charged: true)), [.charged])
        XCTAssertEqual(alerts.ingest(snapshot(100, .wall, charged: true)), [])
    }

    func test_chargedRearmsOnceTheBatteryIsNotFullAnyMore() {
        var alerts = primed(at: 95, .wall)
        XCTAssertEqual(alerts.ingest(snapshot(100, .wall, charged: true)), [.charged])

        XCTAssertEqual(alerts.ingest(snapshot(99, .wall, charging: true)), [])
        XCTAssertEqual(alerts.ingest(snapshot(100, .wall, charged: true)), [.charged])
    }

    // MARK: - TC-BAT-005

    func test_TC_BAT_005_aMacWithNoBatteryNeverAlerts() {
        var alerts = BatteryAlerts()

        for _ in 0..<5 {
            XCTAssertEqual(alerts.ingest(.absent), [])
        }
    }

    // MARK: - Lifecycle

    /// Switching the module off and on again must not replay the transition
    /// that happened while it was not watching.
    func test_resetReturnsToABaselineThatAnnouncesNothing() {
        var alerts = primed(at: 50, .battery)
        XCTAssertEqual(alerts.ingest(snapshot(50, .wall, charging: true)), [.pluggedIn(50)])

        alerts.reset()
        XCTAssertEqual(alerts.ingest(snapshot(50, .battery)), [])
    }
}
