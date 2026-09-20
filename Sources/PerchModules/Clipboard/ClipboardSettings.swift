import Defaults
import KeyboardShortcuts
import PerchCore
import SwiftUI

extension Defaults.Keys {

    /// Read text out of copied images, on-device.
    static let clipboardOCR = Key<Bool>("clipboard.ocr", default: true)

    static let clipboardMaximumCount = Key<Int>("clipboard.maximumCount", default: 200)

    /// Days to keep an unpinned entry. Zero means forever.
    static let clipboardMaximumDays = Key<Int>("clipboard.maximumDays", default: 7)
}

/// The Clipboard pane in Preferences.
struct ClipboardSettingsView: View {

    @Default(.clipboardOCR) private var ocr
    @Default(.clipboardMaximumCount) private var maximumCount
    @Default(.clipboardMaximumDays) private var maximumDays

    let entryCount: Int
    let pinnedCount: Int
    let excludedBundleIDs: [String]
    let onRetentionChange: (ClipboardHistory.Retention) -> Void
    let onClear: () -> Void

    var body: some View {
        Form {
            Section {
                KeyboardShortcuts.Recorder(
                    "Open the picker",
                    name: .clipboardPicker
                )
            } header: {
                Text("Shortcut")
            } footer: {
                Text(
                    """
                    Unset by default. A clipboard manager that claims a global \
                    shortcut without being asked will collide with something, \
                    and the collision will be silent.
                    """
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section {
                Picker("At most", selection: countBinding) {
                    ForEach([50, 100, 200, 500, 1000], id: \.self) { count in
                        Text("\(count) items").tag(count)
                    }
                }
                Picker("For", selection: daysBinding) {
                    Text("A day").tag(1)
                    Text("A week").tag(7)
                    Text("A month").tag(30)
                    Text("Forever").tag(0)
                }
            } header: {
                Text("Keep")
            } footer: {
                Text(
                    """
                    Pinned items are never removed, whatever these say. \
                    NotchBay caps its tray at 60 and doesn't let you change it.
                    """
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Read text out of copied images", isOn: $ocr)
            } header: {
                Text("Images")
            } footer: {
                Text(
                    """
                    Recognition happens on your Mac using Apple's Vision \
                    framework. Nothing is uploaded, and no network request is \
                    made at any point.
                    """
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section {
                if excludedBundleIDs.isEmpty {
                    Text("Nothing excluded").foregroundStyle(.secondary)
                }
                ForEach(excludedBundleIDs, id: \.self) { bundleID in
                    Text(bundleID).font(.system(size: 11, design: .monospaced))
                }
            } header: {
                Text("Never record from")
            } footer: {
                Text(
                    """
                    Password managers are excluded out of the box. Separately \
                    and unconditionally, anything marked as a concealed \
                    pasteboard type is never recorded — there is no setting \
                    for that, because the app that marked it knows better \
                    than a checkbox.
                    """
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section("Holding") {
                LabeledContent("Items", value: "\(entryCount)")
                LabeledContent("Pinned", value: "\(pinnedCount)")
                Button("Clear everything unpinned", role: .destructive, action: onClear)
                    .disabled(entryCount == pinnedCount)
            }
        }
        .formStyle(.grouped)
    }

    /// Written as bindings that report on set, rather than as `onChange`:
    /// `onChange(of:perform:)` is deprecated on newer SDKs and its
    /// replacement does not exist on the macOS 13 floor this app builds for.
    private var countBinding: Binding<Int> {
        Binding(
            get: { maximumCount },
            set: { newValue in
                maximumCount = newValue
                onRetentionChange(retention(count: newValue, days: maximumDays))
            }
        )
    }

    private var daysBinding: Binding<Int> {
        Binding(
            get: { maximumDays },
            set: { newValue in
                maximumDays = newValue
                onRetentionChange(retention(count: maximumCount, days: newValue))
            }
        )
    }

    private func retention(count: Int, days: Int) -> ClipboardHistory.Retention {
        ClipboardHistory.Retention(
            maximumCount: count,
            maximumAge: days == 0 ? nil : .seconds(Double(days) * 24 * 60 * 60)
        )
    }
}

extension KeyboardShortcuts.Name {

    /// Opens the searchable picker. No default: a clipboard manager that
    /// claims a global shortcut without being asked will collide with
    /// something, and the collision will be silent.
    static let clipboardPicker = Self("clipboardPicker")
}
