import Defaults
import KeyboardShortcuts
import PerchCore
import SwiftUI

extension CameraPresentation: Defaults.Serializable {}
extension PreCallCheck.Configuration: Defaults.Serializable {}

extension Defaults.Keys {

    static let cameraPresentation = Key<CameraPresentation>(
        "camera.presentation",
        default: CameraPresentation()
    )

    static let preCallCheck = Key<PreCallCheck.Configuration>(
        "camera.preCallCheck",
        default: PreCallCheck.Configuration()
    )

    /// The remembered camera. A `String?` rather than a device, because the
    /// device may not be plugged in when this is read.
    static let cameraDeviceID = Key<String?>("camera.deviceID", default: nil)
}

/// The Camera pane in Preferences.
struct CameraSettingsView: View {

    let presentation: CameraPresentation
    let devices: [CameraDevice]
    let selectedDeviceID: String?
    let preCall: PreCallCheck.Configuration
    let isCalendarOn: Bool
    let onPresentationChange: (CameraPresentation) -> Void
    let onPreCallChange: (PreCallCheck.Configuration) -> Void
    let onSelectDevice: (CameraDevice) -> Void
    let onRefreshDevices: () -> Void

    var body: some View {
        Form {
            Section("Camera") {
                if devices.isEmpty {
                    LabeledContent("Device", value: "None connected")
                } else {
                    Picker("Device", selection: deviceBinding) {
                        ForEach(devices) { device in
                            Text(label(for: device)).tag(device.id as String?)
                        }
                    }
                }
                Button("Look again", action: onRefreshDevices)
            }

            Section("Preview") {
                Picker("Shape", selection: shapeBinding) {
                    ForEach(CameraPresentation.Shape.allCases, id: \.self) { shape in
                        Text(shape.displayName).tag(shape)
                    }
                }

                Toggle("Mirror", isOn: mirrorBinding)

                LabeledContent("Size") {
                    Slider(
                        value: widthBinding,
                        in: CameraPresentation.minimumWidth...CameraPresentation.maximumWidth
                    )
                }

                LabeledContent("Opacity") {
                    Slider(value: opacityBinding, in: 0.25...1)
                }
            }

            preCallSection

            Section("Shortcut") {
                KeyboardShortcuts.Recorder("Show the camera", name: .cameraPreview)
            }

            Section {
                Text(
                    """
                    The camera opens when you open the preview and closes when \
                    you close it — not when you switch this module on, and not \
                    at launch. No frame is written anywhere unless you press \
                    snapshot, and nothing keeps a frame after the preview \
                    closes: the preview renders straight from the device and \
                    hands Perch nothing to keep.
                    """
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            } header: {
                Text("What the green light means")
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Pre-call check

    @ViewBuilder
    private var preCallSection: some View {
        Section {
            Toggle("Show me before a meeting starts", isOn: preCallEnabledBinding)

            if preCall.isEnabled {
                Picker("How early", selection: leadBinding) {
                    ForEach([15, 30, 45, 60, 120], id: \.self) { seconds in
                        Text(
                            seconds < 60
                                ? "^[\(seconds) second](inflect: true)"
                                : "^[\(seconds / 60) minute](inflect: true)"
                        )
                        .tag(seconds)
                    }
                }

                Toggle("Only for meetings with a join link", isOn: linkOnlyBinding)
            }
        } header: {
            Text("Pre-call check")
        } footer: {
            // TC-CAM-015. The dependency is real and saying so beats a
            // switch that silently does nothing.
            Text(
                isCalendarOn
                    ? String(
                        localized:
                            "The preview opens by itself, and closes by itself if you do nothing."
                    )
                    : String(
                        localized: """
                            This needs the Calendar module, which is switched \
                            off — nothing will fire.
                            """
                    )
            )
            .font(.caption)
            .foregroundStyle(isCalendarOn ? Color.secondary : Color.orange)
        }
    }

    private func label(for device: CameraDevice) -> String {
        device.isContinuity ? "\(device.name) (Continuity)" : device.name
    }

    // MARK: - Bindings

    private var deviceBinding: Binding<String?> {
        Binding(
            get: { selectedDeviceID ?? devices.first?.id },
            set: { id in
                guard let device = devices.first(where: { $0.id == id }) else { return }
                onSelectDevice(device)
            }
        )
    }

    private var shapeBinding: Binding<CameraPresentation.Shape> {
        Binding(
            get: { presentation.shape },
            set: { shape in
                var updated = presentation
                updated.shape = shape
                onPresentationChange(updated)
            }
        )
    }

    private var mirrorBinding: Binding<Bool> {
        Binding(
            get: { presentation.isMirrored },
            set: { isOn in
                var updated = presentation
                updated.isMirrored = isOn
                onPresentationChange(updated)
            }
        )
    }

    private var widthBinding: Binding<Double> {
        Binding(
            get: { presentation.width },
            set: { width in
                var updated = presentation
                updated.setWidth(width)
                onPresentationChange(updated)
            }
        )
    }

    private var opacityBinding: Binding<Double> {
        Binding(
            get: { presentation.opacity },
            set: { opacity in
                var updated = presentation
                updated.setOpacity(opacity)
                onPresentationChange(updated)
            }
        )
    }

    private var preCallEnabledBinding: Binding<Bool> {
        Binding(
            get: { preCall.isEnabled },
            set: { isOn in
                var updated = preCall
                updated.isEnabled = isOn
                onPreCallChange(updated)
            }
        )
    }

    private var leadBinding: Binding<Int> {
        Binding(
            get: { Int(preCall.lead.seconds) },
            set: { seconds in
                var updated = preCall
                updated.lead = .seconds(seconds)
                onPreCallChange(updated)
            }
        )
    }

    private var linkOnlyBinding: Binding<Bool> {
        Binding(
            get: { preCall.requiresMeetingLink },
            set: { isOn in
                var updated = preCall
                updated.requiresMeetingLink = isOn
                onPreCallChange(updated)
            }
        )
    }
}
