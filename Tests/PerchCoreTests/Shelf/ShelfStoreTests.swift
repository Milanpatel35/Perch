import XCTest

@testable import PerchCore

/// Covers `TEST-PLAN.md` § SHF at unit level — the rules about what is on the
/// shelf, with no filesystem in the loop.
final class ShelfStoreTests: XCTestCase {

    private func file(
        _ name: String,
        at path: String? = nil,
        added: Date = .now,
        bytes: Int64 = 1024
    ) -> ShelfItem {
        ShelfItem(
            kind: .file,
            name: name,
            storedPath: "/container/\(name)",
            originalPath: path ?? "/Users/someone/Desktop/\(name)",
            byteCount: bytes,
            addedAt: added
        )
    }

    // MARK: - TC-SHF-003

    func test_TC_SHF_003_fiftyFilesAtOnceAreAllAccepted() {
        var store = ShelfStore()
        let epoch = Date(timeIntervalSinceReferenceDate: 0)

        store.add(
            (0..<50).map {
                file("file-\($0).txt", added: epoch.addingTimeInterval(Double($0)))
            })

        XCTAssertEqual(store.count, 50)
        XCTAssertEqual(store.badgeCount, 50)
    }

    func test_theNewestThingIsOnTop() {
        var store = ShelfStore()
        let epoch = Date(timeIntervalSinceReferenceDate: 0)

        store.add([file("old.txt", added: epoch)])
        store.add([file("new.txt", added: epoch.addingTimeInterval(60))])

        XCTAssertEqual(store.items.first?.name, "new.txt")
    }

    func test_theShelfIsBoundedSoItCannotGrowForever() {
        var store = ShelfStore()
        let epoch = Date(timeIntervalSinceReferenceDate: 0)

        store.add(
            (0..<200).map {
                file("file-\($0).txt", added: epoch.addingTimeInterval(Double($0)))
            })

        XCTAssertEqual(store.count, ShelfStore.capacity)
        // The oldest go, not the newest. Someone who just dropped something
        // must still find it.
        XCTAssertEqual(store.items.first?.name, "file-199.txt")
    }

    func test_droppingTheSameFileTwiceRefreshesItRatherThanDuplicatingIt() {
        var store = ShelfStore()
        let epoch = Date(timeIntervalSinceReferenceDate: 0)

        store.add([file("report.pdf", added: epoch)])
        store.add([file("report.pdf", added: epoch.addingTimeInterval(120))])

        XCTAssertEqual(store.count, 1)
        XCTAssertEqual(store.items.first?.addedAt, epoch.addingTimeInterval(120))
    }

    func test_twoDifferentFilesWithTheSameNameAreTwoItems() {
        var store = ShelfStore()
        store.add([file("notes.md", at: "/Users/someone/a/notes.md")])
        store.add([file("notes.md", at: "/Users/someone/b/notes.md")])

        XCTAssertEqual(store.count, 2)
    }

    // MARK: - TC-SHF-004

    func test_TC_SHF_004_theShelfSurvivesBeingEncodedAndRead() {
        var store = ShelfStore()
        store.add([file("contract.pdf"), file("logo.svg")])

        let data = try? JSONEncoder().encode(store)
        XCTAssertNotNil(data)

        let restored = try? JSONDecoder().decode(ShelfStore.self, from: XCTUnwrap(data))
        XCTAssertEqual(restored?.count, 2)
        XCTAssertEqual(restored?.items.map(\.name).sorted(), ["contract.pdf", "logo.svg"])
    }

    // MARK: - TC-SHF-005

    func test_TC_SHF_005_aMissingFileIsMarkedUnavailableRatherThanRemoved() {
        var store = ShelfStore()
        store.add([file("gone.txt"), file("here.txt")])

        store.refreshAvailability { path in path.hasSuffix("here.txt") }

        // Still two rows. An item vanishing with no explanation reads as
        // Perch having lost it; a greyed row reads as what happened.
        XCTAssertEqual(store.count, 2)
        XCTAssertEqual(store.items.first { $0.name == "gone.txt" }?.isAvailable, false)
        XCTAssertEqual(store.items.first { $0.name == "here.txt" }?.isAvailable, true)
    }

    func test_TC_SHF_005_anItemThatComesBackIsAvailableAgain() {
        var store = ShelfStore()
        store.add([file("flaky.txt")])

        store.refreshAvailability { _ in false }
        XCTAssertEqual(store.items.first?.isAvailable, false)

        store.refreshAvailability { _ in true }
        XCTAssertEqual(store.items.first?.isAvailable, true)
    }

    // MARK: - TC-SHF-008

    func test_TC_SHF_008_clearingEmptiesEverything() {
        var store = ShelfStore()
        store.add([file("a.txt"), file("b.txt")])

        store.removeAll()

        XCTAssertTrue(store.isEmpty)
        XCTAssertEqual(store.badgeCount, 0)
        XCTAssertEqual(store.byteCount, 0)
    }

    func test_removingOneLeavesTheRest() throws {
        var store = ShelfStore()
        store.add([file("a.txt"), file("b.txt")])
        let target = try XCTUnwrap(store.items.first)

        store.remove(target.id)

        XCTAssertEqual(store.count, 1)
        XCTAssertNil(store.items.first { $0.id == target.id })
    }

    // MARK: - TC-SHF-009

    func test_TC_SHF_009_twoIdenticalClippingsAreOneItem() {
        var store = ShelfStore()
        let payload = Data("the same words".utf8)

        store.add([ShelfItem(kind: .text, name: "the same words", payload: payload)])
        store.add([ShelfItem(kind: .text, name: "the same words", payload: payload)])

        XCTAssertEqual(store.count, 1)
    }

    func test_TC_SHF_009_aClippingAndAFileAreNeverTheSameThing() {
        var store = ShelfStore()
        store.add([ShelfItem(kind: .text, name: "notes", payload: Data())])
        store.add([file("notes")])

        XCTAssertEqual(store.count, 2)
    }
}
