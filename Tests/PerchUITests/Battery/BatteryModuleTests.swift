import PerchCore
import XCTest

@testable import PerchUI

/// Covers `TEST-PLAN.md` § BAT for the parts that need the real module — the
/// lifecycle, and what the island is told.
///
/// The readings themselves come from whatever Mac is running the suite, so
/// nothing here asserts a percentage. What it asserts is the contract that
/// holds on every Mac: a module that is off holds nothing, and a module that
/// is on never announces the state you were already in.
@MainActor
final class BatteryModuleTests: XCTestCase {

    private struct Harness {
        let battery: BatteryService
        let island: IslandController
    }

    /// A controller whose collapse timer never fires, so an activity stays
    /// put for the length of a test instead of expiring underneath it.
    private func makeService() -> Harness {
        let island = IslandController(sleep: { _ in try await Task.sleep(for: .seconds(86_400)) })
        return Harness(battery: BatteryService(island: island), island: island)
    }

    // MARK: - Lifecycle

    func test_activatingTwiceIsNotTwiceTheWork() {
        let harness = makeService()

        harness.battery.activate()
        harness.battery.activate()
        XCTAssertTrue(harness.battery.isActive)

        harness.battery.deactivate()
        XCTAssertFalse(harness.battery.isActive)
    }

    func test_deactivatingWhenAlreadyOffIsSafe() {
        let harness = makeService()

        harness.battery.deactivate()
        harness.battery.deactivate()
        XCTAssertFalse(harness.battery.isActive)
    }

    /// The §5.1 contract: a module that is off holds nothing at all. Not a
    /// slower timer, not a cheap observer — nothing.
    func test_TC_BAT_006_theModuleHoldsNothingWhileItIsOff() {
        let harness = makeService()

        harness.battery.activate()
        harness.battery.deactivate()

        XCTAssertFalse(harness.battery.isActive)
        XCTAssertFalse(harness.battery.power.isPresent)
        XCTAssertTrue(harness.battery.roster.isEmpty)
        XCTAssertNil(harness.island.presented)
    }

    /// Switching the module on must not announce the state you are already
    /// in — you can see the cable. `BatteryAlerts` ignores its first reading
    /// and this is the module-level proof of it.
    func test_switchingOnAnnouncesNothing() {
        let harness = makeService()

        harness.battery.activate()

        XCTAssertNil(harness.island.presented)
        XCTAssertTrue(harness.island.state.presentation.isIdle)
    }

    /// An off module must not answer the island's request for a tile, which
    /// is how the home surface loses the row without needing a rule for it.
    func test_TC_BAT_006_refreshingWhileOffDoesNothing() {
        let harness = makeService()

        harness.battery.refreshAccessories()
        harness.battery.showStatus()

        XCTAssertTrue(harness.battery.roster.isEmpty)
        XCTAssertNil(harness.island.presented)
    }

    // MARK: - The readable state

    func test_showStatusPutsTheListOnTheIsland() {
        let harness = makeService()
        harness.battery.activate()

        harness.battery.showStatus()

        XCTAssertEqual(harness.island.presented?.id, BatteryStatusActivity.identifier)
        XCTAssertEqual(harness.island.presented?.source, .battery)

        harness.battery.deactivate()
        XCTAssertNil(harness.island.presented)
    }

    /// The status activity stays until dismissed — it is a thing you opened,
    /// not a thing that happened to you.
    func test_theStatusListDoesNotExpireOnItsOwn() {
        let activity = BatteryStatusActivity(power: .absent, accessories: [])
        XCTAssertNil(activity.timeToLive)
        XCTAssertEqual(activity.priority, .fileDrop)
    }

    // MARK: - Priorities

    /// A low battery is the one thing this module has that is allowed to
    /// interrupt Now Playing (`CLAUDE.md` §3).
    func test_TC_BAT_002_lowBatteryOutranksNowPlaying() {
        let low = BatteryActivity(reason: .low(8), power: .absent)
        let plugged = BatteryActivity(reason: .pluggedIn(8), power: .absent)

        XCTAssertEqual(low.priority, .systemAlert)
        XCTAssertGreaterThan(low.priority, ActivityPriority.nowPlaying)
        XCTAssertEqual(plugged.priority, .ambient)
        XCTAssertLessThan(plugged.priority, ActivityPriority.nowPlaying)
    }

    func test_theLowWarningStaysUpLongerThanAPlugAnnouncement() {
        let low = BatteryActivity(reason: .low(8), power: .absent)
        let plugged = BatteryActivity(reason: .pluggedIn(80), power: .absent)

        XCTAssertGreaterThan(low.timeToLive ?? .zero, plugged.timeToLive ?? .zero)
    }

    /// Every announcement shares one id, so a charger going in while the
    /// "unplugged" peek is still up replaces it rather than queueing behind
    /// it.
    func test_announcementsReplaceEachOtherRatherThanStacking() {
        let harness = makeService()
        harness.battery.activate()

        harness.island.submit(BatteryActivity(reason: .unplugged(80), power: .absent))
        harness.island.submit(BatteryActivity(reason: .pluggedIn(80), power: .absent))

        XCTAssertEqual(harness.island.queued.filter { $0.source == .battery }.count, 1)
    }

    // MARK: - Presentation

    func test_TC_BAT_003_airPodsSummariseAsThreeLevels() {
        let airPods = AccessoryBattery(
            id: "a",
            name: "AirPods Pro",
            kind: .earbuds,
            levels: .init(left: 72, right: 68, caseLevel: 90)
        )

        XCTAssertEqual(airPods.levelSummary, "72% · 68% · 90%")
        XCTAssertFalse(airPods.isLow)
    }

    func test_aSingleLevelDeviceSummarisesAsOneNumber() {
        let mouse = AccessoryBattery(
            id: "b",
            name: "Magic Mouse",
            kind: .mouse,
            levels: .init(single: 12)
        )

        XCTAssertEqual(mouse.levelSummary, "12%")
        XCTAssertTrue(mouse.isLow)
    }

    func test_aDeviceThatStoppedReportingShowsNoNumberRatherThanZero() {
        let silent = AccessoryBattery(id: "c", name: "Dongle", kind: .other, levels: .init())
        XCTAssertEqual(silent.levelSummary, "—")
    }

    /// While macOS is working the estimate out — which it is for a minute or
    /// two after every change — there is nothing to say, and saying "0m
    /// left" would be a lie.
    func test_aMissingTimeEstimateSaysNothingAtAll() {
        XCTAssertNil(PowerSnapshot.absent.remainingDescription)

        let charging = PowerSnapshot(
            isPresent: true,
            percentage: 40,
            source: .wall,
            isCharging: true,
            isCharged: false,
            timeRemaining: .seconds(95 * 60)
        )
        XCTAssertEqual(charging.remainingDescription, "1h 35m to full")

        let draining = PowerSnapshot(
            isPresent: true,
            percentage: 40,
            source: .battery,
            isCharging: false,
            isCharged: false,
            timeRemaining: .seconds(42 * 60)
        )
        XCTAssertEqual(draining.remainingDescription, "42m left")
    }

    // MARK: - TC-BAT-005

    /// A desktop Mac draws no battery row and still lists its accessories.
    func test_TC_BAT_005_theListSizesItselfWithoutAMacBattery() {
        let withBattery = BatteryStatusList.height(macBattery: true, accessories: 2)
        let without = BatteryStatusList.height(macBattery: false, accessories: 2)

        XCTAssertLessThan(without, withBattery)
    }
}
