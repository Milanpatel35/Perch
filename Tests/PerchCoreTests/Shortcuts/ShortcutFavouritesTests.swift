import XCTest

@testable import PerchCore

/// Covers `TEST-PLAN.md` § SHC for the favourites list and for what a run
/// looks like once it is over.
final class ShortcutFavouritesTests: XCTestCase {

    // MARK: - TC-SHC-005

    func test_TC_SHC_005_favouritesKeepTheOrderTheyWereChosenIn() {
        var favourites = ShortcutFavourites()
        favourites.add("Morning")
        favourites.add("Standup notes")
        favourites.add("Lights off")

        XCTAssertEqual(favourites.names, ["Morning", "Standup notes", "Lights off"])
    }

    func test_TC_SHC_005_theSameShortcutTwiceIsOneButton() {
        var favourites = ShortcutFavourites()
        XCTAssertTrue(favourites.add("Morning"))
        XCTAssertFalse(favourites.add("Morning"))
        XCTAssertFalse(favourites.add("  Morning\n"))
        XCTAssertFalse(favourites.add("   "))

        XCTAssertEqual(favourites.names, ["Morning"])
    }

    func test_TC_SHC_005_favouritesStopAtSix() {
        var favourites = ShortcutFavourites()
        for index in 1...10 {
            favourites.add("Shortcut \(index)")
        }

        XCTAssertEqual(favourites.names.count, ShortcutFavourites.capacity)
        XCTAssertTrue(favourites.isFull)
        XCTAssertEqual(favourites.names.last, "Shortcut 6")
    }

    func test_TC_SHC_005_theInitialiserObeysTheSameRules() {
        let favourites = ShortcutFavourites(names: ["a", "a", "", "b", "c", "d", "e", "f", "g"])
        XCTAssertEqual(favourites.names, ["a", "b", "c", "d", "e", "f"])
    }

    func test_TC_SHC_005_movingStaysInsideTheList() {
        var favourites = ShortcutFavourites(names: ["a", "b", "c"])

        favourites.move("c", by: -1)
        XCTAssertEqual(favourites.names, ["a", "c", "b"])

        favourites.move("a", by: -5)
        XCTAssertEqual(favourites.names, ["a", "c", "b"])

        favourites.move("a", by: 99)
        XCTAssertEqual(favourites.names, ["c", "b", "a"])

        favourites.move("missing", by: 1)
        XCTAssertEqual(favourites.names, ["c", "b", "a"])
    }

    func test_TC_SHC_005_removing() {
        var favourites = ShortcutFavourites(names: ["a", "b"])
        favourites.remove("a")
        XCTAssertEqual(favourites.names, ["b"])
        XCTAssertFalse(favourites.isFull)
    }

    /// A renamed shortcut is reported, not silently dropped — and an
    /// unreadable library is not mistaken for an empty one.
    func test_TC_SHC_005_aRenamedShortcutIsReportedMissingNotRemoved() {
        let favourites = ShortcutFavourites(names: ["Morning", "Old name"])

        XCTAssertEqual(favourites.missing(from: ["Morning", "New name"]), ["Old name"])
        XCTAssertEqual(favourites.missing(from: []), [])
        XCTAssertEqual(favourites.names, ["Morning", "Old name"])
    }

    // MARK: - TC-SHC-001

    func test_TC_SHC_001_aSuccessfulRunReportsItsFirstLine() {
        XCTAssertEqual(
            ShortcutOutcome.from(exitCode: 0, output: "\n  Lights off  \nsecond line", error: ""),
            .succeeded(output: "Lights off")
        )
        XCTAssertEqual(
            ShortcutOutcome.from(exitCode: 0, output: "", error: "a warning"),
            .succeeded(output: nil)
        )
    }

    func test_TC_SHC_001_aFailureAlwaysSaysSomething() {
        XCTAssertEqual(
            ShortcutOutcome.from(exitCode: 1, output: "", error: "Couldn’t find shortcut\n"),
            .failed(reason: "Couldn’t find shortcut")
        )

        guard case .failed(let reason) = ShortcutOutcome.from(exitCode: 3, output: "", error: "")
        else { return XCTFail("a non-zero exit is a failure") }
        XCTAssertFalse(reason.isEmpty)
    }

    func test_TC_SHC_001_aLongLineIsCutToFitTheIsland() {
        let long = String(repeating: "x", count: 500)
        guard
            case .succeeded(let output?) = ShortcutOutcome.from(
                exitCode: 0, output: long, error: "")
        else { return XCTFail("expected output") }

        XCTAssertEqual(output.count, ShortcutOutcome.maximumLength)
        XCTAssertTrue(output.hasSuffix("…"))
    }
}
