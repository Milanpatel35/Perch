import AppKit
import PerchCore
import SwiftUI

/// The first run: what Perch is, what it should do, and whether it opens at
/// login. Three screens and no more (`docs/PLAN.md` §3.1).
///
/// It asks for nothing. A preset only switches modules on; each module asks
/// for its own permission when it needs one, with its own reason
/// (`CLAUDE.md` §5.3). What the first run does is say so before anybody picks.
public struct FirstRunView: View {

    private enum Step: Int, CaseIterable {
        case welcome
        case preset
        case finish
    }

    @ObservedObject private var switchboard: ModuleSwitchboard
    @ObservedObject private var launchAtLogin: LaunchAtLogin

    private let built: Set<ModuleID>
    private let onOpenSettings: () -> Void
    private let onDone: () -> Void

    @State private var step: Step = .welcome

    /// `nil` keeps whatever is switched on now — the defaults on a fresh
    /// install, somebody's own choices on an upgrade.
    @State private var preset: ModulePreset?

    public init(
        switchboard: ModuleSwitchboard,
        launchAtLogin: LaunchAtLogin,
        built: Set<ModuleID>,
        onOpenSettings: @escaping () -> Void,
        onDone: @escaping () -> Void
    ) {
        self.switchboard = switchboard
        self.launchAtLogin = launchAtLogin
        self.built = built
        self.onOpenSettings = onOpenSettings
        self.onDone = onDone
    }

    public var body: some View {
        VStack(spacing: 0) {
            Group {
                switch step {
                case .welcome: welcome
                case .preset: presets
                case .finish: finish
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 32)
            .padding(.top, 28)

            Divider()
            footer
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
        }
        .frame(width: 600, height: 540)
    }

    // MARK: - 1. Welcome

    private var welcome: some View {
        VStack(spacing: 18) {
            Image(nsImage: NSImage(named: "AppIcon") ?? NSImage())
                .resizable()
                .scaledToFit()
                .frame(width: 72, height: 72)
                .accessibilityHidden(true)

            Text("Perch lives in your notch")
                .font(.title.weight(.semibold))

            VStack(alignment: .leading, spacing: 14) {
                Gesture(symbol: "cursorarrow.motionlines", text: "Point at the notch to open it.")
                Gesture(
                    symbol: "cursorarrow.click",
                    text: "Click to keep it open. Click again to close it."
                )
                Gesture(symbol: "doc.on.doc", text: "Drag a file to it to hold it on the shelf.")
                Gesture(
                    symbol: "menubar.rectangle",
                    text: "Settings are in Perch's menu bar icon, beside the clock."
                )
            }
            .frame(maxWidth: 400, alignment: .leading)
            .padding(.top, 6)

            Spacer()

            Text("Free and open source, every feature. No account, no licence key, no telemetry.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - 2. Presets

    private var presets: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("What should it do?")
                .font(.title2.weight(.semibold))
            Text(
                """
                Pick a starting point, or skip to keep the defaults. Every \
                module has its own switch in Settings.
                """
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(ModulePreset.allCases, id: \.self) { candidate in
                    PresetCard(
                        preset: candidate,
                        built: built,
                        isSelected: preset == candidate
                    ) {
                        preset = (preset == candidate) ? nil : candidate
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - 3. Finish

    private var finish: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("One last thing")
                .font(.title2.weight(.semibold))

            VStack(alignment: .leading, spacing: 6) {
                Toggle(
                    "Open Perch at login",
                    isOn: Binding(
                        get: { launchAtLogin.isEnabled },
                        set: { launchAtLogin.setEnabled($0) }
                    )
                )
                .toggleStyle(.switch)
                .disabled(!launchAtLogin.isAvailable)

                LaunchAtLoginNote(launchAtLogin: launchAtLogin)
            }

            let asks = askedFor
            if !asks.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("macOS will ask you about these when the module first needs them:")
                        .font(.callout)
                    ForEach(asks, id: \.self) { permission in
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(permission.displayName).font(.callout.weight(.medium))
                                Text(permission.reason)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        } icon: {
                            Image(systemName: permission.symbolName)
                        }
                    }
                }
                .padding(.top, 6)
            } else {
                Text("Nothing you switched on needs a permission.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// What is switched on now asks for — after the preset was applied, so
    /// it describes the island somebody is about to use.
    private var askedFor: [ModulePermission] {
        let enabled = Set(built.filter(switchboard.isEnabled))
        let asked = Set(enabled.flatMap(\.permissions))
        return ModulePermission.allCases.filter(asked.contains)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            HStack(spacing: 6) {
                ForEach(Step.allCases, id: \.self) { each in
                    Circle()
                        .fill(each == step ? Color.primary : Color.secondary.opacity(0.35))
                        .frame(width: 6, height: 6)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Step \(step.rawValue + 1) of \(Step.allCases.count)"))

            Spacer()

            if step != .welcome {
                Button("Back") { move(by: -1) }
            }

            switch step {
            case .welcome:
                Button("Continue") { move(by: 1) }
                    .keyboardShortcut(.defaultAction)
            case .preset:
                Button(preset == nil ? "Skip" : "Continue") {
                    if let preset {
                        switchboard.apply(preset.modules(built: built), among: built)
                    }
                    move(by: 1)
                }
                .keyboardShortcut(.defaultAction)
            case .finish:
                Button("Open Settings") {
                    onDone()
                    onOpenSettings()
                }
                Button("Done") { onDone() }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func move(by offset: Int) {
        guard let next = Step(rawValue: step.rawValue + offset) else { return }
        step = next
    }
}

private struct Gesture: View {

    let symbol: String
    let text: String

    var body: some View {
        Label {
            Text(text).font(.body)
        } icon: {
            Image(systemName: symbol)
                .frame(width: 22)
                .foregroundStyle(.secondary)
        }
    }
}

private struct PresetCard: View {

    let preset: ModulePreset
    let built: Set<ModuleID>
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: preset.symbolName)
                        .font(.system(size: 16))
                    Text(preset.displayName)
                        .font(.headline)
                    Spacer()
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                }

                Text(preset.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)

                Text(askLine)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 128, alignment: .topLeading)
            .contentShape(RoundedRectangle(cornerRadius: 10))
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.primary.opacity(isSelected ? 0.08 : 0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(
                        isSelected ? Color.accentColor : Color.primary.opacity(0.1),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var askLine: String {
        let asks = preset.permissions(built: built)
        guard !asks.isEmpty else { return String(localized: "Asks for no permissions") }
        let names = asks.map(\.displayName).joined(separator: ", ")
        return String(localized: "May ask for: \(names)")
    }
}

// MARK: - Words

extension ModulePreset {

    var displayName: String {
        switch self {
        case .music: String(localized: "Music")
        case .work: String(localized: "Work")
        case .everything: String(localized: "Everything")
        case .justHideTheNotch: String(localized: "Just hide the notch")
        }
    }

    var symbolName: String {
        switch self {
        case .music: "music.note"
        case .work: "briefcase"
        case .everything: "square.grid.2x2"
        case .justHideTheNotch: "rectangle.topthird.inset.filled"
        }
    }

    var summary: String {
        switch self {
        case .music:
            String(localized: "What's playing, the volume and brightness, and your batteries.")
        case .work:
            String(
                localized: """
                    Adds the shelf, clipboard history, a focus timer, your next \
                    meeting and notifications.
                    """
            )
        case .everything:
            String(
                localized: "Every module in this version, camera and system monitor included."
            )
        case .justHideTheNotch:
            String(
                localized: "A black bar behind the menu bar so the notch disappears. Nothing else."
            )
        }
    }
}

extension ModulePermission {

    var displayName: String {
        switch self {
        case .calendar: String(localized: "Calendar")
        case .accessibility: String(localized: "Accessibility")
        case .camera: String(localized: "Camera")
        case .location: String(localized: "Location")
        case .microphone: String(localized: "Microphone")
        case .screenRecording: String(localized: "Screen Recording")
        }
    }

    var symbolName: String {
        switch self {
        case .calendar: "calendar"
        case .accessibility: "accessibility"
        case .camera: "camera"
        case .location: "location"
        case .microphone: "mic"
        case .screenRecording: "rectangle.dashed.badge.record"
        }
    }

    var reason: String {
        switch self {
        case .calendar:
            String(
                localized: """
                    To show your next meeting and its join button. Read on your \
                    Mac, never sent anywhere.
                    """
            )
        case .accessibility:
            String(
                localized: """
                    To mirror notification banners and to press mute in a call's \
                    menu. Asked when you first use them.
                    """
            )
        case .camera:
            String(
                localized: """
                    Only when you open the camera preview. No frame is ever saved \
                    unless you take a snapshot.
                    """
            )
        case .location:
            String(localized: "Optional, for local weather. You can type a city instead.")
        case .microphone:
            String(localized: "Only while you dictate.")
        case .screenRecording:
            String(localized: "Only when you take a screenshot.")
        }
    }
}
