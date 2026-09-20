import XCTest

@testable import PerchCore

/// Covers `TEST-PLAN.md` § GEO, unit level.
///
/// The end-to-end display cases (TC-GEO-005 … 008, 010) need real hardware
/// and live in the manual release checklist. Everything derivable from
/// geometry is here, because notch bugs are the most common complaint across
/// the entire field and the hardest for us to reproduce from a bug report.
final class NotchMetricsTests: XCTestCase {

    // MARK: - TC-GEO-001

    func test_TC_GEO_001_notchedBuiltInReportsHardwareMetrics() {
        let metrics = NotchMetrics(screen: TestScreen.notched14)

        XCTAssertEqual(metrics.mode, .hardware)
        XCTAssertEqual(metrics.collapsedSize.width, 186)
        XCTAssertEqual(metrics.collapsedSize.height, 32)
        XCTAssertGreaterThan(metrics.collapsedSize.width, 0)
        XCTAssertGreaterThan(metrics.collapsedSize.height, 0)
    }

    func test_TC_GEO_001_islandIsHorizontallyCentred() {
        let screen = TestScreen.notched14
        let metrics = NotchMetrics(screen: screen)

        let leftGap = metrics.origin.x
        let rightGap = screen.frame.width - metrics.collapsedFrame.maxX

        XCTAssertEqual(leftGap, rightGap, accuracy: 1)
        XCTAssertEqual(metrics.origin.y, 0, "The island hangs from the top edge")
    }

    // MARK: - TC-GEO-002

    func test_TC_GEO_002_nonNotchedBuiltInUsesVirtualPill() {
        let metrics = NotchMetrics(screen: TestScreen.builtInNoNotch)

        XCTAssertEqual(metrics.mode, .virtual)
        XCTAssertGreaterThan(metrics.collapsedSize.width, 0)
        XCTAssertGreaterThan(metrics.collapsedSize.height, 0)
    }

    // MARK: - TC-GEO-003

    func test_TC_GEO_003_externalDisplayHasNoNotchInset() {
        let metrics = NotchMetrics(screen: TestScreen.external)

        XCTAssertEqual(metrics.mode, .virtual)
        XCTAssertEqual(TestScreen.external.safeAreaInsets.top, 0)
    }

    // MARK: - TC-GEO-004

    func test_TC_GEO_004_twoNotchSizesDifferWithNoHardcodedConstants() {
        let small = NotchMetrics(screen: TestScreen.notched14)
        let large = NotchMetrics(screen: TestScreen.notched16)

        XCTAssertNotEqual(small.collapsedSize, large.collapsedSize)
        XCTAssertEqual(small.collapsedSize.width, TestScreen.notched14.notchWidth)
        XCTAssertEqual(large.collapsedSize.width, TestScreen.notched16.notchWidth)
        XCTAssertEqual(
            small.collapsedSize.height,
            TestScreen.notched14.safeAreaInsets.top
        )
        XCTAssertEqual(
            large.collapsedSize.height,
            TestScreen.notched16.safeAreaInsets.top
        )
    }

    // MARK: - TC-GEO-009

    func test_TC_GEO_009_zeroHeightSafeAreaFallsBackRatherThanDividingByZero() {
        let zeroInset = ScreenGeometry(
            frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            safeAreaInsets: .zero,
            notchWidth: 0
        )

        let metrics = NotchMetrics(screen: zeroInset)

        XCTAssertEqual(metrics.mode, .virtual)
        XCTAssertTrue(metrics.collapsedSize.height.isFinite)
        XCTAssertGreaterThan(metrics.collapsedSize.height, 0)
    }

    func test_TC_GEO_009_implausiblySmallInsetIsNotTrustedAsANotch() {
        let metrics = NotchMetrics(screen: TestScreen.degenerate)

        XCTAssertEqual(
            metrics.mode, .virtual,
            "A 2pt top inset is not a notch; trusting it produces a sliver"
        )
    }

    // MARK: - Expansion

    func test_expandedFrameStaysWithinTheScreen() {
        let screen = TestScreen.notched14
        let metrics = NotchMetrics(screen: screen)

        let frame = metrics.expandedFrame(
            contentSize: CGSize(width: 9999, height: 9999),
            in: screen
        )

        XCTAssertLessThanOrEqual(frame.width, screen.frame.width)
        XCTAssertLessThanOrEqual(frame.height, screen.frame.height)
        XCTAssertGreaterThanOrEqual(frame.minX, 0)
    }

    func test_expandedFrameIsNeverSmallerThanTheCollapsedIsland() {
        let screen = TestScreen.notched16
        let metrics = NotchMetrics(screen: screen)

        let frame = metrics.expandedFrame(
            contentSize: CGSize(width: 10, height: 10),
            in: screen
        )

        XCTAssertGreaterThanOrEqual(frame.width, metrics.collapsedSize.width)
        XCTAssertGreaterThanOrEqual(frame.height, metrics.collapsedSize.height)
    }

    func test_expandedFrameStaysCentredOnANarrowScreen() {
        let narrow = ScreenGeometry(
            frame: CGRect(x: 0, y: 0, width: 320, height: 900),
            safeAreaInsets: .zero,
            notchWidth: 0
        )
        let metrics = NotchMetrics(screen: narrow)

        let frame = metrics.expandedFrame(
            contentSize: CGSize(width: 800, height: 120),
            in: narrow
        )

        let leftGap = frame.minX
        let rightGap = narrow.frame.width - frame.maxX

        XCTAssertEqual(leftGap, rightGap, accuracy: 1)
        XCTAssertGreaterThanOrEqual(leftGap, 0, "Must not clip off-screen")
    }
}
