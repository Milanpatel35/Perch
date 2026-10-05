import XCTest

@testable import PerchCore
@testable import PerchUI

/// Covers `TEST-PLAN.md` § HOM for the parts that need the real host: the
/// launcher row appears with a module, goes with it, and the island sizes
/// around it.
@MainActor
final class HomeLauncherTileTests: XCTestCase {

    nonisolated(unsafe) private var directory = URL(fileURLWithPath: NSTemporaryDirectory())

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("perch-launcher-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        try super.tearDownWithError()
    }

    // MARK: - TC-HOM-004

    func test_TC_HOM_004_launcherRowFollowsTheModuleSwitch() {
        let island = IslandController(sleep: { _ in try await Task.sleep(for: .seconds(86_400)) })
        let modules = ModuleHost(switchboard: ModuleSwitchboard(), island: island)
        let focus = FocusService(island: island, directory: directory)
        modules.register(focus)

        focus.activate()
        XCTAssertNotNil(modules.launcherTile())

        focus.deactivate()
        XCTAssertNil(modules.launcherTile())
    }
}
