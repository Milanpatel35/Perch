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
    let switchboard = ModuleSwitchboard()

    lazy var modules = ModuleHost(
        switchboard: switchboard,
        island: island
    )

    private lazy var panel = IslandPanelController(
        controller: island,
        motion: motion,
        modules: modules
    )

    private var menuBar: MenuBarController?

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

        panel.show()

        // Modules come up after the panel, so the first activity a module
        // submits has somewhere to land. Only the ones whose switch is on
        // actually start.
        PerchModuleRegistry.registerAll(in: modules, island: island)

        menuBar = MenuBarController(island: island)
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Panel torn down explicitly: no orphan window, no orphan process
        // (TC-UPD-004).
        menuBar = nil
        modules.deactivateAll()
        panel.teardown()
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
