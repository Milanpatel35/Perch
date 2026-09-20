import Combine
import Foundation
import PerchCore

/// Owns every module and keeps them in step with their switches.
///
/// The one place that decides a module is running. Modules never check the
/// switchboard themselves — if they did, "off" would mean "off, mostly", and
/// `docs/TEST-PLAN.md` § PRF would start failing in ways nobody could
/// attribute.
@MainActor
public final class ModuleHost: ObservableObject {

    private let switchboard: ModuleSwitchboard
    private let island: IslandController

    private var modules: [ModuleID: any PerchModule] = [:]
    private var cancellables: Set<AnyCancellable> = []

    public init(switchboard: ModuleSwitchboard, island: IslandController) {
        self.switchboard = switchboard
        self.island = island

        switchboard.changes
            .sink { [weak self] module, isOn in
                self?.apply(isOn, to: module)
            }
            .store(in: &cancellables)
    }

    deinit {
        MainActor.assumeIsolated {
            for module in modules.values {
                module.deactivate()
            }
        }
    }

    /// Registers a module. Activates it immediately if its switch is already
    /// on, which is the launch path for a returning user.
    public func register(_ module: any PerchModule) {
        let id = type(of: module).moduleID
        modules[id] = module

        if switchboard.isEnabled(id) {
            module.activate()
        }
    }

    public func module(for id: ModuleID) -> (any PerchModule)? {
        modules[id]
    }

    /// Reaches a module's service by type. This is how a module's view calls
    /// back into the thing that owns its resources — a transport button, a
    /// shelf drop, a camera shutter — without any of them becoming globals.
    public func service<M: PerchModule>(_ type: M.Type = M.self) -> M? {
        modules[M.moduleID] as? M
    }

    /// Tears every module down. Called on quit so nothing outlives the app.
    public func deactivateAll() {
        for module in modules.values {
            module.deactivate()
        }
        cancellables.removeAll()
    }

    private func apply(_ isOn: Bool, to id: ModuleID) {
        guard let module = modules[id] else { return }

        if isOn {
            module.activate()
        } else {
            module.deactivate()
            // Belt and braces: a module that forgot to withdraw its own
            // activities must still not leave one on screen.
            island.withdrawAll(from: id)
        }
    }
}
