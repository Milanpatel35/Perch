import AppKit

extension NSImage {

    /// A copy of this image drawn entirely in one colour.
    ///
    /// The menu bar gets a *template* image and lets the system tint it. The
    /// island cannot: it draws on its own black background regardless of the
    /// system appearance, so the mark has to be tinted here or it would be a
    /// black bird on a black island.
    func tinted(_ color: NSColor) -> NSImage {
        let tinted = NSImage(size: size, flipped: false) { rect in
            color.set()
            rect.fill()
            self.draw(
                in: rect,
                from: .zero,
                operation: .destinationIn,
                fraction: 1
            )
            return true
        }
        tinted.isTemplate = false
        return tinted
    }
}
