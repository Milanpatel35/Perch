import CoreGraphics
import Foundation

/// What hide-the-notch mode is set to.
///
/// TopNotch's whole product, as one value (`docs/FEATURES.md` §17). Everything
/// here is a setting rather than a behaviour, so the module that acts on it
/// has as little to decide as possible.
public struct HideNotchConfiguration: Equatable, Sendable, Codable {

    /// What the strip behind the menu bar is filled with.
    public enum Fill: String, Equatable, Sendable, Codable, CaseIterable {
        /// Solid black. The notch disappears into the bar.
        case black

        /// A solid colour taken from the top edge of the wallpaper. The bar
        /// stops changing tint as windows move, without going black.
        case wallpaper

        public var displayName: String {
            switch self {
            case .black: String(localized: "Black")
            case .wallpaper: String(localized: "Match the wallpaper")
            }
        }
    }

    /// Whether the strip is drawn at all.
    public var isBlackoutEnabled = true

    public var fill: Fill = .black

    /// Per-display choices, by display UUID. A display with no entry follows
    /// the default in `showsStrip(on:hasNotch:)`.
    ///
    /// Keyed by UUID rather than `CGDirectDisplayID` because the latter is
    /// reassigned when a display is unplugged and plugged back in, and a
    /// setting that forgets itself on a dock reconnect is not a setting.
    public var displayChoices: [String: Bool] = [:]

    /// The island draws nothing while idle and appears only for an activity.
    public var isInvisibleWhenIdle = false

    public init() {}

    /// Whether a given display gets a strip (TC-HID-003).
    ///
    /// The default is "only if it has a notch": blacking out the menu bar on
    /// an external display hides nothing, and doing it unasked would look
    /// like a bug.
    public func showsStrip(on display: String, hasNotch: Bool) -> Bool {
        guard isBlackoutEnabled else { return false }
        return displayChoices[display] ?? hasNotch
    }
}

/// Where the strip behind the menu bar goes.
///
/// Pure geometry over `ScreenGeometry`, so every display arrangement is a
/// unit test rather than something to plug in (`CLAUDE.md` §5.4).
public enum MenuBarStrip {

    /// The strip's frame in display space, or `nil` when there is nothing to
    /// cover.
    ///
    /// The height is the taller of the notch and the menu bar. They are the
    /// same on every notched Mac shipped so far, but a strip that stops a
    /// pixel short of either leaves a hairline, and that hairline is the
    /// whole thing this mode exists to remove.
    ///
    /// `menuBarHeight` is zero when the menu bar is set to hide itself —
    /// and then so is the answer for a screen without a notch, because there
    /// is no bar to fill.
    public static func frame(on screen: ScreenGeometry, menuBarHeight: CGFloat) -> CGRect? {
        let height = max(screen.safeAreaInsets.top, menuBarHeight)
        guard height > 0, screen.frame.width > 0 else { return nil }

        // Rounded up to whole pixels: a fractional edge is drawn
        // anti-aliased, which is a grey line under a black bar.
        let scale = max(screen.scaleFactor, 1)
        let pixelHeight = (height * scale).rounded(.up) / scale

        return CGRect(
            x: screen.frame.minX,
            y: screen.frame.minY,
            width: screen.frame.width,
            height: pixelHeight
        )
    }
}

/// An opaque colour, without importing AppKit or SwiftUI (`CLAUDE.md` §3).
public struct StripColor: Equatable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double

    public static let black = Self(red: 0, green: 0, blue: 0)

    public init(red: Double, green: Double, blue: Double) {
        self.red = min(max(red, 0), 1)
        self.green = min(max(green, 0), 1)
        self.blue = min(max(blue, 0), 1)
    }

    /// Relative luminance, 0–1. Used to say whether menu-bar text will be
    /// readable on the strip.
    public var luminance: Double {
        0.2126 * red + 0.7152 * green + 0.0722 * blue
    }
}

/// The colour along the top edge of a wallpaper.
public enum WallpaperEdge {

    /// Averages the top `rows` of an RGBA8 bitmap.
    ///
    /// The *top edge*, not the whole image: the strip sits against the top
    /// of the wallpaper, and a sky-over-sand photo averaged whole is beige,
    /// which matches neither. Rows past the end of the image are ignored, so
    /// a tiny thumbnail cannot read out of bounds.
    ///
    /// Returns `nil` for an empty or malformed buffer — the module falls back
    /// to black rather than inventing a colour.
    public static func averageColor(
        rgba: [UInt8],
        width: Int,
        height: Int,
        rows: Int
    ) -> StripColor? {
        guard width > 0, height > 0, rows > 0,
            rgba.count >= width * height * 4
        else { return nil }

        let sampledRows = min(rows, height)
        var red = 0.0
        var green = 0.0
        var blue = 0.0

        for row in 0..<sampledRows {
            for column in 0..<width {
                let offset = (row * width + column) * 4
                red += Double(rgba[offset])
                green += Double(rgba[offset + 1])
                blue += Double(rgba[offset + 2])
            }
        }

        let count = Double(sampledRows * width) * 255
        return StripColor(red: red / count, green: green / count, blue: blue / count)
    }
}

/// Whether the island draws anything, given what it is presenting.
///
/// The "invisible until something happens" mode from `docs/FEATURES.md` §17.
/// A rule, so it lives here and is tested, rather than as an `if` in a view.
public enum IdleVisibility {

    /// `showsHome` is whether the presented activity is the island's own home
    /// surface — which is what "idle" looks like with every module off but
    /// the island still there.
    ///
    /// Only the *collapsed* home is hidden. Hovering the notch still opens
    /// it, because an island that cannot be reached is not invisible, it is
    /// gone.
    public static func isDrawn(
        _ presentation: IslandPresentation,
        showsHome: Bool,
        invisibleWhenIdle: Bool
    ) -> Bool {
        guard invisibleWhenIdle else { return true }

        switch presentation {
        case .idle: return false
        case .peek: return !showsHome
        case .expanded: return true
        }
    }
}
