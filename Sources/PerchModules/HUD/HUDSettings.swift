import Defaults
import PerchCore
import SwiftUI

extension HUDKind: Defaults.Serializable {}

extension Defaults.Keys {

    /// Which of the six HUDs are on. All of them, by default — a HUD module
    /// that replaces nothing is not a module.
    static let enabledHUDs = Key<Set<HUDKind>>(
        "hud.enabled",
        default: Set(HUDKind.allCases)
    )

    /// Whether to suspend `OSDUIHelper` while the module is on.
    ///
    /// On by default, because without it you get two HUDs for every key
    /// press and the module looks broken. It is a switch rather than a fact
    /// because it is the one thing Perch does to the rest of the system, and
    /// anybody who would rather it did not should be able to say so —
    /// [ADR 0005](../../../docs/adr/0005-private-apis-for-the-hud.md).
    static let hudSuppressesStockHUD = Key<Bool>("hud.suppressesStockHUD", default: true)
}

/// The HUD pane in Preferences.
struct HUDSettingsView: View {

    @Default(.hudSuppressesStockHUD) private var suppressesStockHUD

    let enabled: Set<HUDKind>
    let isBrightnessAvailable: Bool
    let isSuppressing: Bool
    let onToggle: (HUDKind, Bool) -> Void
    let onSuppressionChange: (Bool) -> Void

    var body: some View {
        Form {
            Section {
                ForEach(HUDKind.allCases, id: \.self) { kind in
                    Toggle(kind.displayName, isOn: binding(for: kind))
                        .disabled(kind == .brightness && !isBrightnessAvailable)
                }
            } header: {
                Text("Replace")
            } footer: {
                if !isBrightnessAvailable {
                    Text(
                        """
                        Brightness is unavailable on this Mac: the system \
                        interface Perch reads it through did not load. \
                        Every other HUD is unaffected.
                        """
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            Section {
                Toggle("Hide the built-in macOS overlay", isOn: suppressionBinding)
            } header: {
                Text("The stock HUD")
            } footer: {
                Text(
                    """
                    macOS draws its own overlay in the middle of the screen. \
                    With this on, Perch suspends the system agent that draws \
                    it for as long as the module is switched on, and resumes \
                    it the instant you switch the module off or quit. \
                    Nothing is killed and nothing is changed on disk.
                    """
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Stock overlay") {
                    Text(isSuppressing ? "Suspended by Perch" : "Normal")
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text(
                    """
                    Keyboard backlight and AirDrop are not here. macOS \
                    publishes no notification for either, so a switch for \
                    them would be a switch that never does anything. \
                    docs/FEATURES.md §6 records both.
                    """
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    /// Bindings that report on set, rather than `onChange` — which is
    /// deprecated on newer SDKs and whose replacement does not exist on the
    /// macOS 13 floor this app builds for.
    private func binding(for kind: HUDKind) -> Binding<Bool> {
        Binding(
            get: { enabled.contains(kind) },
            set: { onToggle(kind, $0) }
        )
    }

    private var suppressionBinding: Binding<Bool> {
        Binding(
            get: { suppressesStockHUD },
            set: { newValue in
                suppressesStockHUD = newValue
                onSuppressionChange(newValue)
            }
        )
    }
}
