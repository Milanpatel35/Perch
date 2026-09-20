import XCTest

@testable import PerchCore

/// Covers `TEST-PLAN.md` § CLP at unit level — every rule about what the
/// clipboard keeps, with no pasteboard in the loop.
final class ClipboardHistoryTests: XCTestCase {

    /// "Now", not a fixed point in 2001.
    ///
    /// The default retention drops anything older than a week, so entries
    /// stamped in 2001 are pruned the instant they are recorded — which is
    /// correct behaviour and a useless fixture. Offsets from this are what
    /// the ordering assertions actually depend on.
    private let epoch = Date()

    private func text(_ value: String, at offset: TimeInterval = 0) -> ClipboardEntry {
        ClipboardEntry(
            kind: .text,
            text: value,
            copiedAt: epoch.addingTimeInterval(offset)
        )
    }

    // MARK: - TC-CLP-001

    func test_TC_CLP_001_aCopyLandsAtTheTop() {
        var history = ClipboardHistory()

        XCTAssertTrue(history.record(text("first", at: 0)))
        XCTAssertTrue(history.record(text("second", at: 10)))

        XCTAssertEqual(history.entries.first?.text, "second")
        XCTAssertEqual(history.count, 2)
    }

    // MARK: - TC-CLP-002

    func test_TC_CLP_002_copyingTheSameThingTwiceIsOneEntryWithANewerTimestamp() {
        var history = ClipboardHistory()
        history.record(text("the same thing", at: 0))

        let wasNew = history.record(text("the same thing", at: 60))

        XCTAssertFalse(wasNew, "a repeat should not be announced as new")
        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history.entries.first?.copiedAt, epoch.addingTimeInterval(60))
    }

    func test_TC_CLP_002_aDuplicateNeverUnpinsWhatWasPinned() throws {
        var history = ClipboardHistory()
        history.record(text("keep me", at: 0))
        history.togglePin(try XCTUnwrap(history.entries.first).id)

        history.record(text("keep me", at: 60))

        XCTAssertEqual(history.entries.first?.isPinned, true)
    }

    // MARK: - TC-CLP-004

    func test_TC_CLP_004_theOldestUnpinnedEntryIsEvictedAtTheLimit() {
        var history = ClipboardHistory(
            retention: .init(maximumCount: 3, maximumAge: nil)
        )

        for index in 0..<5 {
            history.record(text("entry \(index)", at: Double(index)))
        }

        XCTAssertEqual(history.count, 3)
        XCTAssertEqual(history.entries.map(\.text), ["entry 4", "entry 3", "entry 2"])
    }

    func test_TC_CLP_004_entriesOlderThanTheAgeLimitAreDropped() {
        var history = ClipboardHistory(
            retention: .init(maximumCount: 100, maximumAge: .seconds(3600))
        )
        history.record(text("ancient", at: 0), now: epoch)
        history.record(text("recent", at: 7000), now: epoch.addingTimeInterval(7000))

        history.prune(now: epoch.addingTimeInterval(7200))

        XCTAssertEqual(history.entries.map(\.text), ["recent"])
    }

    // MARK: - TC-CLP-005

    func test_TC_CLP_005_aPinnedEntryIsNeverEvictedByTheCountLimit() throws {
        var history = ClipboardHistory(
            retention: .init(maximumCount: 2, maximumAge: nil)
        )
        history.record(text("pinned", at: 0))
        history.togglePin(try XCTUnwrap(history.entries.first).id)

        for index in 1..<10 {
            history.record(text("entry \(index)", at: Double(index)))
        }

        XCTAssertTrue(history.entries.contains { $0.text == "pinned" })
        XCTAssertEqual(history.pinned.count, 1)
    }

    func test_TC_CLP_005_aPinnedEntryIsNeverEvictedByAge() throws {
        var history = ClipboardHistory(
            retention: .init(maximumCount: 100, maximumAge: .seconds(60))
        )
        history.record(text("ancient but pinned", at: 0), now: epoch)
        history.togglePin(try XCTUnwrap(history.entries.first).id)

        history.prune(now: epoch.addingTimeInterval(86_400))

        XCTAssertEqual(history.count, 1)
    }

    func test_TC_CLP_005_pinnedEntriesSortAboveTheRest() throws {
        var history = ClipboardHistory()
        history.record(text("old", at: 0))
        history.record(text("new", at: 100))
        history.togglePin(try XCTUnwrap(history.entries.last).id)

        XCTAssertEqual(history.entries.first?.text, "old")
        XCTAssertEqual(history.entries.first?.isPinned, true)
    }

    func test_clearingKeepsWhatWasPinned() throws {
        var history = ClipboardHistory()
        history.record(text("keep", at: 0))
        history.togglePin(try XCTUnwrap(history.entries.first).id)
        history.record(text("drop", at: 10))

        history.clearUnpinned()

        XCTAssertEqual(history.entries.map(\.text), ["keep"])
    }

    // MARK: - TC-CLP-010

    func test_TC_CLP_010_searchOverTenThousandEntriesStaysUnderFiftyMilliseconds() {
        // Built directly rather than through ten thousand `record` calls:
        // the case is about how fast *search* is on a large history, and
        // recording is a separate question with its own cost.
        let history = ClipboardHistory(
            entries: (0..<10_000).map { text("entry number \($0)", at: Double($0)) },
            retention: .init(maximumCount: 10_000, maximumAge: nil)
        )
        XCTAssertEqual(history.count, 10_000)

        let started = Date()
        let results = history.search("number 9999")
        let elapsed = Date().timeIntervalSince(started)

        XCTAssertEqual(results.count, 1)
        XCTAssertLessThan(elapsed, 0.05, "search took \(elapsed * 1000)ms")
    }

    func test_TC_CLP_010_searchIsCaseInsensitiveAndMatchesAnywhere() {
        var history = ClipboardHistory()
        history.record(text("The Quick Brown Fox", at: 0))

        XCTAssertEqual(history.search("quick").count, 1)
        XCTAssertEqual(history.search("BROWN").count, 1)
        XCTAssertEqual(history.search("own fo").count, 1)
        XCTAssertEqual(history.search("zebra").count, 0)
    }

    func test_TC_CLP_010_anEmptyQueryReturnsEverything() {
        var history = ClipboardHistory()
        history.record(text("a", at: 0))
        history.record(text("b", at: 1))

        XCTAssertEqual(history.search("").count, 2)
        XCTAssertEqual(history.search("   ").count, 2)
    }

    // MARK: - TC-CLP-011

    func test_TC_CLP_011_aColourIsSearchableByHexAndByRgb() {
        var history = ClipboardHistory()
        history.record(
            ClipboardEntry(
                kind: .color,
                text: "#0071E3",
                payload: Data("0,113,227".utf8),
                plainText: "rgb(0, 113, 227)",
                copiedAt: epoch
            )
        )

        // People remember one or the other, never reliably the one you stored.
        XCTAssertEqual(history.search("0071e3").count, 1)
        XCTAssertEqual(history.search("rgb(0, 113").count, 1)
    }

    // MARK: - TC-CLP-012

    func test_TC_CLP_012_recognisedTextIsAttachedAfterwardsAndIsSearchable() throws {
        var history = ClipboardHistory()
        history.record(
            ClipboardEntry(kind: .image, text: "Image", payload: Data([0x1]), copiedAt: epoch)
        )
        let id = try XCTUnwrap(history.entries.first).id

        history.attachRecognisedText("Build failed: 3 errors", to: id)

        XCTAssertEqual(history.search("build failed").count, 1)
        XCTAssertEqual(history.entries.first?.recognisedText, "Build failed: 3 errors")
    }

    // MARK: - TC-CLP-013

    func test_TC_CLP_013_anImageWithNoTextRecordsThatFactRatherThanRetryingForever() throws {
        var history = ClipboardHistory()
        history.record(
            ClipboardEntry(kind: .image, text: "Image", payload: Data([0x1]), copiedAt: epoch)
        )
        let id = try XCTUnwrap(history.entries.first).id

        history.attachRecognisedText(nil, to: id)

        XCTAssertNil(history.entries.first?.recognisedText)
        // And it did not error, surface anything, or change the entry.
        XCTAssertEqual(history.count, 1)
    }

    func test_attachingTextToSomethingThatIsGoneIsSafe() {
        var history = ClipboardHistory()
        history.attachRecognisedText("anything", to: UUID())
        XCTAssertTrue(history.isEmpty)
    }
}
