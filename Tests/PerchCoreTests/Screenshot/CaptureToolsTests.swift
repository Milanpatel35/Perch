import XCTest

@testable import PerchCore

/// Covers `TEST-PLAN.md` § SCR for the capture tools' decisions: what a
/// colour is written as, how big a measured area is, and what a scanned
/// code may do.
final class CaptureToolsTests: XCTestCase {

    // MARK: - TC-SCR-014

    func test_TC_SCR_014_aColourInEveryFormat() {
        let navy = SampledColor(red: 27 / 255, green: 58 / 255, blue: 107 / 255)

        XCTAssertEqual(navy.hex, "#1B3A6B")
        XCTAssertEqual(navy.rgb, "rgb(27, 58, 107)")
        XCTAssertEqual(navy.hsl, "hsl(217, 60%, 26%)")
        XCTAssertEqual(navy.string(in: .hex), navy.hex)
    }

    func test_TC_SCR_014_primariesAndGreys() {
        XCTAssertEqual(SampledColor(red: 1, green: 0, blue: 0).hsl, "hsl(0, 100%, 50%)")
        XCTAssertEqual(SampledColor(red: 0, green: 1, blue: 0).hsl, "hsl(120, 100%, 50%)")
        XCTAssertEqual(SampledColor(red: 0, green: 0, blue: 1).hsl, "hsl(240, 100%, 50%)")
        XCTAssertEqual(SampledColor(red: 0.5, green: 0.5, blue: 0.5).hsl, "hsl(0, 0%, 50%)")
        XCTAssertEqual(SampledColor(red: 1, green: 1, blue: 1).hex, "#FFFFFF")
        XCTAssertEqual(SampledColor(red: 0, green: 0, blue: 0).hsl, "hsl(0, 0%, 0%)")
    }

    /// Display P3 colours converted to sRGB can land slightly outside 0…1.
    func test_TC_SCR_014_outOfRangeComponentsAreClamped() {
        let wide = SampledColor(red: 1.08, green: -0.02, blue: 0.5)

        XCTAssertEqual(wide.hex, "#FF0080")
        XCTAssertEqual(wide.rgb, "rgb(255, 0, 128)")
    }

    // MARK: - TC-SCR-015

    func test_TC_SCR_015_settingsFromBeforeColourFormatsStillLoad() throws {
        let saved = Data(#"{"destination":"folder","playsSound":false}"#.utf8)

        let configuration = try JSONDecoder().decode(ScreenshotConfiguration.self, from: saved)

        XCTAssertEqual(configuration.destination, .folder, "what was saved is kept")
        XCTAssertFalse(configuration.playsSound)
        XCTAssertEqual(configuration.colorFormat, .hex)
    }

    // MARK: - TC-SCR-016

    func test_TC_SCR_016_aRetinaCaptureMeasuresInPoints() {
        let size = MeasuredArea.points(pixelWidth: 2560, pixelHeight: 1440, dpi: 144)

        XCTAssertEqual(size, CGSize(width: 1280, height: 720))
        XCTAssertEqual(MeasuredArea.label(size), "1280 × 720")
    }

    func test_TC_SCR_016_aOneTimesDisplayMeasuresTheSame() {
        XCTAssertEqual(
            MeasuredArea.points(pixelWidth: 1280, pixelHeight: 720, dpi: 72),
            CGSize(width: 1280, height: 720)
        )
        XCTAssertEqual(
            MeasuredArea.points(pixelWidth: 1280, pixelHeight: 720, dpi: nil),
            CGSize(width: 1280, height: 720),
            "no density recorded means 1x, never a division by zero"
        )
        XCTAssertEqual(
            MeasuredArea.points(pixelWidth: 301, pixelHeight: 3, dpi: 144),
            CGSize(width: 151, height: 2),
            "half points round"
        )
    }

    // MARK: - TC-SCR-017

    func test_TC_SCR_017_aWebAddressIsOpened() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/menu"))

        XCTAssertEqual(
            CodeAction.decide([DetectedCode(payload: " https://example.com/menu\n", area: 0.2)]),
            .open(url)
        )
    }

    func test_TC_SCR_017_anythingElseIsCopiedNeverOpened() {
        let payloads = [
            "WIFI:S:Home;T:WPA;P:secret;;", "mailto:someone@example.com",
            "file:///etc/passwd", "javascript:alert(1)", "zoommtg://join?confno=1",
            "https://", "Just some text"
        ]
        for payload in payloads {
            XCTAssertEqual(
                CodeAction.decide([DetectedCode(payload: payload, area: 0.1)]),
                .copy(payload),
                payload
            )
        }
    }

    func test_TC_SCR_017_theLargestCodeWins() {
        let decision = CodeAction.decide([
            DetectedCode(payload: "small", area: 0.01),
            DetectedCode(payload: "big", area: 0.4),
            DetectedCode(payload: "   ", area: 0.9)
        ])

        XCTAssertEqual(decision, .copy("big"), "an empty payload never wins")
    }

    func test_TC_SCR_017_noCodeIsNoAction() {
        XCTAssertNil(CodeAction.decide([]))
        XCTAssertNil(CodeAction.decide([DetectedCode(payload: "", area: 1)]))
    }
}
