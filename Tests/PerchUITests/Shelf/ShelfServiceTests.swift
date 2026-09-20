import Defaults
import PerchCore
import XCTest

@testable import PerchUI

/// Covers `TEST-PLAN.md` § SHF for the parts that need a real directory:
/// copying rather than moving, surviving a relaunch, and clearing on quit.
///
/// Every test gets its own temporary directory, so nothing here can touch the
/// real shelf and no test can see another's files.
@MainActor
final class ShelfServiceTests: XCTestCase {

    private var directory = URL(fileURLWithPath: NSTemporaryDirectory())
    private var desktop = URL(fileURLWithPath: NSTemporaryDirectory())

    override func setUp() async throws {
        try await super.setUp()
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("perch-shelf-\(UUID().uuidString)")
        directory = root.appendingPathComponent("Shelf")
        desktop = root.appendingPathComponent("Desktop")

        for url in [directory, desktop] {
            try FileManager.default.createDirectory(
                at: url,
                withIntermediateDirectories: true
            )
        }
        Defaults[.shelfClearOnQuit] = false
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory.deletingLastPathComponent())
        Defaults.reset(.shelfClearOnQuit)
        try await super.tearDown()
    }

    private func makeService() -> (ShelfService, IslandController) {
        let island = IslandController(sleep: { _ in try await Task.sleep(for: .seconds(86_400)) })
        return (ShelfService(island: island, directory: directory), island)
    }

    @discardableResult
    private func makeFile(_ name: String, contents: String = "hello") throws -> URL {
        let url = desktop.appendingPathComponent(name)
        try Data(contents.utf8).write(to: url)
        return url
    }

    // MARK: - TC-SHF-002

    func test_TC_SHF_002_aDroppedFileIsCopiedAndTheOriginalIsUntouched() throws {
        let (shelf, _) = makeService()
        shelf.activate()

        let original = try makeFile("contract.pdf", contents: "the contract")
        let item = try XCTUnwrap(shelf.add(fileAt: original))

        // The original is exactly where it was, byte for byte.
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.path))
        XCTAssertEqual(try Data(contentsOf: original), Data("the contract".utf8))

        // And Perch has its own copy, somewhere else.
        let stored = try XCTUnwrap(item.storedURL)
        XCTAssertNotEqual(stored.path, original.path)
        XCTAssertTrue(stored.path.hasPrefix(directory.path))
        XCTAssertEqual(try Data(contentsOf: stored), Data("the contract".utf8))
    }

    func test_TC_SHF_002_removingFromTheShelfDoesNotTouchTheOriginal() throws {
        let (shelf, _) = makeService()
        shelf.activate()

        let original = try makeFile("keep.txt")
        let item = try XCTUnwrap(shelf.add(fileAt: original))

        shelf.remove(item.id)

        XCTAssertTrue(FileManager.default.fileExists(atPath: original.path))
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: try XCTUnwrap(item.storedPath)),
            "Perch's own copy should go when the row does"
        )
    }

    // MARK: - TC-SHF-004

    func test_TC_SHF_004_theShelfSurvivesARelaunch() throws {
        let (first, _) = makeService()
        first.activate()
        try first.add(fileAt: makeFile("persists.txt"))
        first.deactivate()

        // A second service over the same directory is what "next launch"
        // means for the shelf.
        let (second, _) = makeService()
        second.activate()

        XCTAssertEqual(second.store.count, 1)
        XCTAssertEqual(second.store.items.first?.name, "persists.txt")
        XCTAssertEqual(second.store.items.first?.isAvailable, true)
    }

    // MARK: - TC-SHF-005

    func test_TC_SHF_005_aCopyDeletedUnderneathIsMarkedUnavailableOnNextLaunch() throws {
        let (first, _) = makeService()
        first.activate()
        let item = try XCTUnwrap(first.add(fileAt: makeFile("vanishes.txt")))
        first.deactivate()

        // Somebody emptied the folder, or a sync client took it.
        try FileManager.default.removeItem(atPath: try XCTUnwrap(item.storedPath))

        let (second, _) = makeService()
        second.activate()

        XCTAssertEqual(second.store.count, 1, "the row should stay, greyed")
        XCTAssertEqual(second.store.items.first?.isAvailable, false)
    }

    // MARK: - TC-SHF-006

    func test_TC_SHF_006_aFolderIsOneItemNotItsContents() throws {
        let (shelf, _) = makeService()
        shelf.activate()

        let folder = desktop.appendingPathComponent("Project")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("a".utf8).write(to: folder.appendingPathComponent("a.txt"))
        try Data("b".utf8).write(to: folder.appendingPathComponent("b.txt"))

        let item = try XCTUnwrap(shelf.add(fileAt: folder))

        XCTAssertEqual(shelf.store.count, 1)
        XCTAssertEqual(item.kind, .folder)
        XCTAssertEqual(item.name, "Project")
    }

    // MARK: - TC-SHF-008

    func test_TC_SHF_008_clearOnQuitEmptiesTheShelfAndItsFiles() throws {
        Defaults[.shelfClearOnQuit] = true

        let (shelf, _) = makeService()
        shelf.activate()
        let item = try XCTUnwrap(shelf.add(fileAt: makeFile("temporary.txt")))

        shelf.applicationWillQuit()

        XCTAssertTrue(shelf.store.isEmpty)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: try XCTUnwrap(item.storedPath))
        )
    }

    func test_TC_SHF_008_clearOnQuitIsOffByDefaultAndKeepsEverything() throws {
        let (shelf, _) = makeService()
        shelf.activate()
        try shelf.add(fileAt: makeFile("survives.txt"))

        XCTAssertFalse(Defaults[.shelfClearOnQuit])
        shelf.applicationWillQuit()

        XCTAssertEqual(shelf.store.count, 1)
    }

    // MARK: - The island

    func test_anEmptyShelfPresentsNothingAtAll() {
        let (shelf, island) = makeService()
        shelf.activate()

        XCTAssertTrue(island.queued.allSatisfy { $0.source != .shelf })
    }

    func test_holdingSomethingIsAmbientButBeingDraggedOntoIsUrgent() throws {
        let (shelf, island) = makeService()
        shelf.activate()
        try shelf.add(fileAt: makeFile("held.txt"))

        let holding = try XCTUnwrap(island.queued.first { $0.source == .shelf })
        XCTAssertEqual(holding.priority, .ambient)

        shelf.beginDrag()

        let dropping = try XCTUnwrap(island.queued.first { $0.source == .shelf })
        XCTAssertEqual(dropping.priority, .fileDrop)
        XCTAssertGreaterThan(dropping.priority, ActivityPriority.nowPlaying)
    }

    func test_theShelfNeverExpiresOnItsOwn() throws {
        let (shelf, island) = makeService()
        shelf.activate()
        try shelf.add(fileAt: makeFile("held.txt"))

        // Files wait until they are taken. A shelf that emptied itself after
        // three seconds would be a notification.
        XCTAssertNil(island.queued.first { $0.source == .shelf }?.timeToLive)
    }

    // MARK: - TC-SHF-007 (module lifecycle)

    func test_TC_SHF_007_switchingTheModuleOffLeavesNothingOnTheIsland() throws {
        let (shelf, island) = makeService()
        shelf.activate()
        try shelf.add(fileAt: makeFile("held.txt"))
        XCTAssertNotNil(island.presented)

        shelf.deactivate()

        XCTAssertFalse(shelf.isActive)
        XCTAssertFalse(shelf.isDropTarget)
        XCTAssertTrue(island.queued.allSatisfy { $0.source != .shelf })
    }

    func test_TC_SHF_007_switchingItBackOnFindsEverythingStillThere() throws {
        let (shelf, _) = makeService()
        shelf.activate()
        try shelf.add(fileAt: makeFile("held.txt"))

        shelf.deactivate()
        shelf.activate()

        XCTAssertEqual(shelf.store.count, 1)
    }
}
