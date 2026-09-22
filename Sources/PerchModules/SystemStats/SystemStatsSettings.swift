import Defaults
import PerchCore
import SwiftUI

extension StatAlerts.Configuration: Defaults.Serializable {}
extension GaugeKind: Defaults.Serializable {}

extension Defaults.Keys {

    static let systemGauges = Key<[GaugeKind]>("systemstats.gauges", default: [.cpu, .memory])

    static let statAlerts = Key<StatAlerts.Configuration>(
        "systemstats.alerts",
        default: StatAlerts.Configuration()
    )
}

/// The System Stats pane in Preferences.
struct SystemStatsSettingsView: View {

    let gauges: [GaugeKind]
    let alerts: StatAlerts.Configuration
    let snapshot: SystemSnapshot
    let isPublicIPEnabled: Bool
    let isSampling: Bool
    let onGaugesChange: ([GaugeKind]) -> Void
    let onAlertsChange: (StatAlerts.Configuration) -> Void
    let onPublicIPChange: (Bool) -> Void

    var body: some View {
        Form {
            Section {
                ForEach(GaugeKind.allCases) { kind in
                    Toggle(
                        kind.displayName,
                        isOn: Binding(
                            get: { gauges.contains(kind) },
                            set: { isOn in toggle(kind, isOn) }
                        )
                    )
                    .disabled(!gauges.contains(kind) && gauges.count >= 2)
                }
            } header: {
                Text("In the collapsed island")
            } footer: {
                Text(
                    """
                    Pick two. The space beside the notch fits two readouts; a \
                    third would mean type too small to read.
                    """
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            alertsSection
            networkSection

            Section {
                LabeledContent(
                    "Sampling",
                    value: isSampling ? "Every few seconds" : "Not running"
                )
            } header: {
                Text("Cost")
            } footer: {
                Text(
                    """
                    Perch samples only while a readout is actually on screen. \
                    With the island closed and no gauge showing, no timer \
                    exists at all — not a slower one, none.
                    """
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Alerts

    @ViewBuilder
    private var alertsSection: some View {
        Section {
            ForEach(alerts.rules) { rule in
                Toggle(
                    rule.metric.displayName,
                    isOn: Binding(
                        get: { rule.isEnabled },
                        set: { isOn in setEnabled(rule, isOn) }
                    )
                )
            }
        } header: {
            Text("Tell me when")
        } footer: {
            Text(
                """
                Every alert is off to begin with. Each one fires once when it \
                is crossed, not once per sample, and re-arms only after the \
                value has come well back.
                """
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Network

    @ViewBuilder
    private var networkSection: some View {
        Section {
            Toggle("Show my public IP address", isOn: publicIPBinding)

            if isPublicIPEnabled, let address = snapshot.network.publicIP {
                LabeledContent("Public IP", value: address)
            }
        } header: {
            Text("Network")
        } footer: {
            // `CLAUDE.md` §5.2. Disclosed in the pane it lives in, in as
            // many words (TC-SYS-012).
            Text(
                """
                This is the only feature in Perch that makes a network request \
                — one call to api.ipify.org, carrying no identifier, and only \
                while this switch is on. It is off by default, and everything \
                else in Perch works entirely on your Mac.
                """
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Editing

    /// Two at a time. Turning a third on drops the oldest rather than
    /// refusing the click, which is what somebody who just pressed it means.
    private func toggle(_ kind: GaugeKind, _ isOn: Bool) {
        var updated = gauges

        if isOn {
            guard !updated.contains(kind) else { return }
            updated.append(kind)
            if updated.count > 2 { updated.removeFirst() }
        } else {
            updated.removeAll { $0 == kind }
        }

        onGaugesChange(updated)
    }

    private func setEnabled(_ rule: StatAlerts.Rule, _ isOn: Bool) {
        var updated = alerts
        guard let index = updated.rules.firstIndex(where: { $0.metric == rule.metric }) else {
            return
        }
        updated.rules[index].isEnabled = isOn
        onAlertsChange(updated)
    }

    /// Written out rather than passing `onPublicIPChange` straight in: the
    /// macOS 14 SDK types `Binding`'s setter as `@isolated(any) @Sendable`,
    /// and handing it a plain stored closure is a conversion it refuses.
    /// A closure literal is inferred at the isolation it is written in.
    private var publicIPBinding: Binding<Bool> {
        Binding(
            get: { isPublicIPEnabled },
            set: { isOn in onPublicIPChange(isOn) }
        )
    }
}
