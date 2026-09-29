import Defaults
import PerchCore
import SwiftUI

extension HideNotchConfiguration: Defaults.Serializable {}

extension Defaults.Keys {
    static let hideNotch = Key<HideNotchConfiguration>(
        "hideNotch.configuration",
        default: HideNotchConfiguration()
    )
}

/// The Hide-the-notch pane in Preferences.
struct HideNotchSettingsView: View {

    let configuration: HideNotchConfiguration
    let displays: [HideNotchDisplay]
    let onChange: (HideNotchConfiguration) -> Void
    let onDisplayChange: (String, Bool) -> Void

    var body: some View {
        Form {
            Section {
                Toggle("Black out the menu bar", isOn: blackoutBinding)

                if configuration.isBlackoutEnabled {
                    Picker("Fill", selection: fillBinding) {
                        ForEach(HideNotchConfiguration.Fill.allCases, id: \.self) { fill in
                            Text(fill.displayName).tag(fill)
                        }
                    }
                }
            } header: {
                Text("Menu bar")
            } footer: {
                Text(
                    """
                    A strip is drawn behind the menu bar — never over it — so \
                    the notch disappears into the bar. The menus, status items \
                    and the island all stay on top.
                    """
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if configuration.isBlackoutEnabled {
                displaysSection
            }

            Section {
                Toggle("Invisible until something happens", isOn: invisibleBinding)
            } header: {
                Text("Island")
            } footer: {
                Text(
                    """
                    The island draws nothing while idle and appears only when a \
                    module has something to show. Hovering the notch still \
                    opens it.
                    """
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var displaysSection: some View {
        Section {
            if displays.isEmpty {
                LabeledContent("Displays", value: "None found")
            }
            ForEach(displays) { display in
                Toggle(isOn: displayBinding(display)) {
                    Text(display.name)
                    if display.hasNotch {
                        Text("Has a notch").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("Displays")
        } footer: {
            Text("Displays with a notch are on unless you switch them off; the rest are off.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Bindings

    private var blackoutBinding: Binding<Bool> {
        Binding(
            get: { configuration.isBlackoutEnabled },
            set: { isOn in
                var updated = configuration
                updated.isBlackoutEnabled = isOn
                onChange(updated)
            }
        )
    }

    private var fillBinding: Binding<HideNotchConfiguration.Fill> {
        Binding(
            get: { configuration.fill },
            set: { fill in
                var updated = configuration
                updated.fill = fill
                onChange(updated)
            }
        )
    }

    private var invisibleBinding: Binding<Bool> {
        Binding(
            get: { configuration.isInvisibleWhenIdle },
            set: { isOn in
                var updated = configuration
                updated.isInvisibleWhenIdle = isOn
                onChange(updated)
            }
        )
    }

    private func displayBinding(_ display: HideNotchDisplay) -> Binding<Bool> {
        Binding(
            get: { display.showsStrip },
            set: { onDisplayChange(display.id, $0) }
        )
    }
}
