import CoreGraphics
import Foundation

/// Where the island lives on a given screen, and how big it is.
///
/// Notch size differs per model. **Never hardcode dimensions** — every value
/// here is derived from the screen's own safe-area insets (`CLAUDE.md` §9).
/// The only constants are the virtual-pill fallback, which by definition has
/// no hardware to measure.
///
/// This type is pure arithmetic over a `ScreenGeometry` value so it can be
/// unit-tested against display configurations nobody has to plug in — that is
/// most of `TEST-PLAN.md` § GEO. The AppKit layer supplies real
/// `NSScreen.safeAreaInsets`; the tests supply fixtures.
public struct NotchMetrics: Equatable, Sendable {

    public enum Mode: Equatable, Sendable {
        /// A real hardware notch, measured from the screen.
        case hardware
        /// No notch: a floating pill drawn at the top edge. Mac mini, Studio,
        /// iMac, external displays, and Intel laptops.
        case virtual
    }

    public let mode: Mode

    /// Collapsed size of the island, in points.
    public let collapsedSize: CGSize

    /// Origin of the collapsed island in the screen's coordinate space, with
    /// the origin at the top-left of the screen.
    public let origin: CGPoint

    /// Corner radius of the island's bottom corners. Matched to the hardware
    /// notch where there is one so the island reads as part of the cutout.
    public let cornerRadius: CGFloat

    public var collapsedFrame: CGRect {
        CGRect(origin: origin, size: collapsedSize)
    }

    // MARK: - Virtual fallback constants
    //
    // These are the *only* hardcoded dimensions in the type, and they apply
    // solely where there is no hardware to measure. Sized to sit comfortably
    // inside a standard 24pt menu bar.

    private static let virtualSize = CGSize(width: 180, height: 22)
    private static let virtualCornerRadius: CGFloat = 11
    private static let hardwareCornerRadius: CGFloat = 10

    /// Minimum believable hardware notch height. Anything at or below this is
    /// treated as "no notch" rather than trusted — some configurations report
    /// a tiny nonzero top inset that is not a cutout, and dividing the layout
    /// by it produces a sliver (TC-GEO-009).
    private static let minimumNotchHeight: CGFloat = 8

    /// Derives metrics for a screen.
    ///
    /// Falls back to `.virtual` whenever the safe area does not describe a
    /// usable notch — zero inset, an implausibly small one, or a screen too
    /// narrow to seat the reported width.
    public init(screen: ScreenGeometry) {
        let notchHeight = screen.safeAreaInsets.top

        guard notchHeight > Self.minimumNotchHeight,
            screen.notchWidth > 0,
            screen.notchWidth < screen.frame.width
        else {
            self.mode = .virtual
            self.collapsedSize = Self.virtualSize
            self.cornerRadius = Self.virtualCornerRadius
            self.origin = CGPoint(
                x: ((screen.frame.width - Self.virtualSize.width) / 2).rounded(),
                y: 0
            )
            return
        }

        self.mode = .hardware
        self.collapsedSize = CGSize(width: screen.notchWidth, height: notchHeight)
        self.cornerRadius = Self.hardwareCornerRadius
        self.origin = CGPoint(
            x: ((screen.frame.width - screen.notchWidth) / 2).rounded(),
            y: 0
        )
    }

    /// The expanded frame for a given content size.
    ///
    /// Stays centred on the notch, never exceeds the screen, and keeps a
    /// margin so it cannot clip on a rotated or unusually narrow display
    /// (TC-GEO-008).
    public func expandedFrame(
        contentSize: CGSize,
        in screen: ScreenGeometry
    ) -> CGRect {
        let margin: CGFloat = 12
        let maxWidth = screen.frame.width - (margin * 2)
        let width = min(max(contentSize.width, collapsedSize.width), maxWidth)
        let height = min(
            max(contentSize.height, collapsedSize.height),
            screen.frame.height / 2
        )

        return CGRect(
            x: ((screen.frame.width - width) / 2).rounded(),
            y: 0,
            width: width,
            height: height
        )
    }
}

/// The subset of a screen's geometry the island needs.
///
/// A plain value type so `PerchCore` never imports AppKit (`CLAUDE.md` §3).
/// `PerchUI` builds these from `NSScreen`; tests build them by hand.
public struct ScreenGeometry: Equatable, Sendable {

    /// Screen bounds in points.
    public let frame: CGRect

    /// Insets reported by the display. `top` is the notch height on notched
    /// built-in displays, and zero everywhere else.
    public let safeAreaInsets: EdgeInsets

    /// Width of the physical cutout, in points. Zero when there is none.
    public let notchWidth: CGFloat

    /// Backing scale. Kept so layout can round to whole pixels rather than
    /// whole points, which is what stops the island looking blurry on a
    /// non-integer scale factor (TC-GEO-007).
    public let scaleFactor: CGFloat

    /// Whether this is the Mac's built-in display.
    public let isBuiltIn: Bool

    public init(
        frame: CGRect,
        safeAreaInsets: EdgeInsets = .zero,
        notchWidth: CGFloat = 0,
        scaleFactor: CGFloat = 2,
        isBuiltIn: Bool = true
    ) {
        self.frame = frame
        self.safeAreaInsets = safeAreaInsets
        self.notchWidth = notchWidth
        self.scaleFactor = scaleFactor
        self.isBuiltIn = isBuiltIn
    }
}

/// Mirrors `NSEdgeInsets` without importing AppKit.
public struct EdgeInsets: Equatable, Sendable {
    public let top: CGFloat
    public let left: CGFloat
    public let bottom: CGFloat
    public let right: CGFloat

    public static let zero = Self(top: 0, left: 0, bottom: 0, right: 0)

    public init(top: CGFloat, left: CGFloat, bottom: CGFloat, right: CGFloat) {
        self.top = top
        self.left = left
        self.bottom = bottom
        self.right = right
    }
}
