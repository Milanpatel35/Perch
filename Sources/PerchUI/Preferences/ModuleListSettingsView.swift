import Defaults
import PerchCore
import SwiftUI

/// Every module, with its switch.
///
/// The list is the contract from `docs/FEATURES.md`: each one switchable,
/// each one costing nothing when off.
struct ModuleListSettingsView: View {

    @Default(.enabledModules) private var enabledModules

    /// Appearance is module 18 — cross-cutting, no directory, no off switch.
    /// It has the General pane instead.
    private var modules: [ModuleID] {
        ModuleID.allCases.filter { $0 != .appearance }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(modules, id: \.self) { module in
                    row(for: module)
                    Divider()
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private func row(for module: ModuleID) -> some View {
        HStack(spacing: 12) {
            Image(systemName: module.symbolName)
                .frame(width: 22)
                .foregroundStyle(.secondary)

            Text(module.displayName)

            Spacer()

            Toggle("", isOn: binding(for: module))
                .labelsHidden()
                .toggleStyle(.switch)
                .accessibilityLabel(Text(module.displayName))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func binding(for module: ModuleID) -> Binding<Bool> {
        Binding(
            get: { enabledModules.contains(module) },
            set: { isOn in
                if isOn {
                    enabledModules.insert(module)
                } else {
                    enabledModules.remove(module)
                }
            }
        )
    }
}
