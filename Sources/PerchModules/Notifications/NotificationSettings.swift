import Defaults
import PerchCore
import SwiftUI

extension NotificationPolicy.Configuration: Defaults.Serializable {}

extension Defaults.Keys {

    static let notificationPolicy = Key<NotificationPolicy.Configuration>(
        "notifications.policy",
        default: NotificationPolicy.Configuration()
    )
}

/// The Notifications pane in Preferences.
struct NotificationSettingsView: View {

    let isWatching: Bool
    let configuration: NotificationPolicy.Configuration
    let knownApps: [String: String]
    let onChange: (NotificationPolicy.Configuration) -> Void
    let onRequestAccessibility: () -> Void

    var body: some View {
        Form {
            accessSection

            Section {
                Picker("Apps", selection: modeBinding) {
                    Text("Mirror everything except").tag(NotificationPolicy.Mode.denyListed)
                    Text("Mirror only").tag(NotificationPolicy.Mode.allowListedOnly)
                }
                .pickerStyle(.radioGroup)
            } header: {
                Text("Which notifications")
            } footer: {
                Text(
                    """
                    The list fills itself in as apps post notifications — Perch \
                    does not read your installed apps to build it.
                    """
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            appList

            Section {
                Toggle("Hold them while a focus session runs", isOn: silentBinding)
            } footer: {
                Text(
                    """
                    Held, not dropped. Everything that arrived during the session \
                    appears when it ends, grouped by app.
                    """
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section {
                Text(
                    """
                    macOS has no API that hands one app another app's \
                    notifications, so Perch reads the banner itself through \
                    Accessibility. That means it mirrors what is on screen and \
                    nothing more — no notification history, nothing read from \
                    disk. Do Not Disturb is respected: a banner macOS does not \
                    draw is one Perch never sees.
                    """
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            } header: {
                Text("How this works")
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Access

    @ViewBuilder
    private var accessSection: some View {
        if !isWatching {
            // TC-NTF-008. An explanation and a button, not an error.
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(
                        """
                        Mirroring needs Accessibility, because reading a banner \
                        is the only way macOS allows it.
                        """
                    )
                    .font(.callout)

                    Button("Grant Accessibility…", action: onRequestAccessibility)
                }
            } header: {
                Text("Accessibility")
            }
        }
    }

    // MARK: - The list

    @ViewBuilder
    private var appList: some View {
        if knownApps.isEmpty {
            Section {
                Text("No app has posted a notification yet.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        } else {
            Section(listHeader) {
                ForEach(knownApps.sorted(by: { $0.value < $1.value }), id: \.key) { app in
                    Toggle(
                        app.value,
                        isOn: Binding(
                            get: { configuration.apps.contains(app.key) },
                            set: { isOn in
                                var updated = configuration
                                if isOn {
                                    updated.apps.insert(app.key)
                                } else {
                                    updated.apps.remove(app.key)
                                }
                                onChange(updated)
                            }
                        )
                    )
                }
            }
        }
    }

    private var listHeader: LocalizedStringKey {
        configuration.mode == .denyListed ? "Never mirror" : "Mirror these"
    }

    // MARK: - Bindings

    private var modeBinding: Binding<NotificationPolicy.Mode> {
        Binding(
            get: { configuration.mode },
            set: { mode in
                var updated = configuration
                updated.mode = mode
                // The list means the opposite thing in the other mode, so
                // carrying it across would silence exactly the apps somebody
                // had just asked to see.
                updated.apps = []
                onChange(updated)
            }
        )
    }

    private var silentBinding: Binding<Bool> {
        Binding(
            get: { configuration.silentDuringFocus },
            set: { isOn in
                var updated = configuration
                updated.silentDuringFocus = isOn
                onChange(updated)
            }
        )
    }
}
