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
            toolsSection
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

    @ViewBuilder
    private var toolsSection: some View {
        Section {
            Picker("Copy colours as", selection: colorFormat) {
                Text("HEX — #1B3A6B").tag(ColorFormat.hex)
                Text("RGB — rgb(27, 58, 107)").tag(ColorFormat.rgb)
                Text("HSL — hsl(217, 60%, 26%)").tag(ColorFormat.hsl)
            }
        } header: {
            Text("Tools")
        } footer: {
            Text(
                """
                Colour uses the system’s loupe and needs no permission. Measure \
                copies an area’s size in points. Scan reads the largest QR code \
                or barcode in an area on this Mac: a web address opens, \
                anything else is copied and never opened.
                """
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var colorFormat: Binding<ColorFormat> {
        Binding(
            get: { service.configuration.colorFormat },
            set: { value in
                var updated = service.configuration
                updated.colorFormat = value
                service.setConfiguration(updated)
            }
        )
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
