import SwiftUI

/// The Updates box in the About pane.
struct UpdatesSettingsSection: View {

    @ObservedObject var updates: SoftwareUpdates

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                statusIcon
                VStack(alignment: .leading, spacing: 2) {
                    Text(statusLine).font(.callout.weight(.medium))
                    if let lastChecked = updates.lastChecked {
                        Text("Last checked \(lastChecked, format: .relative(presentation: .named))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button(buttonTitle) { updates.checkNow() }
                    .disabled(!updates.canCheck)
            }

            Toggle("Check for updates automatically", isOn: $updates.checksAutomatically)
                .toggleStyle(.checkbox)

            Text(
                """
                Once a day, Perch reads one small file listing its releases — \
                the only request it makes unless you switch something else on. \
                Turn this off and it asks only when you press the button.
                """
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            // No `.fixedSize(horizontal: false, vertical: true)` here. Inside
            // the About pane's full-height stack, in a NavigationSplitView,
            // it sent layout round in a loop and the whole Settings window —
            // sidebar too — drew nothing the moment About was selected
            // (TC-UPD-008). The text wraps to the box's width without it.
        }
        .padding(14)
        .frame(maxWidth: 420)
        .background(RoundedRectangle(cornerRadius: 10).fill(.quaternary.opacity(0.5)))
    }

    private var buttonTitle: LocalizedStringKey {
        if case .available = updates.status { return "Install Update…" }
        return "Check for Updates…"
    }

    private var statusLine: String {
        switch updates.status {
        case .unknown:
            String(localized: "Updates")
        case .checking:
            String(localized: "Checking…")
        case .upToDate:
            String(localized: "Perch is up to date")
        case .available(let version):
            String(localized: "Perch \(version) is available")
        case .failed:
            String(localized: "Couldn’t check for updates")
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch updates.status {
        case .checking:
            ProgressView().controlSize(.small)
        case .upToDate:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .available:
            Image(systemName: "arrow.down.circle.fill").foregroundStyle(.blue)
        case .failed:
            Image(systemName: "wifi.exclamationmark").foregroundStyle(.secondary)
        case .unknown:
            Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(.secondary)
        }
    }
}
