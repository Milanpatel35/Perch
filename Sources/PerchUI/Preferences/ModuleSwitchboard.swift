import Combine
import Defaults
import Foundation
import PerchCore

/// Which modules are on, and the one place anything asks.
///
/// Every module is individually switchable and costs nothing when off
/// (`CLAUDE.md` §4). "Costs nothing" is the hard part, and it is not this
/// type's job to enforce — it is `PerchModule.activate` / `deactivate`. What
/// this owns is the switch, and telling everyone it flipped.
@MainActor
public final class ModuleSwitchboard: ObservableObject {

    @Published public private(set) var enabled: Set<ModuleID>

    /// Fires on every change, with the module and its new state. Modules
    /// subscribe to this rather than polling the set.
    public let changes = PassthroughSubject<(ModuleID, Bool), Never>()

    public init() {
        self.enabled = Defaults[.enabledModules]
    }

    public func isEnabled(_ module: ModuleID) -> Bool {
        // Appearance is not a module you can switch off — it is the island
        // itself. Its individual gestures have their own switches.
        module == .appearance || enabled.contains(module)
    }

    public func setEnabled(_ module: ModuleID, _ isOn: Bool) {
        guard module != .appearance else { return }
        guard isEnabled(module) != isOn else { return }

        if isOn {
            enabled.insert(module)
        } else {
            enabled.remove(module)
        }

        Defaults[.enabledModules] = enabled
        changes.send((module, isOn))
    }

    /// Switches on exactly `modules` among those that exist, and off the
    /// rest of them. Used by the first run's presets. One module at a time,
    /// through `setEnabled`, so every module hears about its own switch the
    /// same way it would from Settings.
    public func apply(_ modules: Set<ModuleID>, among built: Set<ModuleID>) {
        for module in built.subtracting(modules) {
            setEnabled(module, false)
        }
        for module in modules.intersection(built) {
            setEnabled(module, true)
        }
    }

    public func toggle(_ module: ModuleID) {
        setEnabled(module, !isEnabled(module))
    }
}
