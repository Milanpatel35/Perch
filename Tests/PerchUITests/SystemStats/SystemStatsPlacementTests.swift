import Defaults
import PerchCore
import XCTest

@testable import PerchUI

/// Covers TC-SYS-016: where the monitor lives. By default it is a row on the
/// home surface and puts nothing permanent beside the notch, because the
/// gauge is wider than the notch and covers part of the menu bar.
@MainActor
final class SystemStatsPlacementTests: XCTestCase {

    private var saved = false

    override func setUp() async throws {
        saved = Defaults[.systemGaugeBesideNotch]
        Defaults[.systemGaugeBesideNotch] = false
    }

    override func tearDown() async throws {
        Defaults[.systemGaugeBesideNotch] = saved
    }

    private func makeService() -> (SystemStatsService, IslandController) {
        let island = IslandController(sleep: { _ in try await Task.sleep(for: .seconds(86_400)) })
        return (SystemStatsService(island: island), island)
    }

    func test_TC_SYS_016_byDefaultNothingSitsBesideTheNotch() {
        let (stats, island) = makeService()
        stats.activate()

        XCTAssertFalse(stats.showsBesideNotch)
        XCTAssertTrue(island.queued.isEmpty, "no gauge covering the menu bar")
        XCTAssertFalse(stats.isSampling)

        stats.deactivate()
    }

    func test_TC_SYS_016_theGaugeCanBePutBesideTheNotchAndTakenAway() {
        let (stats, island) = makeService()
        stats.activate()

        stats.setShowsBesideNotch(true)
        XCTAssertEqual(island.presented?.id, SystemStatsActivity.identifier)
        XCTAssertTrue(Defaults[.systemGaugeBesideNotch])

        stats.setShowsBesideNotch(false)
        XCTAssertTrue(island.queued.isEmpty)

        stats.deactivate()
    }

    func test_TC_SYS_016_theChoiceIsRememberedAcrossLaunches() {
        Defaults[.systemGaugeBesideNotch] = true
        let (stats, island) = makeService()
        stats.activate()

        XCTAssertEqual(island.presented?.id, SystemStatsActivity.identifier)
        stats.deactivate()
    }

    /// The home-surface row samples only while it is on screen, like the
    /// gauge: the view asks, and gives it back.
    func test_TC_SYS_016_theHomeRowSamplesOnlyWhileShowing() {
        let (stats, _) = makeService()
        stats.activate()
        XCTAssertNotNil(ModuleHost.tileProbe(stats))

        stats.beginSampling(.expanded)
        XCTAssertTrue(stats.isSampling)
        stats.endSampling(.expanded)
        XCTAssertFalse(stats.isSampling)

        stats.deactivate()
    }
}

private extension ModuleHost {
    /// The tile is built from the service; this stands in for the host so
    /// the test does not need a switchboard.
    @MainActor
    static func tileProbe(_ service: SystemStatsService) -> SystemStatsTile? {
        service.isActive ? SystemStatsTile(service: service) : nil
    }
}
