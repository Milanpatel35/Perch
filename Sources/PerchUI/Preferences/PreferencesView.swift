import PerchCore
import SwiftUI

/// The preferences window.
///
/// A sidebar rather than a row of tabs, because seventeen modules do not fit
/// in a row of tabs. Each module supplies its own pane
/// (`<Name>Settings.swift`, `CLAUDE.md` §4) and appears here automatically —
/// there is no list of panes to keep in step with the list of modules.
public struct PreferencesView: View {

    /// Supplies each module's pane. Injected rather than imported so that
    /// `PerchUI` does not have to know what the modules are.
    public typealias PaneProvider = @MainActor (ModuleID) -> AnyView?

    private enum Section: Hashable {
        case general
        case module(ModuleID)
        case about
    }

    @ObservedObject private var switchboard: ModuleSwitchboard

    private let paneProvider: PaneProvider
    @State private var selection: Section? = .general

    public init(
        switchboard: ModuleSwitchboard,
        paneProvider: @escaping PaneProvider
    ) {
        self.switchboard = switchboard
        self.paneProvider = paneProvider
    }

    public var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .frame(minWidth: 720, minHeight: 460)
    }

    private var sidebar: some View {
        List(selection: $selection) {
            Label("General", systemImage: "gearshape").tag(Section.general)

            SwiftUI.Section("Modules") {
                ForEach(listedModules, id: \.self) { module in
                    row(for: module).tag(Section.module(module))
                }
            }

            Label("About", systemImage: "info.circle").tag(Section.about)
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 210, ideal: 220, max: 260)
    }

    /// Module 18 — appearance and gestures — has no switch of its own. It is
    /// the island, and its pane is General.
    private var listedModules: [ModuleID] {
        ModuleID.allCases.filter { $0 != .appearance }
    }

    private func row(for module: ModuleID) -> some View {
        HStack {
            Label(module.displayName, systemImage: module.symbolName)
            Spacer()
            Toggle("", isOn: binding(for: module))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .accessibilityLabel(Text("Enable \(module.displayName)"))
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .general, .none:
            GeneralSettingsView()
        case .about:
            AboutSettingsView()
        case .module(let module):
            ModulePane(
                module: module,
                isEnabled: binding(for: module),
                content: paneProvider(module)
            )
        }
    }

    /// The switchboard is the only source of truth for this. Reading the
    /// defaults key directly would let the window and the running modules
    /// drift apart the moment anything else flipped a switch.
    private func binding(for module: ModuleID) -> Binding<Bool> {
        Binding(
            get: { switchboard.isEnabled(module) },
            set: { switchboard.setEnabled(module, $0) }
        )
    }
}

/// One module's pane: its switch, then whatever it has to say for itself.
///
/// A module that has not been built yet still gets a page rather than an
/// empty panel, because the switch has to live somewhere and "coming in a
/// later release" is a more honest answer than a blank rectangle.
private struct ModulePane: View {

    let module: ModuleID
    @Binding var isEnabled: Bool
    let content: AnyView?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: module.symbolName)
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)
                    .frame(width: 24)

                Text(module.displayName)
                    .font(.title3.weight(.semibold))

                Spacer()

                Toggle("", isOn: $isEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .accessibilityLabel(Text("Enable \(module.displayName)"))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            Divider()

            if let content {
                content
            } else {
                ContentUnavailable(module: module)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct ContentUnavailable: View {

    let module: ModuleID

    var body: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "hammer")
                .font(.system(size: 24))
                .foregroundStyle(.tertiary)
            Text("\(module.displayName) is on the way")
                .font(.callout)
            Text("It is in docs/PLAN.md, and it will be free when it lands.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
