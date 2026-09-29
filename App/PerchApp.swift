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
        // A SwiftUI app has to declare a scene, and this one is empty on
        // purpose. The real Settings window is `SettingsWindowController`,
        // because from macOS 14 this scene can only be opened by a
        // `SettingsLink` in a view, and a menu-bar menu has none.
        Settings {
            EmptyView()
        }
    }
}
