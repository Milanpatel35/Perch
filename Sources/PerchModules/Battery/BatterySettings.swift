import Defaults
import PerchCore
import SwiftUI

extension Defaults.Keys {

    /// Where the low-battery warning fires. Matches what macOS itself warns
    /// at, so the two do not disagree by a few points and look broken.
    static let batteryLowThreshold = Key<Int>("battery.lowThreshold", default: 20)

    /// Each announcement is individually switchable, the way every HUD is
    /// (`docs/FEATURES.md` §6). Somebody who wants the low warning and
    /// nothing else should not have to switch the module off to get it.
    static let batteryAnnounceLow = Key<Bool>("battery.announceLow", default: true)
    static let batteryAnnouncePowerChanges = Key<Bool>(
        "battery.announcePowerChanges",
        default: true
    )
    static let batteryAnnounceCharged = Key<Bool>(
        "battery.announceCharged",
        default: true
    )
}

/// The Battery pane in Preferences.
struct BatterySettingsView: View {

    @Default(.batteryLowThreshold) private var lowThreshold
    @Default(.batteryAnnounceLow) private var announceLow
    @Default(.batteryAnnouncePowerChanges) private var announcePowerChanges
    @Default(.batteryAnnounceCharged) private var announceCharged

    let power: PowerSnapshot
    let accessories: [AccessoryBattery]
    let onThresholdChange: (Int) -> Void
    let onRefresh: () -> Void

    var body: some View {
        Form {
            Section("Announce") {
                Toggle("Low battery", isOn: $announceLow)
                Toggle("Charger connected or disconnected", isOn: $announcePowerChanges)
                Toggle("Fully charged", isOn: $announceCharged)
            }

            Section {
                Picker("Warn at", selection: thresholdBinding) {
                    ForEach([10, 15, 20, 25, 30], id: \.self) { percentage in
                        Text("\(percentage)%").tag(percentage)
                    }
                }
                .disabled(!announceLow)
            } footer: {
                Text(
                    """
                    Once per discharge cycle. Plugging in rearms it; \
                    the level recovering does not.
                    """
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section("This Mac") {
                if power.isPresent {
                    LabeledContent("Charge", value: "\(power.percentage)%")
                    LabeledContent("Power", value: power.isPluggedIn ? "Wall" : "Battery")
                } else {
                    Text("This Mac has no battery. Accessories are still listed.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                if accessories.isEmpty {
                    Text("Nothing connected is reporting a level.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(accessories) { accessory in
                        LabeledContent(accessory.name, value: accessory.levelSummary)
                    }
                }
                Button("Refresh", action: onRefresh)
            } header: {
                Text("Accessories")
            } footer: {
                Text(
                    """
                    Levels are re-read when something connects or disconnects, \
                    and when the island is about to show them — never on a timer.
                    """
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    /// Written as a binding that reports on set, rather than as `onChange`:
    /// `onChange(of:perform:)` is deprecated on newer SDKs and its
    /// replacement does not exist on the macOS 13 floor this app builds for.
    private var thresholdBinding: Binding<Int> {
        Binding(
            get: { lowThreshold },
            set: { newValue in
                lowThreshold = newValue
                onThresholdChange(newValue)
            }
        )
    }
}

extension AccessoryBattery {

    /// "72% · 68% · 90%" for AirPods, "45%" for a mouse, and nothing at all
    /// for a device that has stopped reporting.
    var levelSummary: String {
        if levels.isSplit {
            let parts = [levels.left, levels.right, levels.caseLevel]
                .compactMap { $0 }
                .map { "\($0)%" }
            return parts.joined(separator: " · ")
        }
        guard let single = levels.single else { return "—" }
        return "\(single)%"
    }
}
