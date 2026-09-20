import AppKit
import PerchCore
import SwiftUI
import XCTest

@testable import PerchUI

/// Renders the real island, for the website's feature shots and as the
/// groundwork for the snapshot cases in `docs/TEST-PLAN.md`.
///
/// These are **not** mockups. Each image is `IslandRootView` — the same view
/// the panel hosts — driven by a real `IslandController` holding a real
/// module activity. If the island changes, the pictures change, because
/// there is nothing else for them to be.
///
/// Capturing is opt-in: set `PERCH_CAPTURE_DIR` and the images are written
/// there. Without it the tests still run and still assert the island drew
/// something, which is worth having on every CI run.
@MainActor
final class IslandSnapshots: XCTestCase {

    /// A 14" MacBook Pro. Real safe-area insets, so the notch in the picture
    /// is the size of an actual notch.
    private var layout: IslandLayout {
        let screen = ScreenGeometry(
            frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            safeAreaInsets: EdgeInsets(top: 32, left: 0, bottom: 0, right: 0),
            notchWidth: 186,
            scaleFactor: 2,
            isBuiltIn: true
        )
        return IslandLayout(metrics: NotchMetrics(screen: screen), screen: screen)
    }

    private var captureDirectory: URL? {
        ProcessInfo.processInfo.environment["PERCH_CAPTURE_DIR"]
            .map { URL(fileURLWithPath: $0) }
    }

    // MARK: - The shots

    func test_capturesTheModulesAsTheIslandActuallyDrawsThem() throws {
        let shots: [(name: String, activity: any IslandActivity)] = [
            ("now-playing", NowPlayingActivity(snapshot: .demo)),
            ("shelf", ShelfActivity(items: .demo)),
            ("shelf-drop", ShelfActivity(items: .demo, isDropTarget: true)),
            ("clipboard", ClipboardPickerActivity(entries: .demo)),
            ("home", HomeActivity(collapsedSize: layout.metrics.collapsedSize))
        ]

        for shot in shots {
            let image = try XCTUnwrap(
                render(shot.activity, expanded: true),
                "\(shot.name) rendered nothing"
            )
            XCTAssertGreaterThan(image.drawnPixels, 0, "\(shot.name) is blank")
            try write(image, named: "island-\(shot.name)")
        }
    }

    func test_capturesThePeekPresentations() throws {
        let shots: [(name: String, activity: any IslandActivity)] = [
            ("now-playing", NowPlayingActivity(snapshot: .demo)),
            ("shelf", ShelfActivity(items: .demo))
        ]

        for shot in shots {
            let image = try XCTUnwrap(render(shot.activity, expanded: false))
            XCTAssertGreaterThan(image.drawnPixels, 0, "\(shot.name) peek is blank")
            try write(image, named: "peek-\(shot.name)")
        }
    }

    // MARK: - Rendering

    /// Hosts `IslandRootView` in an offscreen window and draws it at 2x on a
    /// transparent background.
    ///
    /// The window is not optional. Rendering a hosting view's layer directly
    /// gives an upside-down image — Core Graphics counts from the bottom —
    /// and, worse, it silently omits anything SwiftUI has not been asked to
    /// lay out, which for the shelf and the clipboard is every row. With a
    /// real backing store the view lays out and `cacheDisplay` draws all of
    /// it, the right way up.
    ///
    /// The 2x comes from the backing store, not from scaling the content.
    /// `bitmapImageRepForCachingDisplay` follows the display's scale, so on a
    /// retina Mac this is already a true 2x capture with the type drawn at
    /// its real point size. Scaling the view on top of that made it 4x and
    /// drew the text twice as large as it renders, which is a picture of a
    /// different UI.
    private func render(
        _ activity: any IslandActivity,
        expanded: Bool
    ) -> NSBitmapImageRep? {
        let island = IslandController(sleep: { _ in try await Task.sleep(for: .seconds(86_400)) })
        let modules = ModuleHost(switchboard: ModuleSwitchboard(), island: island)

        island.submit(activity)
        if expanded { island.send(.clicked) }

        let size = layout.panelFrame.size

        let root = IslandRootView(
            controller: island,
            motion: MotionPreferences(),
            modules: modules,
            layout: layout
        )

        let host = NSHostingView(rootView: root)
        host.frame = CGRect(origin: .zero, size: size)

        let window = NSWindow(
            contentRect: host.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.backgroundColor = .clear
        window.isOpaque = false
        window.contentView = host

        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()

        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            return nil
        }
        host.cacheDisplay(in: host.bounds, to: rep)
        return rep
    }

    private func write(_ rep: NSBitmapImageRep, named name: String) throws {
        guard let directory = captureDirectory else { return }
        let rep = rep.trimmedToDrawnContent(margin: 24) ?? rep
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let data = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        try data.write(to: directory.appendingPathComponent("\(name).png"))
    }
}

extension NSBitmapImageRep {

    /// Crops away the transparent panel around the island.
    ///
    /// The panel is sized to hold the largest possible expansion, so most of
    /// what gets drawn is empty space. Publishing that would put a 568x304
    /// image on the page to show a 420x196 island.
    func trimmedToDrawnContent(margin: Int) -> NSBitmapImageRep? {
        guard let data = bitmapData else { return nil }
        let samples = samplesPerPixel

        var minX = pixelsWide
        var minY = pixelsHigh
        var maxX = -1
        var maxY = -1

        for y in 0..<pixelsHigh {
            for x in 0..<pixelsWide {
                let alpha = data[((y * pixelsWide) + x) * samples + (samples - 1)]
                guard alpha > 8 else { continue }
                minX = Swift.min(minX, x)
                minY = Swift.min(minY, y)
                maxX = Swift.max(maxX, x)
                maxY = Swift.max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }

        let rect = NSRect(
            x: Swift.max(0, minX - margin),
            y: Swift.max(0, minY - margin),
            width: Swift.min(pixelsWide, maxX + margin) - Swift.max(0, minX - margin),
            height: Swift.min(pixelsHigh, maxY + margin) - Swift.max(0, minY - margin)
        )

        guard let cropped = cgImage?.cropping(to: rect) else { return nil }
        return NSBitmapImageRep(cgImage: cropped)
    }

    /// How many pixels were actually painted. A blank island is a bug, not a
    /// picture.
    fileprivate var drawnPixels: Int {
        guard let data = bitmapData else { return 0 }
        let samples = samplesPerPixel
        var drawn = 0
        for pixel in 0..<(pixelsWide * pixelsHigh)
        where data[(pixel * samples) + (samples - 1)] > 0 {
            drawn += 1
        }
        return drawn
    }
}
