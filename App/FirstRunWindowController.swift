import AppKit
import Defaults
import PerchUI
import SwiftUI

/// The first-run window. Shown once, at the first launch that has not seen
/// it, and never again — closing it counts as seeing it.
///
/// Owned directly for the same reason as `SettingsWindowController`: an
/// accessory app has no SwiftUI scene that can open a window on macOS 14+.
@MainActor
final class FirstRunWindowController: NSObject, NSWindowDelegate {

    private let makeContent: @MainActor (_ done: @escaping () -> Void) -> FirstRunView
    private var window: NSWindow?

    init(content: @escaping @MainActor (_ done: @escaping () -> Void) -> FirstRunView) {
        self.makeContent = content
    }

    func showIfNeeded() {
        guard !Defaults[.firstRunCompleted] else { return }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 540),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = String(localized: "Welcome to Perch")
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = FirstMouseHostingView(
            rootView: makeContent { [weak self] in self?.finish() }
        )
        window.center()
        self.window = window

        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    private func finish() {
        Defaults[.firstRunCompleted] = true
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        Defaults[.firstRunCompleted] = true
        window?.delegate = nil
        window = nil
    }
}

/// A hosting view that takes the click that brings its window forward.
///
/// macOS 14+ often declines to activate an accessory app, so this window can
/// stay non-key, and a hosting view refuses "first mouse" by default: every
/// click went to focusing a window that never took focus. The bordered
/// buttons worked, being real `NSButton`s; the preset cards did nothing.
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
