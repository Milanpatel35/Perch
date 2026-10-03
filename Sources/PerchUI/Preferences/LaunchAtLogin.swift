import Combine
import Foundation
import PerchCore
import ServiceManagement

/// Whether Perch opens at login.
///
/// A menu-bar app that is gone after a restart is one most people never
/// open again. `SMAppService.mainApp` is the macOS 13 API for it — no helper
/// app, no launch agent written by hand — and the system keeps the truth, so
/// this reads it back rather than remembering a copy that can drift
/// (the user can remove it in System Settings ▸ General ▸ Login Items).
@MainActor
public final class LaunchAtLogin: ObservableObject {

    @Published public private(set) var isEnabled: Bool

    /// Set when the system refused, so the switch can say why instead of
    /// flicking back without a word.
    @Published public private(set) var failure: String?

    public let location: InstallLocation

    public init(bundlePath: String = Bundle.main.bundlePath) {
        self.location = InstallLocation(bundlePath: bundlePath)
        self.isEnabled = SMAppService.mainApp.status == .enabled
    }

    public var isAvailable: Bool { location.supportsLaunchAtLogin }

    public func setEnabled(_ enabled: Bool) {
        guard isAvailable else { return }
        failure = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            failure = error.localizedDescription
        }
        refresh()
    }

    /// Re-reads the system's answer. Called when Settings appears, because
    /// System Settings can change it behind Perch's back.
    public func refresh() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }
}
