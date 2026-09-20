import AppKit
import PerchCore
import SwiftUI
import XCTest

@testable import PerchUI

/// The shelf's views, rendered for real and checked by drawn pixels.
///
/// Same approach as the Now Playing view tests, and for the same reason:
/// SwiftUI renders leaf content straight into the hosting view's layer, so
/// counting `subviews` proves nothing.
@MainActor
final class ShelfViewTests: XCTestCase {

    /// The island always hands its views a `ModuleHost`; a test that renders
    /// one in isolation has to do the same, or SwiftUI trips over the missing
    /// environment object while evaluating the body.
    private func hosted(_ view: AnyView) -> AnyView {
        let island = IslandController(sleep: { _ in try await Task.sleep(for: .seconds(86_400)) })
        let modules = ModuleHost(switchboard: ModuleSwitchboard(), island: island)
        return AnyView(view.environmentObject(modules))
    }

    private func drawnPixels(_ view: AnyView, size: CGSize) -> Int {
        let host = NSHostingView(rootView: hosted(view))
        host.frame = CGRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()

        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            XCTFail("could not make a bitmap for a \(size) view")
            return 0
        }
        host.cacheDisplay(in: host.bounds, to: rep)

        guard let data = rep.bitmapData else { return 0 }
        let samples = rep.samplesPerPixel
        var drawn = 0
        for pixel in 0..<(rep.pixelsWide * rep.pixelsHigh)
        where data[(pixel * samples) + (samples - 1)] > 0 {
            drawn += 1
        }
        return drawn
    }

    private func item(
        _ name: String,
        kind: ShelfItem.Kind = .file,
        available: Bool = true
    ) -> ShelfItem {
        ShelfItem(
            kind: kind,
            name: name,
            storedPath: "/tmp/\(name)",
            originalPath: "/Users/someone/\(name)",
            byteCount: 2_400_000,
            isAvailable: available
        )
    }

    // MARK: - TC-SHF-001

    func test_TC_SHF_001_theDropTargetDraws() {
        let activity = ShelfActivity(items: [], isDropTarget: true)

        XCTAssertGreaterThan(
            drawnPixels(activity.expandedView(), size: activity.expandedSize),
            0,
            "a drop target nobody can see is not a drop target"
        )
        XCTAssertEqual(activity.priority, .fileDrop)
    }

    func test_TC_SHF_001_theDropTargetOutranksWhateverIsOnTheIsland() {
        // The pointer is held down and the person is looking for somewhere to
        // let go. That beats a track change.
        XCTAssertGreaterThan(
            ShelfActivity(items: [], isDropTarget: true).priority,
            ActivityPriority.nowPlaying
        )
    }

    // MARK: - TC-SHF-003

    func test_TC_SHF_003_fiftyItemsStillLayOutInsideTheIsland() {
        let items = (0..<50).map { item("file-\($0).txt") }
        let activity = ShelfActivity(items: items)

        // The list scrolls; the island must not grow to fit fifty rows.
        XCTAssertLessThanOrEqual(
            activity.expandedSize.height,
            IslandLayout.maximumContentSize.height
        )
        XCTAssertGreaterThan(
            drawnPixels(activity.expandedView(), size: activity.expandedSize),
            0
        )
    }

    // MARK: - TC-SHF-005

    func test_TC_SHF_005_anUnavailableItemStillDrawsItsRow() {
        let activity = ShelfActivity(items: [item("gone.txt", available: false)])

        XCTAssertGreaterThan(
            drawnPixels(activity.expandedView(), size: activity.expandedSize),
            0,
            "a missing file should grey out, not disappear"
        )
    }

    // MARK: - The peek

    func test_theBadgeDrawsWhateverIsOnTheShelf() {
        for count in [1, 9, 64] {
            let activity = ShelfActivity(items: (0..<count).map { item("f\($0)") })
            XCTAssertGreaterThan(
                drawnPixels(activity.peekView(), size: activity.peekSize),
                0,
                "peek blank with \(count) items"
            )
        }
    }

    func test_everyKindOfItemRendersWithoutTrapping() {
        for kind in [ShelfItem.Kind.file, .folder, .text, .image] {
            let activity = ShelfActivity(items: [item("thing", kind: kind)])
            XCTAssertGreaterThan(
                drawnPixels(activity.expandedView(), size: activity.expandedSize),
                0,
                "\(kind) drew nothing"
            )
        }
    }

    func test_anEmptyShelfSaysSoRatherThanDrawingABlankBox() {
        let activity = ShelfActivity(items: [])

        XCTAssertGreaterThan(
            drawnPixels(activity.expandedView(), size: activity.expandedSize),
            0
        )
    }
}
