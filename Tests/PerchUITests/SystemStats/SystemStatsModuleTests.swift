import AppKit
import PerchCore
import SwiftUI
import XCTest

@testable import PerchUI

/// Covers `TEST-PLAN.md` § SYS for the parts that need the real module —
/// TC-SYS-009 above all, which is the reason `CLAUDE.md` §4 singles this
/// module out.
///
/// The sampler's lifetime belongs to the view. These tests stand in for the
/// view by calling `beginSampling` and `endSampling` directly, which is
/// exactly what `onAppear` and `onDisappear` do.
@MainActor
final class SystemStatsModuleTests: XCTestCase {

    private struct Harness {
        let stats: SystemStatsService
        let island: IslandController
    }

    private func makeService() -> Harness {
        let island = IslandController(sleep: { _ in try await Task.sleep(for: .seconds(86_400)) })
        return Harness(stats: SystemStatsService(island: island), island: island)
    }

    // MARK: - TC-SYS-009

    /// **The rule the module exists under.** Switching it on starts no
    /// sampler: it puts a gauge on the island, and the gauge's *view*
    /// appearing is what starts sampling.
    func test_TC_SYS_009_activatingStartsNoSampler() {
        let harness = makeService()
        harness.stats.activate()

        XCTAssertTrue(harness.stats.isActive)
        XCTAssertFalse(harness.stats.isSampling, "a switched-on module is not a sampling one")
        XCTAssertEqual(harness.stats.demand, SamplerPolicy.Demand.none)

        harness.stats.deactivate()
    }

    func test_TC_SYS_009_nothingDrawingMeansNoSampler() {
        let harness = makeService()
        harness.stats.activate()

        harness.stats.beginSampling(.microGauge)
        XCTAssertTrue(harness.stats.isSampling)

        harness.stats.endSampling(.microGauge)
        XCTAssertFalse(harness.stats.isSampling, "not a slower timer — none")
        XCTAssertEqual(harness.stats.demand, SamplerPolicy.Demand.none)

        harness.stats.deactivate()
    }

    /// Both views can be up at once during the expand animation. The one
    /// that disappears first must not stop the other's sampler, which is
    /// why the service counts demands rather than holding a flag.
    func test_TC_SYS_009_theGaugeGoingAwayDoesNotStopTheGridsSampler() {
        let harness = makeService()
        harness.stats.activate()

        harness.stats.beginSampling(.microGauge)
        harness.stats.beginSampling(.expanded)
        XCTAssertEqual(harness.stats.demand, SamplerPolicy.Demand.expanded)

        harness.stats.endSampling(.microGauge)

        XCTAssertTrue(harness.stats.isSampling)
        XCTAssertEqual(harness.stats.demand, SamplerPolicy.Demand.expanded)

        harness.stats.endSampling(.expanded)
        XCTAssertFalse(harness.stats.isSampling)

        harness.stats.deactivate()
    }

    /// Two views of the same kind — which happens while SwiftUI is swapping
    /// one out for another — must not leave a sampler behind when only one
    /// of them goes.
    func test_TC_SYS_009_balancedBeginAndEndPairsLeaveNothingRunning() {
        let harness = makeService()
        harness.stats.activate()

        harness.stats.beginSampling(.microGauge)
        harness.stats.beginSampling(.microGauge)
        harness.stats.endSampling(.microGauge)
        XCTAssertTrue(harness.stats.isSampling, "one view is still drawing")

        harness.stats.endSampling(.microGauge)
        XCTAssertFalse(harness.stats.isSampling)

        harness.stats.deactivate()
    }

    /// An unbalanced `endSampling` — a view torn down twice — must not
    /// drive the count negative and leave the module unable to sample again.
    func test_TC_SYS_009_anUnbalancedEndDoesNotBreakTheCount() {
        let harness = makeService()
        harness.stats.activate()

        harness.stats.endSampling(.microGauge)
        harness.stats.endSampling(.microGauge)

        harness.stats.beginSampling(.microGauge)
        XCTAssertTrue(harness.stats.isSampling)

        harness.stats.endSampling(.microGauge)
        XCTAssertFalse(harness.stats.isSampling)

        harness.stats.deactivate()
    }

    func test_TC_SYS_009_askingToSampleWhileTheModuleIsOffDoesNothing() {
        let harness = makeService()

        harness.stats.beginSampling(.expanded)

        XCTAssertFalse(harness.stats.isSampling)
        XCTAssertNil(harness.island.presented)
    }

    // MARK: - TC-SYS-011

    func test_TC_SYS_011_switchingTheModuleOffTearsDownEverySampler() {
        let harness = makeService()
        harness.stats.activate()
        harness.stats.beginSampling(.expanded)
        XCTAssertTrue(harness.stats.isSampling)

        harness.stats.deactivate()

        XCTAssertFalse(harness.stats.isSampling)
        XCTAssertEqual(harness.stats.demand, SamplerPolicy.Demand.none)
        XCTAssertTrue(harness.stats.cpuHistory.isEmpty)
        XCTAssertNil(harness.island.presented)
    }

    func test_TC_SYS_011_deactivatingTwiceIsSafe() {
        let harness = makeService()
        harness.stats.activate()
        harness.stats.deactivate()
        harness.stats.deactivate()

        XCTAssertFalse(harness.stats.isActive)
    }

    func test_TC_SYS_011_theModuleSurvivesBeingSwitchedOnAndOffRepeatedly() {
        let harness = makeService()

        for _ in 0..<5 {
            harness.stats.activate()
            harness.stats.beginSampling(.microGauge)
            harness.stats.deactivate()
            XCTAssertFalse(harness.stats.isSampling)
        }
    }

    // MARK: - Sampling really reads something

    /// A sampler that exists must produce readings. The numbers themselves
    /// are the machine's and cannot be asserted, but "CPU reported a value
    /// and memory has a size" holds on every Mac.
    func test_TC_SYS_001_samplingProducesAReadingOfThisMachine() {
        let harness = makeService()
        harness.stats.activate()
        harness.stats.beginSampling(.expanded)

        XCTAssertGreaterThan(harness.stats.snapshot.memory.total, 0)
        XCTAssertGreaterThan(harness.stats.snapshot.uptime, .seconds(0))
        XCTAssertFalse(harness.stats.snapshot.disks.isEmpty)
        XCTAssertFalse(harness.stats.cpuHistory.isEmpty, "the first reading is immediate")

        harness.stats.endSampling(.expanded)
        harness.stats.deactivate()
    }

    /// The first CPU reading has no previous counters to difference
    /// against, so it must be zero rather than the machine's average since
    /// boot — which is not what anybody means by "CPU now".
    func test_TC_SYS_001_theFirstCPUReadingIsZeroRatherThanSinceBoot() {
        let harness = makeService()
        harness.stats.activate()
        harness.stats.beginSampling(.microGauge)

        XCTAssertEqual(harness.stats.snapshot.cpu.total, 0)

        harness.stats.endSampling(.microGauge)
        harness.stats.deactivate()
    }

    // MARK: - TC-SYS-012

    /// **Off, and no request made.** The one network switch in the app.
    func test_TC_SYS_012_thePublicIPReadoutIsOffByDefault() {
        let harness = makeService()
        harness.stats.activate()

        XCTAssertFalse(harness.stats.isPublicIPEnabled)
        XCTAssertNil(harness.stats.snapshot.network.publicIP)

        harness.stats.deactivate()
    }

    func test_TC_SYS_012_switchingItOffClearsTheAddress() {
        let harness = makeService()
        harness.stats.activate()

        harness.stats.setPublicIP("203.0.113.9")
        XCTAssertEqual(harness.stats.snapshot.network.publicIP, "203.0.113.9")

        harness.stats.setPublicIPEnabled(false)
        XCTAssertNil(harness.stats.snapshot.network.publicIP)

        harness.stats.deactivate()
    }

    /// A captive portal answers a plain-text request with HTML. Showing that
    /// in the island would be absurd, so anything that is not an address is
    /// no address.
    func test_TC_SYS_013_onlySomethingShapedLikeAnAddressIsAccepted() {
        XCTAssertTrue(SystemStatsService.isPlausibleAddress("203.0.113.9"))
        XCTAssertTrue(SystemStatsService.isPlausibleAddress("2001:db8::1"))

        XCTAssertFalse(SystemStatsService.isPlausibleAddress(""))
        XCTAssertFalse(SystemStatsService.isPlausibleAddress("<!DOCTYPE html>"))
        XCTAssertFalse(
            SystemStatsService.isPlausibleAddress("Sign in to the hotel network to continue")
        )
    }

    // MARK: - Gauges

    func test_onlyTwoGaugesEverFitBesideTheNotch() {
        let harness = makeService()
        harness.stats.activate()

        harness.stats.setGauges([.cpu, .memory, .network, .temperature])
        XCTAssertEqual(harness.stats.gauges.count, 2)

        harness.stats.setGauges([.cpu, .memory])
        harness.stats.deactivate()
    }

    func test_gaugeChoicesSurviveTheModuleBeingSwitchedOff() {
        let harness = makeService()
        harness.stats.activate()

        harness.stats.setGauges([.network, .temperature])
        harness.stats.deactivate()
        harness.stats.activate()

        XCTAssertEqual(harness.stats.gauges, [.network, .temperature])

        harness.stats.setGauges([.cpu, .memory])
        harness.stats.deactivate()
    }
}
