import PerchCore
import SwiftUI

/// The preferences window.
///
/// One pane per module, plus the cross-cutting ones. Fleshed out module by
/// module — each `<Name>Settings.swift` supplies its own pane
/// (`CLAUDE.md` §4).
public struct PreferencesView: View {

    public init() {}

    public var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }

            ModuleListSettingsView()
                .tabItem { Label("Modules", systemImage: "square.grid.2x2") }

            AboutSettingsView()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 520, height: 420)
    }
}
