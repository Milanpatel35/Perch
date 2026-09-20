import Foundation
import PerchCore
import SwiftUI

/// Where every module is wired in.
///
/// One line per module, and the only line the app target needs to know about.
/// Adding a module means adding it here and nowhere else — the switchboard,
/// the preferences list and the teardown path all come from `ModuleHost`
/// (`CLAUDE.md` §4).
///
/// Modules are registered whether or not they are switched on. `ModuleHost`
/// activates only the ones whose switch is on, which is what keeps a module
/// that nobody uses at literally zero cost (`CLAUDE.md` §5.1).
public enum PerchModuleRegistry {

    @MainActor
    public static func registerAll(in host: ModuleHost, island: IslandController) {
        host.register(NowPlayingService(island: island))
    }

    /// The Preferences pane for a module, if it has one yet.
    ///
    /// `nil` means the module has not been built — Preferences shows the
    /// switch and says so, which is a more honest answer than a blank panel.
    @MainActor
    public static func settingsPane(
        for module: ModuleID,
        in host: ModuleHost
    ) -> AnyView? {
        switch module {
        case .nowPlaying:
            AnyView(
                NowPlayingSettingsView(
                    knownSources: host.service(NowPlayingService.self)?.knownSources ?? []
                )
            )
        default:
            nil
        }
    }
}
