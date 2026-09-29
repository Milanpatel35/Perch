import AppKit
import PerchUI
import SwiftUI

/// The Settings window, owned directly.
///
/// **Not the SwiftUI `Settings` scene's window.** From macOS 14 the only
/// supported way to open that scene is a `SettingsLink` inside a SwiftUI
/// view, and the old `showSettingsWindow:` action is refused with a runtime
/// warning. An accessory app opening Settings from an `NSMenu` has no view
/// to put a `SettingsLink` in, so the menu item did nothing at all: no module
/// could be switched on or off. Hosting the same `PreferencesView` in a
/// window this app owns works identically on 13, 14 and 15+.
@MainActor
final class SettingsWindowController {

    private let makeContent: @MainActor () -> PreferencesView
    private var window: NSWindow?

    init(content: @escaping @MainActor () -> PreferencesView) {
        self.makeContent = content
    }

    var isVisible: Bool { window?.isVisible ?? false }

    /// Shows the window, creating it the first time. Reopening brings the
    /// same window forward rather than stacking a second one.
    func show() {
        let window = window ?? makeWindow()
        self.window = window

        // An accessory app has to come forward before its window can take
        // focus, or it opens behind whatever was in front. On macOS 14
        // activation is cooperative and `activate(ignoringOtherApps:)` is
        // routinely declined, so the window is also ordered front
        // explicitly — which is what actually put it on top in testing.
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    func close() {
        window?.close()
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = String(localized: "Perch Settings")
        window.contentViewController = NSHostingController(rootView: makeContent())
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("PerchSettings")
        if !window.setFrameUsingName("PerchSettings") {
            window.center()
        }
        return window
    }
}
