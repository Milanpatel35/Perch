import PerchCore
import SwiftUI

/// The Screenshots pane in Preferences.
struct ScreenshotSettingsView: View {

    @ObservedObject var service: ScreenshotService

    /// Whether the shelf is on, because "Shelf" only means the shelf while
    /// it is — otherwise captures go to the screenshot folder, and the pane
    /// says so rather than leaving somebody looking for them.
    let isShelfOn: Bool

    let screenshotFolder: URL

    var body: some View {
        Form {
            permissionSection
            captureSection
        }
        .formStyle(.grouped)
        // Checked when somebody looks, and never polled (`CLAUDE.md` §5.1).
        .onAppear { service.refreshPermission() }
    }

    @ViewBuilder
    private var permissionSection: some View {
        Section {
            LabeledContent("Screen Recording") {
                if service.hasPermission {
                    Text("Allowed").foregroundStyle(.secondary)
                } else {
                    Button("Open System Settings") { service.openPermissionSettings() }
                }
            }
        } footer: {
            Text(
                """
                Asked for the first time you take a screenshot, never before. \
                Text is read on this Mac by the system's own recogniser; \
                nothing you capture is sent anywhere.
                """
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var captureSection: some View {
        Section {
            Picker("Save screenshots to", selection: destination) {
                Text("Shelf").tag(ScreenshotDestination.shelf)
                Text("Clipboard").tag(ScreenshotDestination.clipboard)
                Text(screenshotFolder.lastPathComponent).tag(ScreenshotDestination.folder)
            }
            Toggle("Play the shutter sound", isOn: playsSound)
        } header: {
            Text("Screenshots")
        } footer: {
            Text(destinationNote)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var destinationNote: String {
        switch service.configuration.destination {
        case .shelf where !isShelfOn:
            String(
                localized: """
                    The Shelf module is off, so screenshots go to \
                    \(screenshotFolder.path) until it is on.
                    """)
        case .shelf:
            String(localized: "Drag them out, share or convert them from there.")
        case .clipboard:
            String(localized: "Nothing is saved; paste it where you need it.")
        case .folder:
            String(localized: "The same folder macOS saves its own screenshots to.")
        }
    }

    private var destination: Binding<ScreenshotDestination> {
        Binding(
            get: { service.configuration.destination },
            set: { value in
                var updated = service.configuration
                updated.destination = value
                service.setConfiguration(updated)
            }
        )
    }

    private var playsSound: Binding<Bool> {
        Binding(
            get: { service.configuration.playsSound },
            set: { value in
                var updated = service.configuration
                updated.playsSound = value
                service.setConfiguration(updated)
            }
        )
    }
}
