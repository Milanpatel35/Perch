import Defaults
import PerchCore
import SwiftUI

extension Defaults.Keys {

    /// Empty the shelf when Perch quits.
    ///
    /// **Off by default, deliberately.** A shelf that empties itself without
    /// being asked has lost somebody's file, and they will not know where it
    /// went (`docs/FEATURES.md` §2, TC-SHF-008).
    static let shelfClearOnQuit = Key<Bool>("shelf.clearOnQuit", default: false)
}

/// The Shelf pane in Preferences.
struct ShelfSettingsView: View {

    @Default(.shelfClearOnQuit) private var clearOnQuit
    @Default(.dragToOpenShelf) private var dragToOpen

    let itemCount: Int
    let byteCount: Int64
    let directory: URL
    let onClear: () -> Void

    var body: some View {
        Form {
            Section {
                Toggle("Open the shelf when dragging a file to the notch", isOn: $dragToOpen)
                Toggle("Empty the shelf when Perch quits", isOn: $clearOnQuit)
            } footer: {
                Text("Off by default. A shelf that empties itself has lost somebody's file.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Holding") {
                LabeledContent("Items", value: "\(itemCount)")
                LabeledContent("Size", value: byteCount.formattedByteCount)
                LabeledContent("Location") {
                    Button(directory.lastPathComponent) {
                        NSWorkspace.shared.activateFileViewerSelecting([directory])
                    }
                    .buttonStyle(.link)
                }
                Button("Empty the shelf now", role: .destructive, action: onClear)
                    .disabled(itemCount == 0)
            }

            Section {
                Text(
                    """
                    Files are copied into Perch's own folder, never moved. \
                    The originals stay exactly where you dragged them from, \
                    and nothing here leaves your Mac.
                    """
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

extension Int64 {
    /// Sizes, the way Finder writes them.
    var formattedByteCount: String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
    }
}
