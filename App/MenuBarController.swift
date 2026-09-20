import AppKit
import PerchCore
import PerchUI

/// The menu-bar item.
///
/// The only part of Perch with a conventional macOS affordance, and the
/// answer to "how do I get to settings" and "how do I quit". Kept small: it
/// is a way in, not a second interface.
@MainActor
final class MenuBarController: NSObject {

    private let island: IslandController
    private let statusItem: NSStatusItem

    init(island: IslandController) {
        self.island = island
        self.statusItem = NSStatusBar.system.statusItem(
            withLength: NSStatusItem.variableLength
        )
        super.init()

        statusItem.button?.image = NSImage(
            systemSymbolName: "bird.fill",
            accessibilityDescription: "Perch"
        )
        statusItem.button?.image?.isTemplate = true
        statusItem.menu = makeMenu()
    }

    /// Removes the menu-bar item.
    ///
    /// Explicit rather than a `deinit`, because tidying up main-actor state
    /// from a deinitialiser means `MainActor.assumeIsolated`, and that traps
    /// outright if the last reference is released on another thread.
    /// `AppDelegate` calls this on termination (TC-UPD-004).
    func teardown() {
        statusItem.menu = nil
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()

        menu.addItem(
            withTitle: String(localized: "Open Island"),
            action: #selector(openIsland),
            keyEquivalent: ""
        ).target = self

        menu.addItem(.separator())

        menu.addItem(
            withTitle: String(localized: "Settings…"),
            action: #selector(openSettings),
            keyEquivalent: ","
        ).target = self

        menu.addItem(.separator())

        menu.addItem(
            withTitle: String(localized: "Quit Perch"),
            action: #selector(quit),
            keyEquivalent: "q"
        ).target = self

        return menu
    }

    @objc private func openIsland() {
        island.send(.clicked)
    }

    @objc private func openSettings() {
        // The app is an accessory, so it has to come forward before its
        // settings window can take focus.
        NSApp.activate(ignoringOtherApps: true)
        if #available(macOS 14.0, *) {
            NSApp.sendAction(
                Selector(("showSettingsWindow:")), to: nil, from: nil
            )
        } else {
            NSApp.sendAction(
                Selector(("showPreferencesWindow:")), to: nil, from: nil
            )
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
