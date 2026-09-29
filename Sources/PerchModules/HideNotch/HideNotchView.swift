import AppKit
import PerchCore
import SwiftUI

/// The strip behind the menu bar that makes the notch disappear.
///
/// The second place in Perch allowed a window other than `IslandPanel`
/// (`CLAUDE.md` §9; the first is `CameraPinPanel`). The reason is the level:
/// the island sits *above* the menu bar, and a strip there would cover the
/// menus. This one sits one level *below* it, so the bar's own translucency
/// draws over a solid fill instead of over the wallpaper — which is the whole
/// trick. Nothing here draws over a menu, a status item or the island.
///
/// It takes no clicks, no focus and no part in Mission Control. It is not in
/// full-screen Spaces either: there the menu bar hides itself and the notch
/// is already black.
@MainActor
final class MenuBarStripPanel: NSPanel {

    private let hosting = NSHostingView(rootView: MenuBarStripView(colour: .black))

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue - 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        ignoresMouseEvents = true
        isOpaque = true
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isExcludedFromWindowsMenu = true
        backgroundColor = .black

        contentView = hosting
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// AppKit keeps windows out from under the menu bar by moving them down
    /// — and under the menu bar is the only place this window is for.
    /// Without this the strip lands one bar-height too low, black and
    /// useless, directly beneath the bar it was meant to fill.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }

    /// Places and fills the strip. `frame` is in AppKit's global space.
    ///
    /// No animation, in either direction: TC-HID-005 is "returns to normal
    /// immediately", and a fade on a bar the width of the screen reads as a
    /// flicker rather than as motion.
    func show(frame: CGRect, colour: StripColor) {
        hosting.rootView = MenuBarStripView(colour: colour)
        setFrame(frame, display: true)
        orderFrontRegardless()
    }
}

/// What the strip draws: one flat colour, edge to edge.
struct MenuBarStripView: View {

    let colour: StripColor

    var body: some View {
        Rectangle()
            .fill(Color(red: colour.red, green: colour.green, blue: colour.blue))
            .ignoresSafeArea()
            .accessibilityHidden(true)
    }
}
