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
    private let settings: SettingsWindowController
    private let statusItem: NSStatusItem

    init(island: IslandController, settings: SettingsWindowController) {
        self.island = island
        self.settings = settings
        self.statusItem = NSStatusBar.system.statusItem(
            withLength: NSStatusItem.variableLength
        )
        super.init()

        // The mark, drawn for this size rather than an SF Symbol standing
        // in for it. It is a template image, so macOS tints it to match the
        // menu bar in either appearance.
        let mark = NSImage(named: "MenuBarIcon")
        mark?.isTemplate = true
        mark?.size = NSSize(width: 18, height: 18)
        statusItem.button?.image = mark
        statusItem.button?.image?.accessibilityDescription = "Perch"
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
        settings.show()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
