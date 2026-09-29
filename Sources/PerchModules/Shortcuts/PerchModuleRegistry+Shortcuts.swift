import Foundation
import PerchCore

extension PerchModuleRegistry {

    /// "Add to shelf" and "Start focus session" from the Shortcuts app, a
    /// URL or the CLI (`docs/FEATURES.md` §13). Returning false is how the
    /// Shortcuts module learns the other module is off, and says so on the
    /// island instead of doing nothing.
    @MainActor
    static func wireShortcutsToModules(in host: ModuleHost) {
        guard let shortcuts = host.service(ShortcutsService.self) else { return }

        shortcuts.onAddToShelf = { [weak host] url in
            guard let shelf = host?.service(ShelfService.self), shelf.isActive else { return false }
            return shelf.add(fileAt: url) != nil
        }

        shortcuts.onStartFocus = { [weak host] in
            guard let focus = host?.service(FocusService.self), focus.isActive else { return false }
            focus.start()
            return true
        }
    }
}
