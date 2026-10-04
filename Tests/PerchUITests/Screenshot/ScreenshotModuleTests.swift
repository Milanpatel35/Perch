import Defaults
import PerchCore
import XCTest

@testable import PerchUI

/// Covers `TEST-PLAN.md` § SCR for the parts that need the real module: what
/// a press does from permission to delivery, where the file ends up, and
/// that "off" means off.
///
/// Nothing here captures the real screen. The capture tool is a fake that
/// writes a small file — or does not, which is a cancel — and records what
/// it was asked, which is how the tests prove what was *not* captured.
@MainActor
final class ScreenshotModuleTests: XCTestCase {

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

    private func makeService(recognised: String = "") throws -> ScreenshotHarness {
        let harness = try ScreenshotHarness.make(recognised: recognised)
        folders.append(harness.folder)
        return harness
    }

    // MARK: - TC-SCR-001

    func test_TC_SCR_001_switchingOnCostsNothing() throws {
        let harness = try makeService()
        harness.service.activate()

        XCTAssertTrue(harness.capturer.calls.isEmpty)
        XCTAssertEqual(harness.permission.requests, 0)
        XCTAssertEqual(harness.permission.settingsOpened, 0)
        XCTAssertNil(harness.island.presented)

        harness.service.deactivate()
    }

    // MARK: - TC-SCR-002

    func test_TC_SCR_002_withoutPermissionItAsksOnceAndCapturesNothing() throws {
        let harness = try makeService()
        harness.permission.isGranted = false
        harness.service.activate()

        harness.service.perform(.save(.area))
        XCTAssertEqual(harness.permission.requests, 1)
        XCTAssertEqual(harness.outcome, .needsPermission)

        // The system prompt only ever shows once, so the second press goes
        // to where the switch is.
        harness.service.perform(.save(.area))
        XCTAssertEqual(harness.permission.requests, 1)
        XCTAssertEqual(harness.permission.settingsOpened, 1)

        XCTAssertTrue(harness.capturer.calls.isEmpty)
        harness.service.deactivate()
    }

    // MARK: - TC-SCR-003

    func test_TC_SCR_003_theScreenIsTheOneUnderThePointer() async throws {
        let harness = try makeService()
        harness.service.setConfiguration(ScreenshotConfiguration(destination: .folder))
        harness.service.activate()

        harness.service.perform(.save(.screen))
        await harness.settle()

        XCTAssertEqual(Array(harness.capturer.calls.first?.prefix(2) ?? []), ["-D", "2"])
        harness.service.deactivate()
    }

    func test_TC_SCR_003_textAndPinBothAskForAnArea() async throws {
        let harness = try makeService(recognised: "hello")
        harness.service.activate()

        harness.service.perform(.copyText)
        await harness.settle()
        harness.service.perform(.pin)
        await harness.settle()

        XCTAssertEqual(
            harness.capturer.calls.map { Array($0.prefix(2)) }, [["-i", "-s"], ["-i", "-s"]])
        harness.service.deactivate()
    }

    func test_TC_SCR_003_aSecondPressWhileCapturingIsIgnored() async throws {
        let harness = try makeService()
        harness.capturer.behaviour = .hold
        harness.service.activate()

        harness.service.perform(.save(.area))
        for _ in 0..<5 { await Task.yield() }
        harness.service.perform(.save(.window))
        for _ in 0..<5 { await Task.yield() }

        XCTAssertEqual(harness.capturer.calls.count, 1)
        harness.service.deactivate()
    }

    // MARK: - TC-SCR-004

    func test_TC_SCR_004_aCancelLeavesNothing() async throws {
        let harness = try makeService()
        harness.capturer.behaviour = .cancel
        harness.service.activate()

        harness.service.perform(.save(.area))
        await harness.settle()

        XCTAssertNil(harness.island.presented)
        XCTAssertTrue(harness.savedFiles.isEmpty)
        XCTAssertFalse(harness.service.isCapturing)
        harness.service.deactivate()
    }

    func test_TC_SCR_004_aFailureIsSaid() async throws {
        let harness = try makeService()
        harness.capturer.behaviour = .fail("Invalid display specified.")
        harness.service.activate()

        harness.service.perform(.save(.screen))
        await harness.settle()

        XCTAssertEqual(harness.outcome, .failed(reason: "Invalid display specified."))
        harness.service.deactivate()
    }

    // MARK: - TC-SCR-005

    func test_TC_SCR_005_withTheShelfOnItLandsInTheShelfAndNothingIsLeft() async throws {
        let harness = try makeService()
        var shelved: [URL] = []
        harness.service.onSave = { url in
            shelved.append(url)
            return true
        }
        harness.service.activate()

        harness.service.perform(.save(.area))
        await harness.settle()

        XCTAssertEqual(shelved.count, 1)
        XCTAssertTrue(harness.savedFiles.isEmpty)
        XCTAssertFalse(harness.stagedFiles.contains(try XCTUnwrap(shelved.first).lastPathComponent))
        XCTAssertNil(harness.island.presented, "the shelf announces itself")
        harness.service.deactivate()
    }

    func test_TC_SCR_005_withTheShelfOffItGoesToTheScreenshotFolder() async throws {
        let harness = try makeService()
        harness.service.onSave = { _ in false }
        harness.service.activate()

        harness.service.perform(.save(.area))
        await harness.settle()

        let saved = harness.savedFiles
        XCTAssertEqual(saved.count, 1)
        XCTAssertTrue(try XCTUnwrap(saved.first).hasPrefix("Screenshot "))
        guard case .saved(let name, _) = harness.outcome else {
            return XCTFail("expected to be told where it went")
        }
        XCTAssertEqual(name, saved.first)
        harness.service.deactivate()
    }

    func test_TC_SCR_005_theClipboardKeepsNoFile() async throws {
        let harness = try makeService()
        harness.service.setConfiguration(ScreenshotConfiguration(destination: .clipboard))
        harness.service.activate()

        harness.service.perform(.save(.window))
        await harness.settle()

        guard case .image(let url) = harness.clipboard.items.first else {
            return XCTFail("expected an image on the clipboard")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertTrue(harness.savedFiles.isEmpty)
        XCTAssertEqual(harness.outcome, .copiedImage)
        harness.service.deactivate()
    }

    // MARK: - TC-SCR-009

    func test_TC_SCR_009_textIsCopiedAndTheImageIsNotKept() async throws {
        let harness = try makeService(recognised: "error: no such module")
        harness.service.activate()

        harness.service.perform(.copyText)
        await harness.settle()

        XCTAssertEqual(harness.clipboard.items, [.text("error: no such module")])
        XCTAssertEqual(harness.outcome, .copiedText(characters: 21))
        XCTAssertTrue(harness.savedFiles.isEmpty)
        harness.service.deactivate()
    }

    func test_TC_SCR_009_noTextFoundSaysSoAndCopiesNothing() async throws {
        let harness = try makeService(recognised: "")
        harness.service.activate()

        harness.service.perform(.copyText)
        await harness.settle()

        XCTAssertTrue(harness.clipboard.items.isEmpty)
        XCTAssertEqual(harness.outcome, .noText)
        harness.service.deactivate()
    }

    // MARK: - TC-SCR-010

    func test_TC_SCR_010_aPinKeepsNothingOnDisk() async throws {
        let harness = try makeService()
        harness.service.activate()

        harness.service.perform(.pin)
        await harness.settle()

        XCTAssertEqual(harness.pins.count, 1)
        XCTAssertTrue(harness.savedFiles.isEmpty)
        XCTAssertNil(harness.island.presented, "the card is the answer")
        harness.service.deactivate()
    }

    // MARK: - TC-SCR-011

    func test_TC_SCR_011_whileOffAPressDoesNothing() throws {
        let harness = try makeService()

        harness.service.perform(.save(.area))

        XCTAssertTrue(harness.capturer.calls.isEmpty)
        XCTAssertEqual(harness.permission.requests, 0)
        XCTAssertNil(harness.island.presented)
    }

    func test_TC_SCR_011_switchingOffEndsACaptureAndClosesThePins() async throws {
        let harness = try makeService()
        harness.service.activate()
        harness.service.perform(.pin)
        await harness.settle()

        harness.capturer.behaviour = .hold
        harness.service.perform(.save(.area))
        for _ in 0..<5 { await Task.yield() }
        harness.service.deactivate()
        await harness.settle()

        XCTAssertFalse(harness.service.isActive)
        XCTAssertFalse(harness.service.isCapturing)
        XCTAssertEqual(harness.capturer.cancelled, 1)
        XCTAssertEqual(harness.pins.closed, 1)
        XCTAssertEqual(harness.pins.count, 0)
        XCTAssertNil(harness.island.presented)
    }

    func test_deactivatingTwiceIsSafe() throws {
        let harness = try makeService()
        harness.service.activate()
        harness.service.deactivate()
        harness.service.deactivate()

        XCTAssertEqual(harness.capturer.cancelled, 1)
    }

    // MARK: - TC-SCR-013

    /// The island is closed before the capture starts, so a full-screen
    /// shot never has the island in it.
    func test_TC_SCR_013_theIslandClosesBeforeTheShot() async throws {
        let harness = try makeService()
        harness.service.activate()
        // The buttons live on the home surface, so that is what is open
        // when one is pressed.
        harness.island.submit(HomeActivity(collapsedSize: CGSize(width: 186, height: 32)))
        harness.island.send(.hoverBegan)
        XCTAssertEqual(harness.island.state.presentation, .expanded(HomeActivity.identifier))

        harness.capturer.behaviour = .hold
        harness.service.perform(.save(.screen))
        for _ in 0..<5 { await Task.yield() }

        XCTAssertEqual(harness.capturer.calls.count, 1)
        XCTAssertEqual(
            harness.island.state.presentation,
            .peek(HomeActivity.identifier),
            "folded to the notch before the shot, not open over the screen"
        )
        harness.service.deactivate()
    }
}
