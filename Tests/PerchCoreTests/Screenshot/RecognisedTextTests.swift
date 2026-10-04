import XCTest

@testable import PerchCore

/// Covers `TEST-PLAN.md` § SCR for turning Vision's lines back into text.
/// Boxes are in Vision's space: 0…1, origin bottom left.
final class RecognisedTextTests: XCTestCase {

    private func line(
        _ text: String,
        x: CGFloat = 0.1,
        top: CGFloat,
        height: CGFloat = 0.04,
        confidence: Float = 0.9
    ) -> RecognisedLine {
        RecognisedLine(
            text: text,
            boundingBox: CGRect(x: x, y: top - height, width: 0.3, height: height),
            confidence: confidence
        )
    }

    // MARK: - TC-SCR-008

    func test_TC_SCR_008_linesReadTopToBottomWhateverOrderTheyArrive() {
        let text = RecognisedText.assemble([
            line("third", top: 0.70),
            line("first", top: 0.90),
            line("second", top: 0.80)
        ])

        XCTAssertEqual(text, "first\nsecond\nthird")
    }

    func test_TC_SCR_008_aRowReadsLeftToRight() {
        let text = RecognisedText.assemble([
            line("value", x: 0.6, top: 0.905),
            line("label", x: 0.1, top: 0.90)
        ])

        XCTAssertEqual(text, "label\nvalue")
    }

    func test_TC_SCR_008_aWideGapIsAParagraph() {
        let text = RecognisedText.assemble([
            line("one", top: 0.90),
            line("two", top: 0.84),
            line("three", top: 0.78),
            line("after the break", top: 0.60),
            line("last", top: 0.54)
        ])

        XCTAssertEqual(text, "one\ntwo\nthree\n\nafter the break\nlast")
    }

    func test_TC_SCR_008_noiseAndBlanksAreDropped() {
        let text = RecognisedText.assemble([
            line("real", top: 0.90),
            line("#~", top: 0.80, confidence: 0.1),
            line("   ", top: 0.70)
        ])

        XCTAssertEqual(text, "real")
    }

    func test_TC_SCR_008_nothingRecognisedIsEmpty() {
        XCTAssertEqual(RecognisedText.assemble([]), "")
        XCTAssertEqual(RecognisedText.assemble([line("x", top: 0.5, confidence: 0)]), "")
    }

    func test_medianIsNotPulledByOneBigGap() {
        XCTAssertEqual(RecognisedText.median([0.02, 0.02, 0.5]), 0.02)
        XCTAssertEqual(RecognisedText.median([0.02, 0.04]), 0.03, accuracy: 0.0001)
        XCTAssertEqual(RecognisedText.median([]), 0)
    }
}
