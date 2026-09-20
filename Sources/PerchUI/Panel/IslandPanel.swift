import AppKit

/// The window the island lives in.
///
/// Borderless, non-activating, above the menu bar, present on every Space and
/// over full-screen apps. **Use this, never a bare `NSWindow`**
/// (`CLAUDE.md` §9) — the behaviours below are the difference between an
/// island and a floating black rectangle that steals your focus.
public final class IslandPanel: NSPanel {

    public init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            // `.nonactivatingPanel` is the one that matters: clicking the
            // island must not deactivate the app underneath (TC-ISL-008).
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovable = false
        isMovableByWindowBackground = false

        // Above the menu bar, so the island can overlap it (`CLAUDE.md` §9).
        level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)

        // Follows the user to any Space, and keeps drawing over a full-screen
        // window rather than being hidden behind it (TC-ISL-010, TC-ISL-011).
        collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle
        ]

        backgroundColor = .clear
        isOpaque = false
        hasShadow = false

        // A menu-bar app has no windows in the Dock or the window menu.
        isExcludedFromWindowsMenu = true

        becomesKeyOnlyIfNeeded = true
    }

    /// Whether the island may currently take key focus.
    ///
    /// Almost always `false`: the island is a surface you touch, not one you
    /// focus, and typing must keep going to the app in front (TC-ISL-008).
    /// The exception is a module that genuinely needs the keyboard — the
    /// clipboard's search field is the only one — which raises this for
    /// exactly as long as its field is open and lowers it again on dismissal.
    public var allowsKeyFocus = false {
        didSet {
            guard allowsKeyFocus != oldValue else { return }
            if allowsKeyFocus {
                makeKey()
            } else if isKeyWindow {
                resignKey()
            }
        }
    }

    /// A plain `NSWindow` fails TC-ISL-008 by default; this is the override
    /// that makes it pass.
    override public var canBecomeKey: Bool { allowsKeyFocus }
    override public var canBecomeMain: Bool { false }
}
