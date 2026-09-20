import AppKit
import PerchCore
import XCTest

@testable import PerchUI

/// Reads a real `NSPasteboard` — a private, named one, so running the tests
/// never clobbers whatever the person running them had copied.
///
/// TC-CLP-007 is the important one here and it is worth stating plainly: if
/// this test ever goes red, Perch is recording passwords.
@MainActor
final class PasteboardReaderTests: XCTestCase {

    // `name` is taken: XCTestCase already has one.
    nonisolated(unsafe) private var boardName = ""
    private var pasteboard: NSPasteboard { NSPasteboard(name: .init(boardName)) }

    override func setUpWithError() throws {
        try super.setUpWithError()
        boardName = "app.perch.tests.reader.\(UUID().uuidString)"
    }

    override func tearDownWithError() throws {
        // Built inline rather than through the `pasteboard` property:
        // teardown is not main-actor isolated on every toolchain, and the
        // property is.
        NSPasteboard(name: .init(boardName)).releaseGlobally()
        try super.tearDownWithError()
    }

    // MARK: - TC-CLP-007

    func test_TC_CLP_007_aConcealedPasteboardIsNeverRead() {
        let board = pasteboard
        board.clearContents()
        board.setString("hunter2-must-never-be-recorded", forType: .string)
        // Exactly what a password manager does.
        board.setData(Data(), forType: .init("org.nspasteboard.ConcealedType"))

        XCTAssertTrue(PasteboardReader.isConcealed(board))
        XCTAssertNil(
            PasteboardReader.entry(from: board, sourceBundleID: "com.example.vault"),
            "if this fails, Perch is recording passwords"
        )
    }

    func test_TC_CLP_007_aTransientPasteboardIsAlsoIgnored() {
        let board = pasteboard
        board.clearContents()
        board.setString("temporary", forType: .string)
        board.setData(Data(), forType: .init("org.nspasteboard.TransientType"))

        XCTAssertNil(PasteboardReader.entry(from: board, sourceBundleID: nil))
    }

    // MARK: - TC-CLP-001

    func test_TC_CLP_001_plainTextIsRead() throws {
        let board = pasteboard
        board.clearContents()
        board.setString("the quick brown fox", forType: .string)

        let entry = try XCTUnwrap(
            PasteboardReader.entry(from: board, sourceBundleID: "com.apple.Safari")
        )
        XCTAssertEqual(entry.kind, .text)
        XCTAssertEqual(entry.text, "the quick brown fox")
        XCTAssertEqual(entry.sourceBundleID, "com.apple.Safari")
    }

    func test_TC_CLP_001_whitespaceOnlyIsNotWorthRecording() {
        let board = pasteboard
        board.clearContents()
        board.setString("   \n\t  ", forType: .string)

        XCTAssertNil(PasteboardReader.entry(from: board, sourceBundleID: nil))
    }

    func test_TC_CLP_001_anEmptyPasteboardYieldsNothing() {
        let board = pasteboard
        board.clearContents()

        XCTAssertNil(PasteboardReader.entry(from: board, sourceBundleID: nil))
    }

    // MARK: - TC-CLP-003

    func test_TC_CLP_003_anImageIsStoredWithItsBytes() throws {
        let image = NSImage(size: NSSize(width: 8, height: 8))
        image.lockFocus()
        NSColor.systemBlue.drawSwatch(in: NSRect(x: 0, y: 0, width: 8, height: 8))
        image.unlockFocus()

        let board = pasteboard
        board.clearContents()
        board.writeObjects([image])

        let entry = try XCTUnwrap(PasteboardReader.entry(from: board, sourceBundleID: nil))
        XCTAssertEqual(entry.kind, .image)
        XCTAssertNotNil(entry.payload)
        XCTAssertNil(entry.recognisedText, "OCR happens afterwards, not here")
    }

    // MARK: - TC-CLP-011

    func test_TC_CLP_011_aColourIsStoredAsAColourNotAsItsName() throws {
        let board = pasteboard
        board.clearContents()
        board.writeObjects([
            NSColor(srgbRed: 0, green: 113 / 255, blue: 227 / 255, alpha: 1)
        ])

        let entry = try XCTUnwrap(PasteboardReader.entry(from: board, sourceBundleID: nil))
        XCTAssertEqual(entry.kind, .color)
        XCTAssertEqual(entry.text, "#0071E3")
        XCTAssertEqual(entry.plainText, "rgb(0, 113, 227)")
    }

    // MARK: - TC-CLP-015

    func test_TC_CLP_015_richTextKeepsAPlainTextVersionForOptionPaste() throws {
        let attributed = NSAttributedString(
            string: "formatted",
            attributes: [.font: NSFont.boldSystemFont(ofSize: 14)]
        )
        let rtf = try XCTUnwrap(
            attributed.rtf(
                from: NSRange(location: 0, length: attributed.length),
                documentAttributes: [:]
            )
        )

        let board = pasteboard
        board.clearContents()
        board.setData(rtf, forType: .rtf)
        board.setString("formatted", forType: .string)

        let entry = try XCTUnwrap(PasteboardReader.entry(from: board, sourceBundleID: nil))
        XCTAssertEqual(entry.kind, .richText)
        XCTAssertNotNil(entry.payload, "the formatting is kept")
        XCTAssertEqual(entry.plainText, "formatted", "and so is a plain version")
    }

    // MARK: - Ordering

    func test_aCopiedFileIsAFileNotAStringOfItsPath() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("perch-test-file.txt")
        try Data("x".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let board = pasteboard
        board.clearContents()
        // Finder puts both on the pasteboard. Reading the string first would
        // flatten every copied file into text.
        board.writeObjects([url as NSURL])
        board.setString(url.path, forType: .string)

        let entry = try XCTUnwrap(PasteboardReader.entry(from: board, sourceBundleID: nil))
        XCTAssertEqual(entry.kind, .fileURL)
    }
}
