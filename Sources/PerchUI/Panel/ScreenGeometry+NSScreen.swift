import AppKit
import PerchCore

/// Bridges `NSScreen` into the plain value `PerchCore` reasons about.
///
/// **Coordinate convention.** `ScreenGeometry.frame` is in *display* space:
/// global, but with the origin at the top-left of the primary screen and `y`
/// increasing downwards, which is how `CGDisplayBounds` and every
/// safe-area API describe the world. AppKit's global space has `y` increasing
/// upwards from the bottom of the primary screen, so the panel flips once, at
/// `NSRect.fromDisplaySpace`. Core never sees an AppKit coordinate.
public extension ScreenGeometry {

    init(screen: NSScreen) {
        let insets = screen.safeAreaInsets

        // The cutout's width is whatever the menu bar cannot use between the
        // two auxiliary areas. Reading it this way means a new Mac with a
        // different notch needs no code change (`CLAUDE.md` §9).
        var notchWidth: CGFloat = 0
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            notchWidth = max(0, screen.frame.width - left.width - right.width)
        }

        self.init(
            frame: screen.displaySpaceFrame,
            safeAreaInsets: EdgeInsets(
                top: insets.top,
                left: insets.left,
                bottom: insets.bottom,
                right: insets.right
            ),
            notchWidth: notchWidth,
            scaleFactor: screen.backingScaleFactor,
            isBuiltIn: screen.isBuiltIn
        )
    }
}

public extension NSScreen {

    /// The screen that owns the menu bar. Everything global is measured from
    /// this one, including the flip between display and AppKit space.
    static var primaryScreen: NSScreen? { screens.first }

    /// This screen's frame in display space — top-left origin, y downwards.
    var displaySpaceFrame: CGRect {
        guard let primary = Self.primaryScreen else { return frame }
        return CGRect(
            x: frame.minX,
            y: primary.frame.maxY - frame.maxY,
            width: frame.width,
            height: frame.height
        )
    }

    /// Whether this is the Mac's own display. Used to decide which screen
    /// owns the island by default, and to know whether a notch is plausible.
    var isBuiltIn: Bool {
        guard
            let number = deviceDescription[
                NSDeviceDescriptionKey("NSScreenNumber")
            ] as? NSNumber
        else {
            return false
        }
        return CGDisplayIsBuiltin(CGDirectDisplayID(number.uint32Value)) != 0
    }
}

public extension CGRect {

    /// Converts a display-space rect (top-left origin) into AppKit's global
    /// coordinates (bottom-left origin).
    ///
    /// The one place the two conventions meet. Doing this conversion anywhere
    /// else is how an island ends up at the bottom of a second display.
    static func fromDisplaySpace(_ rect: CGRect) -> CGRect {
        guard let primary = NSScreen.primaryScreen else { return rect }
        return CGRect(
            x: rect.minX,
            y: primary.frame.maxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }
}
