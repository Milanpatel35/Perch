import Defaults
import PerchCore
import XCTest

@testable import PerchUI

/// Covers `TEST-PLAN.md` § SCR for the capture tools inside the real module:
/// what lands on the clipboard and the island, what is opened, and that no
/// capture is kept.
@MainActor
final class CaptureToolsModuleTests: XCTestCase {

    private var savedConfiguration = ScreenshotConfiguration()
    private var savedAsked = false
    private var folders: [URL] = []

    override func setUp() async throws {
        savedConfiguration = Defaults[.screenshotConfiguration]
        savedAsked = Defaults[.screenshotAskedForPermission]
        Defaults[.screenshotConfiguration] = ScreenshotConfiguration()
        Defaults[.screenshotAskedForPermission] = false
    }

    override func tearDown() async throws {
        Defaults[.screenshotConfiguration] = savedConfiguration
        Defaults[.screenshotAskedForPermission] = savedAsked
        for folder in folders {
            try? FileManager.default.removeItem(at: folder)
        }
    }

    private func makeService(codes: [DetectedCode] = []) throws -> ScreenshotHarness {
        let harness = try ScreenshotHarness.make(recognised: "")
        harness.tools.codes = codes
        folders.append(harness.folder)
        return harness
    }

    private let navy = SampledColor(red: 27 / 255, green: 58 / 255, blue: 107 / 255)

    // MARK: - TC-SCR-015

    func test_TC_SCR_015_aPickedColourIsCopiedInTheChosenFormat() throws {
        let harness = try makeService()
        harness.service.activate()
        harness.service.setConfiguration(ScreenshotConfiguration(colorFormat: .rgb))
        harness.tools.picked = navy

        harness.service.pickColor()

        XCTAssertEqual(harness.clipboard.items, [.text("rgb(27, 58, 107)")])
        XCTAssertEqual(harness.outcome, .copiedColor(text: "rgb(27, 58, 107)", color: navy))
        harness.service.deactivate()
    }

    func test_TC_SCR_015_noScreenRecordingIsNeeded() throws {
        let harness = try makeService()
        harness.permission.isGranted = false
        harness.service.activate()
        harness.tools.picked = navy

        harness.service.pickColor()

        XCTAssertEqual(harness.clipboard.items, [.text("#1B3A6B")])
        XCTAssertEqual(harness.permission.requests, 0, "never asked")
        XCTAssertTrue(harness.capturer.calls.isEmpty, "no capture taken")
        harness.service.deactivate()
    }

    func test_TC_SCR_015_escapeCopiesAndSaysNothing() throws {
        let harness = try makeService()
        harness.service.activate()
        harness.tools.picked = nil

        harness.service.pickColor()

        XCTAssertEqual(harness.tools.loupesShown, 1)
        XCTAssertTrue(harness.clipboard.items.isEmpty)
        XCTAssertNil(harness.outcome)
        harness.service.deactivate()
    }

    func test_TC_SCR_015_offMeansNoLoupe() throws {
        let harness = try makeService()
        harness.service.pickColor()
        XCTAssertEqual(harness.tools.loupesShown, 0)
    }

    // MARK: - TC-SCR-016

    func test_TC_SCR_016_anAreaIsMeasuredAndNotKept() async throws {
        let harness = try makeService()
        harness.service.activate()

        harness.service.perform(.measure)
        await harness.settle()

        XCTAssertEqual(Array(harness.capturer.calls.first?.prefix(2) ?? []), ["-i", "-s"])
        XCTAssertEqual(harness.clipboard.items, [.text("1280 × 720")])
        XCTAssertEqual(harness.outcome, .measured("1280 × 720"))
        XCTAssertTrue(harness.savedFiles.isEmpty)
        XCTAssertTrue(harness.stagedFiles.isEmpty, "the capture is deleted once read")
        harness.service.deactivate()
    }

    func test_TC_SCR_016_escapeMeasuresNothing() async throws {
        let harness = try makeService()
        harness.capturer.behaviour = .cancel
        harness.service.activate()

        harness.service.perform(.measure)
        await harness.settle()

        XCTAssertTrue(harness.clipboard.items.isEmpty)
        XCTAssertNil(harness.outcome)
        harness.service.deactivate()
    }

    // MARK: - TC-SCR-017

    func test_TC_SCR_017_aWebAddressIsOpenedAndTheCaptureDeleted() async throws {
        let harness = try makeService(codes: [
            DetectedCode(payload: "https://example.com/menu", area: 0.3)
        ])
        let service = harness.service
        service.activate()

        service.perform(.scanCode)
        await harness.settle()

        XCTAssertEqual(harness.tools.opened.map(\.absoluteString), ["https://example.com/menu"])
        XCTAssertTrue(harness.clipboard.items.isEmpty)
        XCTAssertEqual(harness.outcome, .openedLink(host: "example.com"))
        XCTAssertTrue(harness.stagedFiles.isEmpty)
        service.deactivate()
    }

    func test_TC_SCR_017_anythingElseIsCopiedNotOpened() async throws {
        let harness = try makeService(codes: [
            DetectedCode(payload: "WIFI:S:Home;P:secret;;", area: 0.3)
        ])
        let service = harness.service
        service.activate()

        service.perform(.scanCode)
        await harness.settle()

        XCTAssertTrue(harness.tools.opened.isEmpty)
        XCTAssertEqual(harness.clipboard.items, [.text("WIFI:S:Home;P:secret;;")])
        XCTAssertEqual(harness.outcome, .copiedCode)
        service.deactivate()
    }

    func test_TC_SCR_017_noCodeSaysSo() async throws {
        let harness = try makeService()
        harness.service.activate()

        harness.service.perform(.scanCode)
        await harness.settle()

        XCTAssertEqual(harness.outcome, .noCode)
        XCTAssertTrue(harness.tools.opened.isEmpty)
        XCTAssertTrue(harness.clipboard.items.isEmpty)
        harness.service.deactivate()
    }
}
