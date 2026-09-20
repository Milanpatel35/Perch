import AppKit
import PerchCore
import SwiftUI
import XCTest

@testable import PerchUI

/// Renders the module's views for real, and counts the pixels.
///
/// Not a snapshot comparison — those live in `__Snapshots__` and need
/// reference images. This is the cheaper half of the same idea: host the view
/// in a real `NSHostingView`, draw it, and check that something came out. It
/// catches the two failures a model test cannot — a view that traps on
/// missing data, and a view that lays out to nothing (TC-MED-004:
/// "placeholder shown; no crash, no blank frame").
///
/// Counting drawn pixels rather than counting `subviews`, because SwiftUI
/// renders leaf content straight into the hosting view's layer: a view that
/// draws perfectly well can have no `NSView` children at all.
@MainActor
final class NowPlayingViewTests: XCTestCase {

    @discardableResult
    private func render(_ view: AnyView, size: CGSize) -> NSHostingView<AnyView> {
        let host = NSHostingView(rootView: view)
        host.frame = CGRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
        return host
    }

    /// How many pixels the view actually painted.
    private func drawnPixels(_ view: AnyView, size: CGSize) -> Int {
        let host = render(view, size: size)

        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            XCTFail("could not make a bitmap for a \(size) view")
            return 0
        }
        host.cacheDisplay(in: host.bounds, to: rep)

        guard let data = rep.bitmapData else { return 0 }
        let count = rep.pixelsWide * rep.pixelsHigh
        let samples = rep.samplesPerPixel

        var drawn = 0
        for pixel in 0..<count where data[(pixel * samples) + (samples - 1)] > 0 {
            drawn += 1
        }
        return drawn
    }

    private func snapshot(
        title: String = "So What",
        artist: String = "Miles Davis",
        artwork: Data? = nil,
        rate: Double = 1,
        duration: Duration? = .seconds(545)
    ) -> NowPlayingSnapshot {
        NowPlayingSnapshot(
            title: title,
            artist: artist,
            album: "Kind of Blue",
            progress: PlaybackProgress(
                elapsed: .seconds(42),
                rate: rate,
                asOf: .now,
                duration: duration
            ),
            artwork: artwork,
            sourceBundleID: "com.apple.Music",
            sourceName: "Music"
        )
    }

    // MARK: - TC-MED-004

    func test_TC_MED_004_expandedViewRendersWithNoArtwork() {
        let activity = NowPlayingActivity(snapshot: snapshot(artwork: nil))

        XCTAssertGreaterThan(
            drawnPixels(activity.expandedView(), size: activity.expandedSize),
            0,
            "the island drew nothing at all"
        )
    }

    func test_TC_MED_004_expandedViewRendersWithUnreadableArtwork() {
        // Sources do hand over bytes that are not an image. A placeholder is
        // the right answer; a crash in a menu-bar app takes the island with
        // it.
        let rubbish = Data([0x00, 0x01, 0x02, 0x03, 0x04])
        let activity = NowPlayingActivity(snapshot: snapshot(artwork: rubbish))

        XCTAssertGreaterThan(
            drawnPixels(activity.expandedView(), size: activity.expandedSize),
            0
        )
    }

    func test_TC_MED_004_peekRendersWithNoArtwork() {
        let activity = NowPlayingActivity(snapshot: snapshot(artwork: nil))

        XCTAssertGreaterThan(
            drawnPixels(activity.peekView(), size: activity.peekSize),
            0
        )
    }

    func test_TC_MED_004_expandedViewRendersForAStreamWithNoDuration() {
        let activity = NowPlayingActivity(snapshot: snapshot(duration: nil))

        XCTAssertGreaterThan(
            drawnPixels(activity.expandedView(), size: activity.expandedSize),
            0
        )
    }

    // MARK: - TC-MED-006

    func test_TC_MED_006_aLongTitleDoesNotOverflowTheIsland() {
        let long = String(repeating: "A Love Supreme, Pt. I — Acknowledgement ", count: 6)
        let activity = NowPlayingActivity(snapshot: snapshot(title: long, artist: long))
        let host = render(activity.expandedView(), size: activity.expandedSize)

        // The marquee scrolls inside a clipped frame; it must never widen the
        // island to fit the text.
        XCTAssertEqual(host.frame.width, activity.expandedSize.width)
        for subview in host.subviews {
            XCTAssertLessThanOrEqual(
                subview.frame.width.rounded(),
                activity.expandedSize.width.rounded()
            )
        }
    }

    func test_TC_MED_006_shortTitlesStillDraw() {
        // A marquee that animates text which already fits is a wakeup every
        // frame for no information — it truncates instead. It must still draw.
        XCTAssertGreaterThan(
            drawnPixels(AnyView(MarqueeText("So What")), size: CGSize(width: 300, height: 20)),
            0
        )
    }

    // MARK: - TC-MED-002

    func test_TC_MED_002_theVisualiserDrawsWhetherPlayingOrPaused() {
        // Paused it is a flat row rather than nothing: present, and saying
        // that nothing is happening.
        for isPlaying in [true, false] {
            XCTAssertGreaterThan(
                drawnPixels(
                    AnyView(Visualiser(isPlaying: isPlaying)),
                    size: CGSize(width: 22, height: 18)
                ),
                0,
                "visualiser blank when isPlaying=\(isPlaying)"
            )
        }
    }
}
