import Defaults
import PerchCore
import SwiftUI

/// The cross-cutting pane: where the island lives and how it responds to you.
/// Module 18 in `docs/FEATURES.md`.
struct GeneralSettingsView: View {

    @Default(.islandScreenPolicy) private var screenPolicy
    @Default(.hoverToExpand) private var hoverToExpand
    @Default(.clickToPin) private var clickToPin
    @Default(.dragToOpenShelf) private var dragToOpenShelf
    @Default(.swipeToSkip) private var swipeToSkip

    var body: some View {
        Form {
            Section {
                Picker("Island lives on", selection: $screenPolicy) {
                    Text("The built-in display").tag("builtIn")
                    Text("The active display").tag("active")
                }
            } footer: {
                Text(
                    """
                    On a Mac without a notch, Perch draws a floating pill \
                    at the top edge instead.
                    """
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section("Gestures") {
                Toggle("Expand on hover", isOn: $hoverToExpand)
                Toggle("Click to keep open", isOn: $clickToPin)
                Toggle("Open the shelf when dragging a file", isOn: $dragToOpenShelf)
                Toggle("Swipe to skip tracks", isOn: $swipeToSkip)
            }

            Section {
                Text(
                    """
                    Perch respects Reduce Motion. With it on, every \
                    transition cross-fades instead of springing.
                    """
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
