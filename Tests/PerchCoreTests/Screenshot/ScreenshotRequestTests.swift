import XCTest

@testable import PerchCore

/// Covers `TEST-PLAN.md` § SCR for the parts with decisions in them: what the
/// capture tool is told, how its ending is read, what a file is called and
/// where it goes.
final class ScreenshotRequestTests: XCTestCase {

    private let file = URL(fileURLWithPath: "/tmp/Screenshot 2026-10-03 at 14.32.05.png")

    // MARK: - TC-SCR-003

    func test_TC_SCR_003_areaIsTheInteractiveSelection() {
        XCTAssertEqual(
            ScreenCaptureArguments.make(kind: .area, display: nil, output: file, playsSound: true),
            ["-i", "-s", file.path]
        )
    }

    func test_TC_SCR_003_windowIsTheInteractiveWindowPicker() {
        XCTAssertEqual(
            ScreenCaptureArguments.make(
                kind: .window, display: nil, output: file, playsSound: false),
            ["-i", "-w", "-x", file.path]
        )
    }

    func test_TC_SCR_003_screenIsTheDisplayUnderThePointer() {
        XCTAssertEqual(
            ScreenCaptureArguments.make(kind: .screen, display: 2, output: file, playsSound: true),
            ["-D", "2", file.path]
        )
        XCTAssertEqual(
            ScreenCaptureArguments.make(
                kind: .screen, display: nil, output: file, playsSound: true),
            ["-D", "1", file.path],
            "no display found means the main one, never 0"
        )
    }

    func test_TC_SCR_003_displaysAreNumberedFromTheMainOne() {
        XCTAssertEqual(ScreenCaptureArguments.displayNumber(of: 1, in: [1, 5]), 1)
        XCTAssertEqual(ScreenCaptureArguments.displayNumber(of: 5, in: [1, 5]), 2)
        XCTAssertNil(ScreenCaptureArguments.displayNumber(of: 9, in: [1, 5]), "unplugged")
    }

    /// The path is one argument however odd it is. Nothing is ever handed
    /// to a shell, so there is nothing for a name to break out of.
    func test_TC_SCR_003_anOddFileNameIsStillOneArgument() {
        let odd = URL(fileURLWithPath: "/tmp/a; rm -rf ~ $(x).png")
        let arguments = ScreenCaptureArguments.make(
            kind: .area, display: nil, output: odd, playsSound: true)

        XCTAssertEqual(arguments.last, odd.path)
        XCTAssertEqual(arguments.count, 3)
    }

    // MARK: - TC-SCR-004

    func test_TC_SCR_004_escapeIsACancelNotAFailure() {
        XCTAssertEqual(
            CaptureResult.from(exitCode: 1, producedOutput: false, error: ""), .cancelled)
        XCTAssertEqual(
            CaptureResult.from(exitCode: 0, producedOutput: false, error: ""), .cancelled)
    }

    func test_TC_SCR_004_aFailureSaysWhy() {
        XCTAssertEqual(
            CaptureResult.from(
                exitCode: 1, producedOutput: false, error: "Invalid display specified.\n"),
            .failed(reason: "Invalid display specified.")
        )
    }

    func test_TC_SCR_004_aWrittenFileIsACapture() {
        XCTAssertEqual(CaptureResult.from(exitCode: 0, producedOutput: true, error: ""), .captured)
    }

    // MARK: - TC-SCR-006

    private let home = URL(fileURLWithPath: "/Users/someone", isDirectory: true)

    func test_TC_SCR_006_aTildeLocationIsExpanded() {
        let resolved = ScreenshotLocation.resolve(
            stored: "~/Desktop/Shots", home: home, isDirectory: { _ in true })

        XCTAssertEqual(resolved.path, "/Users/someone/Desktop/Shots")
    }

    func test_TC_SCR_006_anAbsoluteLocationIsUsedAsIs() {
        let resolved = ScreenshotLocation.resolve(
            stored: "/Volumes/Work/Shots", home: home, isDirectory: { _ in true })

        XCTAssertEqual(resolved.path, "/Volumes/Work/Shots")
    }

    func test_TC_SCR_006_unsetOrGoneFallsBackToTheDesktop() {
        let desktop = "/Users/someone/Desktop"

        XCTAssertEqual(
            ScreenshotLocation.resolve(stored: nil, home: home, isDirectory: { _ in true }).path,
            desktop
        )
        XCTAssertEqual(
            ScreenshotLocation.resolve(stored: "  ", home: home, isDirectory: { _ in true }).path,
            desktop
        )
        XCTAssertEqual(
            ScreenshotLocation.resolve(
                stored: "/Volumes/Unplugged", home: home, isDirectory: { _ in false }
            ).path,
            desktop
        )
    }

    // MARK: - TC-SCR-007

    func test_TC_SCR_007_filesAreNamedTheWayMacOSNamesItsOwn() throws {
        let utc = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let date = Date(timeIntervalSince1970: 1_791_037_925)  // 2026-10-03 14:32:05 UTC

        let name = ScreenshotNaming.filename(for: date, timeZone: utc)

        XCTAssertEqual(name, "Screenshot 2026-10-03 at 14.32.05.png")
        XCTAssertFalse(name.contains(":"))
        XCTAssertFalse(name.contains("/"))
    }

    func test_TC_SCR_007_twoInTheSameSecondDoNotCollide() {
        let taken: Set = ["Screenshot 1.png", "Screenshot 1 (2).png"]

        XCTAssertEqual(
            ScreenshotNaming.unique("Screenshot 1.png", avoiding: taken.contains),
            "Screenshot 1 (3).png"
        )
        XCTAssertEqual(
            ScreenshotNaming.unique("Screenshot 2.png", avoiding: taken.contains),
            "Screenshot 2.png"
        )
    }
}
