import CoreGraphics
import Foundation

/// The frame the island's panel occupies, and where the island sits inside it.
///
/// The panel does **not** resize as the island expands. It is placed once per
/// screen at a size that can hold the largest expansion, and the island is
/// drawn inside it. Resizing an `NSWindow` sixty times a second is the single
/// biggest source of jitter in this category of app; animating a view inside a
/// fixed window is free.
///
/// Pure arithmetic over `NotchMetrics` and `ScreenGeometry`, so every display
/// configuration in `TEST-PLAN.md` § GEO is a unit test rather than a cable.
public struct IslandLayout: Equatable, Sendable {

    /// The largest an expanded island may ever be. Modules are laid out
    /// inside this; nothing may exceed it, because the panel is sized from
    /// it and a module that overflows would be clipped by the window rather
    /// than by the layout.
    public static let maximumContentSize = CGSize(width: 520, height: 280)

    /// Breathing room around the island inside the panel. The island casts a
    /// shadow and scales slightly on press; both need room that is inside the
    /// window, not outside it.
    private static let padding: CGFloat = 24

    public let metrics: NotchMetrics

    /// The panel's frame in screen space, origin at the screen's top-left.
    /// `PerchUI` flips this into AppKit's bottom-left coordinates.
    public let panelFrame: CGRect

    public init(metrics: NotchMetrics, screen: ScreenGeometry) {
        self.metrics = metrics

        let desiredWidth =
            max(
                Self.maximumContentSize.width,
                metrics.collapsedSize.width
            ) + (Self.padding * 2)

        // Never wider than the screen. A 1280-point external display must not
        // get a panel hanging off both edges (TC-GEO-011).
        let width = min(desiredWidth, screen.frame.width)
        let height = min(
            Self.maximumContentSize.height + Self.padding,
            screen.frame.height / 2
        )

        self.panelFrame = CGRect(
            x: (screen.frame.minX + ((screen.frame.width - width) / 2)).rounded(),
            y: screen.frame.minY,
            width: width,
            height: height
        )
    }

    /// Where the collapsed island sits inside the panel.
    public var collapsedIslandFrame: CGRect {
        islandFrame(contentSize: metrics.collapsedSize)
    }

    /// Where an island of a given content size sits inside the panel.
    ///
    /// Always centred on the notch and flush with the top edge, because the
    /// island is meant to read as the cutout growing rather than as a window
    /// appearing near it (TC-GEO-012).
    public func islandFrame(contentSize: CGSize) -> CGRect {
        let width = min(
            max(contentSize.width, metrics.collapsedSize.width),
            panelFrame.width
        )
        let height = min(
            max(contentSize.height, metrics.collapsedSize.height),
            panelFrame.height
        )

        return CGRect(
            x: ((panelFrame.width - width) / 2).rounded(),
            y: 0,
            width: width,
            height: height
        )
    }
}
