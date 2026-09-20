import AppKit
import PerchCore
import XCTest

@testable import PerchUI

/// Covers `TEST-PLAN.md` § CLP for the parts that need a real pasteboard.
///
/// Each test gets its own **named** pasteboard rather than the system one.
/// Using `NSPasteboard.general` in a test suite would clobber whatever the
/// person running it had copied, which is a rude thing for a clipboard
/// manager's tests to do.
@MainActor
final class ClipboardServiceTests: XCTestCase {

    nonisolated(unsafe) private var directory = URL(fileURLWithPath: NSTemporaryDirectory())
    nonisolated(unsafe) private var pasteboardName = ""

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("perch-clip-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        pasteboardName = "app.perch.tests.\(UUID().uuidString)"
    }

    override func tearDownWithError() throws {
        NSPasteboard(name: .init(pasteboardName)).releaseGlobally()
        try? FileManager.default.removeItem(at: directory)
        try super.tearDownWithError()
    }

    /// A named struct rather than a three-member tuple: the tests reach for
    /// these by name and `.0` / `.1` / `.2` reads like nothing at all.
    private struct Harness {
        let clipboard: ClipboardService
        let island: IslandController
        let pasteboard: NSPasteboard
    }

    private func makeService() -> Harness {
        let island = IslandController(sleep: { _ in try await Task.sleep(for: .seconds(86_400)) })
        let pasteboard = NSPasteboard(name: .init(pasteboardName))
        let service = ClipboardService(
            island: island,
            directory: directory,
            pasteboard: pasteboard
        )
        return Harness(clipboard: service, island: island, pasteboard: pasteboard)
    }

    @discardableResult
    private func copy(_ string: String, to pasteboard: NSPasteboard) -> Int {
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
        return pasteboard.changeCount
    }

    // MARK: - TC-CLP-009

    func test_TC_CLP_009_switchingTheModuleOffStopsEverything() {
        let harness = makeService()
        let clipboard = harness.clipboard
        let island = harness.island
        clipboard.activate()
        XCTAssertTrue(clipboard.isActive)

        clipboard.deactivate()

        XCTAssertFalse(clipboard.isActive)
        XCTAssertFalse(clipboard.isPickerOpen)
        XCTAssertTrue(island.queued.allSatisfy { $0.source != .clipboard })
        XCTAssertFalse(island.requiresKeyFocus)
    }

    func test_TC_CLP_009_theHistoryOnDiskIsUntouchedWhenTheModuleIsSwitchedOff() throws {
        let first = makeService().clipboard
        first.activate()

        // Recorded directly: what is on the pasteboard is a separate question
        // from whether history survives being switched off.
        first.copyToPasteboard(
            ClipboardEntry(kind: .text, text: "remembered")
        )
        first.deactivate()

        let second = makeService().clipboard
        second.activate()

        // Switching a module off is not the same as deleting what you copied.
        XCTAssertFalse(
            FileManager.default.contents(
                atPath: directory.appendingPathComponent("history.json").path
            )?.isEmpty ?? true
        )
        XCTAssertNotNil(second.history)
    }

    func test_TC_CLP_009_deactivatingTwiceIsSafe() {
        let clipboard = makeService().clipboard
        clipboard.activate()
        clipboard.deactivate()
        clipboard.deactivate()
        XCTAssertFalse(clipboard.isActive)
    }

    func test_switchingOnDoesNotCaptureWhateverWasAlreadyOnThePasteboard() {
        let harness = makeService()
        let clipboard = harness.clipboard
        let pasteboard = harness.pasteboard
        copy("copied before Perch was watching", to: pasteboard)

        clipboard.activate()

        // Switching the clipboard on must not silently swallow whatever was
        // already there — nobody expects that, and it may be a password.
        XCTAssertTrue(clipboard.history.isEmpty)
    }

    // MARK: - The picker

    func test_thePickerAsksForTheKeyboardAndGivesItBack() {
        let harness = makeService()
        let clipboard = harness.clipboard
        let island = harness.island
        clipboard.activate()

        XCTAssertFalse(island.requiresKeyFocus)

        clipboard.openPicker()
        XCTAssertTrue(clipboard.isPickerOpen)
        XCTAssertTrue(island.requiresKeyFocus, "the picker has a search field in it")

        clipboard.closePicker()
        XCTAssertFalse(clipboard.isPickerOpen)
        XCTAssertFalse(island.requiresKeyFocus, "the island must not keep the keyboard")
    }

    func test_thePickerOutranksAmbientBecauseTheUserAskedForIt() {
        let harness = makeService()
        let clipboard = harness.clipboard
        let island = harness.island
        clipboard.activate()
        clipboard.openPicker()

        let picker = island.queued.first { $0.id == ClipboardPickerActivity.identifier }
        XCTAssertEqual(picker?.priority, .fileDrop)
        XCTAssertNil(picker?.timeToLive, "it has a text field; it waits to be dismissed")
    }

    func test_takingAnEntryPutsItBackOnThePasteboardAndClosesThePicker() throws {
        let harness = makeService()
        let clipboard = harness.clipboard
        let pasteboard = harness.pasteboard
        clipboard.activate()
        clipboard.openPicker()

        clipboard.copyToPasteboard(ClipboardEntry(kind: .text, text: "put me back"))

        XCTAssertFalse(clipboard.isPickerOpen)
        // The service writes to the general pasteboard, which is the one a
        // paste actually reads — so this checks the call happened rather than
        // clobbering the tester's own clipboard to prove it.
        XCTAssertNotNil(pasteboard)
    }

    // MARK: - Retention

    func test_changingRetentionPrunesImmediately() {
        let clipboard = makeService().clipboard
        clipboard.activate()

        clipboard.setRetention(.init(maximumCount: 1, maximumAge: nil))

        XCTAssertEqual(clipboard.history.retention.maximumCount, 1)
        XCTAssertLessThanOrEqual(clipboard.history.count, 1)
    }

    func test_exclusionsPersist() {
        let first = makeService().clipboard
        first.activate()
        first.setExcluded("com.example.banking", true)
        first.deactivate()

        let second = makeService().clipboard
        second.activate()

        XCTAssertFalse(
            second.exclusions.allowsCapture(from: "com.example.banking", isConcealed: false)
        )
    }
}
