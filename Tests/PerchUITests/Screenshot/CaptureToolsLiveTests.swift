import CoreImage
import ImageIO
import PerchCore
import UniformTypeIdentifiers
import XCTest

@testable import PerchUI

/// Covers `TEST-PLAN.md` § SCR against the real Vision reader and the real
/// image measurer, on images made here — a generated QR code and a PNG
/// stamped at a known density. Nothing captures the screen.
@MainActor
final class CaptureToolsLiveTests: XCTestCase {

    private var directory = FileManager.default.temporaryDirectory

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("capture-tools-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func write(_ image: CGImage, dpi: Double, named name: String) throws -> URL {
        let url = directory.appendingPathComponent(name)
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        )
        CGImageDestinationAddImage(
            destination, image,
            [kCGImagePropertyDPIWidth: dpi, kCGImagePropertyDPIHeight: dpi] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return url
    }

    private func qrCode(_ payload: String) throws -> CGImage {
        let filter = try XCTUnwrap(CIFilter(name: "CIQRCodeGenerator"))
        filter.setValue(Data(payload.utf8), forKey: "inputMessage")
        let output = try XCTUnwrap(filter.outputImage)
            .transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        // A quiet zone around it, as on a real page.
        let padded = output.composited(
            over: CIImage(color: .white).cropped(to: output.extent.insetBy(dx: -48, dy: -48)))
        return try XCTUnwrap(CIContext().createCGImage(padded, from: padded.extent))
    }

    // MARK: - TC-SCR-017

    func test_TC_SCR_017_theRealReaderFindsAGeneratedCode() async throws {
        let url = try write(qrCode("https://example.com/menu"), dpi: 144, named: "qr.png")

        let codes = await ScreenshotTools.live.detectCodes(url)

        XCTAssertEqual(codes.map(\.payload), ["https://example.com/menu"])
        XCTAssertGreaterThan(codes.first?.area ?? 0, 0)
    }

    /// The CPU fallback on its own. It is what reads codes where Vision's
    /// accelerated model returns nothing — the macOS 14 CI machine — so it
    /// is tested directly rather than only when Vision happens to fail.
    func test_TC_SCR_017_theFallbackReaderFindsAGeneratedCode() throws {
        let url = try write(qrCode("WIFI:S:Home;P:secret;;"), dpi: 144, named: "qr-wifi.png")

        XCTAssertEqual(CodeReader.coreImageQR(url).map(\.payload), ["WIFI:S:Home;P:secret;;"])
        XCTAssertTrue(CodeReader.coreImageQR(directory.appendingPathComponent("none.png")).isEmpty)
    }

    func test_TC_SCR_017_theRealReaderFindsNothingInABlankArea() async throws {
        let blank = CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: 200, height: 200))
        let image = try XCTUnwrap(CIContext().createCGImage(blank, from: blank.extent))
        let url = try write(image, dpi: 144, named: "blank.png")

        let codes = await ScreenshotTools.live.detectCodes(url)

        XCTAssertTrue(codes.isEmpty)
    }

    // MARK: - TC-SCR-016

    func test_TC_SCR_016_theRealMeasurerReadsTheRecordedDensity() throws {
        let area = CIImage(color: .gray).cropped(to: CGRect(x: 0, y: 0, width: 200, height: 40))
        let image = try XCTUnwrap(CIContext().createCGImage(area, from: area.extent))

        // What `screencapture -R0,0,100,20` writes on a Retina display.
        let retina = try write(image, dpi: 144, named: "retina.png")
        XCTAssertEqual(ScreenshotTools.live.measure(retina), CGSize(width: 100, height: 20))

        // The same pixels from a 1x external display.
        let external = try write(image, dpi: 72, named: "external.png")
        XCTAssertEqual(ScreenshotTools.live.measure(external), CGSize(width: 200, height: 40))

        XCTAssertNil(ScreenshotTools.live.measure(directory.appendingPathComponent("missing.png")))
    }
}
