import AppKit
import PerchCore
import PerchUI
import SwiftUI

/// Wires the island together and puts it on screen.
///
/// Deliberately thin. It owns the long-lived objects and nothing else — no
/// state, no policy. State lives in `PerchCore` and is reached through
/// `IslandController` (`CLAUDE.md` §3).
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private let motion = MotionPreferences()
    private let island = IslandController()

    /// Lazy so that nothing reads a preference before
    /// `applicationWillFinishLaunching` has moved the old dotted keys.
    private(set) lazy var switchboard = ModuleSwitchboard()

    lazy var modules = ModuleHost(
        switchboard: switchboard,
        island: island
    )

    private lazy var panel = IslandPanelController(
        controller: island,
        motion: motion,
        modules: modules
    )

    private let launchAtLogin = LaunchAtLogin()

    private var menuBar: MenuBarController?
    private var islandPreferences: IslandPreferences?

    private(set) lazy var settings = SettingsWindowController { [unowned self] in
        PreferencesView(
            switchboard: switchboard,
            launchAtLogin: launchAtLogin,
            paneProvider: { [unowned self] module in
                PerchModuleRegistry.settingsPane(for: module, in: modules)
            },
            isBuilt: { [unowned self] module in modules.module(for: module) != nil }
        )
    }

    private lazy var firstRun = FirstRunWindowController { [unowned self] done in
        FirstRunView(
            switchboard: switchboard,
            launchAtLogin: launchAtLogin,
            built: Set(ModuleID.allCases.filter { modules.module(for: $0) != nil }),
            onOpenSettings: { [unowned self] in settings.show() },
            onDone: done
        )
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        PreferenceMigration.migrateDottedKeys()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // No Dock icon, no main menu, no window on launch. The island is the
        // app (TC-UPD-003).
        NSApp.setActivationPolicy(.accessory)

        // The home surface follows the island between displays: a 14" notch
        // and a 16" notch are different sizes, and so is the virtual pill.
        panel.onLayoutChange = { [weak self] layout in
            self?.island.submit(
                HomeActivity(collapsedSize: layout.metrics.collapsedSize)
            )
        }

        // Before `show()`, so the island is placed on the chosen screen the
        // first time rather than moved there a moment later.
        islandPreferences = IslandPreferences(island: island, panel: panel)
        panel.show()

        // Modules come up after the panel, so the first activity a module
        // submits has somewhere to land. Only the ones whose switch is on
        // actually start.
        PerchModuleRegistry.registerAll(in: modules, island: island)

        menuBar = MenuBarController(island: island, settings: settings)

        // After the modules, so the presets know which ones are built.
        firstRun.showIfNeeded()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Panel torn down explicitly: no orphan window, no orphan process
        // (TC-UPD-004).
        menuBar?.teardown()
        menuBar = nil
        islandPreferences?.stop()
        modules.deactivateAll()
        panel.teardown()
    }

    /// Every `perch://` URL — from a link, the Shortcuts app's actions, or
    /// the `perch` CLI. The Shortcuts module decides what is allowed; with
    /// it switched off, a URL does nothing (TC-SHC-003).
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            modules.handlePerchURL(url)
        }
    }

    /// A menu-bar app has nothing to reopen. Without this, clicking the app
    /// in Spotlight would try to make a window that does not exist.
    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows: Bool
    ) -> Bool {
        false
    }
}
