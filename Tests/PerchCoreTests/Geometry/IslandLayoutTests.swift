import XCTest

@testable import PerchCore

/// Covers `TEST-PLAN.md` § GEO for the panel's own frame — TC-GEO-011 and
/// TC-GEO-012.
///
/// The panel is placed once per screen and never resized, so these two cases
/// are the whole of its correctness. Getting them wrong shows up as an island
/// hanging off the edge of a small external display, which is exactly the
/// complaint `COMPARISON.md` records against the field.
final class IslandLayoutTests: XCTestCase {

    // MARK: - TC-GEO-011

    func test_TC_GEO_011_panelNeverExceedsTheScreen() {
        let narrow = ScreenGeometry(
            frame: CGRect(x: 0, y: 0, width: 400, height: 300),
            scaleFactor: 1,
            isBuiltIn: false
        )
        let layout = IslandLayout(
            metrics: NotchMetrics(screen: narrow),
            screen: narrow
        )

        XCTAssertLessThanOrEqual(layout.panelFrame.width, narrow.frame.width)
        XCTAssertGreaterThanOrEqual(layout.panelFrame.minX, narrow.frame.minX)
        XCTAssertLessThanOrEqual(layout.panelFrame.maxX, narrow.frame.maxX)
        XCTAssertLessThanOrEqual(layout.panelFrame.height, narrow.frame.height / 2)
    }

    func test_TC_GEO_011_panelIsOffsetByTheScreensOriginInTheArrangement() {
        // A second display sitting to the right of the primary. The panel must
        // land on *that* screen, not at the same x as the primary's.
        let second = ScreenGeometry(
            frame: CGRect(x: 1512, y: 0, width: 2560, height: 1440),
            scaleFactor: 1,
            isBuiltIn: false
        )
        let layout = IslandLayout(
            metrics: NotchMetrics(screen: second),
            screen: second
        )

        XCTAssertGreaterThanOrEqual(layout.panelFrame.minX, second.frame.minX)
        XCTAssertLessThanOrEqual(layout.panelFrame.maxX, second.frame.maxX)
    }

    // MARK: - TC-GEO-012

    func test_TC_GEO_012_islandIsCentredAndFlushWithTheTopEdge() {
        let screen = TestScreen.notched16
        let layout = IslandLayout(
            metrics: NotchMetrics(screen: screen),
            screen: screen
        )

        for size in [
            CGSize(width: 0, height: 0),
            CGSize(width: 320, height: 40),
            IslandLayout.maximumContentSize
        ] {
            let frame = layout.islandFrame(contentSize: size)
            let leftGap = frame.minX
            let rightGap = layout.panelFrame.width - frame.maxX

            XCTAssertEqual(frame.minY, 0, "island must touch the screen edge")
            XCTAssertEqual(leftGap, rightGap, accuracy: 1, "island must be centred")
            XCTAssertLessThanOrEqual(frame.maxX, layout.panelFrame.width)
        }
    }

    func test_TC_GEO_012_islandNeverShrinksBelowTheNotch() {
        let screen = TestScreen.notched14
        let metrics = NotchMetrics(screen: screen)
        let layout = IslandLayout(metrics: metrics, screen: screen)

        let frame = layout.islandFrame(contentSize: .zero)

        XCTAssertEqual(frame.width, metrics.collapsedSize.width)
        XCTAssertEqual(frame.height, metrics.collapsedSize.height)
    }

    func test_TC_GEO_012_virtualPillGetsTheSameTreatment() {
        let screen = TestScreen.external
        let metrics = NotchMetrics(screen: screen)
        let layout = IslandLayout(metrics: metrics, screen: screen)

        XCTAssertEqual(metrics.mode, .virtual)
        XCTAssertEqual(layout.collapsedIslandFrame.size, metrics.collapsedSize)
        XCTAssertEqual(layout.collapsedIslandFrame.minY, 0)
    }

    // MARK: - TC-GEO-013

    func test_TC_GEO_013_theWindowHoldsTheIslandAndItsShadowCentredOnTheNotch() {
        let screen = TestScreen.notched16
        let metrics = NotchMetrics(screen: screen)
        let layout = IslandLayout(metrics: metrics, screen: screen)

        for size in [
            metrics.collapsedSize, CGSize(width: 360, height: 34), CGSize(width: 420, height: 120)
        ] {
            let window = layout.windowFrame(islandSize: size)

            XCTAssertGreaterThan(window.width, size.width, "room for the shadow beside it")
            XCTAssertGreaterThan(window.height, size.height, "room for the shadow below it")
            XCTAssertEqual(window.midX, layout.panelFrame.midX, accuracy: 1, "centred on the notch")
            XCTAssertEqual(window.minY, layout.panelFrame.minY, "flush with the top of the screen")
            XCTAssertTrue(layout.panelFrame.contains(window), "never beyond the old maximum")
        }
    }

    /// **The bug this exists for.** The resting home surface is the size of
    /// the notch, and its window must be too — not the 568 × 304 block that
    /// used to sit over the menu bar and the top of every app beside it.
    func test_TC_GEO_013_theRestingIslandLeavesTheMenuBarItsClicks() {
        let screen = TestScreen.notched14
        let metrics = NotchMetrics(screen: screen)
        let layout = IslandLayout(metrics: metrics, screen: screen)

        let resting = layout.windowFrame(islandSize: metrics.collapsedSize)

        XCTAssertLessThan(resting.width, metrics.collapsedSize.width + 40)
        XCTAssertLessThan(resting.height, metrics.collapsedSize.height + 30)
        XCTAssertLessThan(
            resting.width * resting.height,
            layout.panelFrame.width * layout.panelFrame.height * 0.1,
            "under a tenth of the old block"
        )
    }

    func test_TC_GEO_013_theLargestIslandIsClampedToThePanel() {
        let screen = TestScreen.external
        let layout = IslandLayout(metrics: NotchMetrics(screen: screen), screen: screen)

        let window = layout.windowFrame(islandSize: CGSize(width: 5_000, height: 5_000))

        XCTAssertEqual(window.size, layout.panelFrame.size)
        XCTAssertEqual(window.origin, layout.panelFrame.origin)
    }

    // MARK: - TC-ISL-022

    func test_TC_ISL_022_theIslandIsWhereTheWindowDrawsIt() {
        let screen = TestScreen.notched16
        let layout = IslandLayout(metrics: NotchMetrics(screen: screen), screen: screen)
        let size = CGSize(width: 380, height: 96)

        let island = layout.islandScreenFrame(islandSize: size)
        let window = layout.windowFrame(islandSize: size)

        XCTAssertEqual(island.size, size)
        XCTAssertEqual(island.midX, window.midX, accuracy: 1, "centred in its window")
        XCTAssertEqual(island.minY, window.minY, "both flush with the top")
        XCTAssertTrue(window.contains(island))
        XCTAssertFalse(
            island.contains(CGPoint(x: island.midX, y: island.maxY + 200)), "far below is outside")
    }
}
