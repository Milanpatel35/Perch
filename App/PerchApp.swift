import PerchUI
import SwiftUI

/// Perch.
///
/// There is no main window. The app is an `LSUIElement` accessory: a menu-bar
/// item, a preferences window, and an island that lives above the menu bar in
/// its own panel. Everything user-facing is set up by `AppDelegate`.
@main
struct PerchApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        // The one real scene. `Settings` gives the preferences window its
        // standard ⌘, behaviour, placement and restoration for free.
        Settings {
            PreferencesView(
                switchboard: delegate.switchboard,
                paneProvider: { module in
                    PerchModuleRegistry.settingsPane(for: module, in: delegate.modules)
                }
            )
        }
    }
}
