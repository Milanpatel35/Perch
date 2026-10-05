import KeyboardShortcuts
import PerchCore
import SwiftUI

/// Every global shortcut Perch has, in one list.
///
/// Each module's pane still has its own recorder; this is the same setting,
/// gathered where somebody looking for "the keyboard" will look first.
public struct KeyboardShortcutsSettings: View {

    @State private var applied: Int?

    public init() {}

    public var body: some View {
        Form {
            Section {
                ForEach(SuggestedShortcuts.all, id: \.name.rawValue) { shortcut in
                    KeyboardShortcuts.Recorder(shortcut.title, name: shortcut.name)
                }
            } footer: {
                Text(
                    """
                    A module's shortcut works while that module is switched on. \
                    Open Perch always works.
                    """
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Button("Use suggested shortcuts") {
                        applied = SuggestedShortcuts.apply()
                    }
                    if let applied {
                        Text(
                            applied == 0
                                ? "Every shortcut was already set — nothing changed."
                                : "Set \(applied) shortcut\(applied == 1 ? "" : "s")."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            } footer: {
                Text(
                    """
                    ⌃⌥P opens Perch, ⌃⌥V the clipboard, ⌃⌥F the focus timer, \
                    ⌃⌥M the camera and ⌃⌥J the current meeting. Only shortcuts \
                    you have not set are filled in; yours are left alone. Perch \
                    never takes a key you did not ask for.
                    """
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section("On the island") {
                Text(
                    """
                    Open Perch from the keyboard, then press the letter shown on \
                    a button: C for the clipboard, A to capture an area, and so on. \
                    Escape closes it.
                    """
                )
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
    }
}

/// The shortcuts "Use suggested shortcuts" fills in.
///
/// ⌃⌥ plus a letter, because macOS and the common apps leave that space
/// alone — ⌃⌥Space, the obvious one, already switches input source.
@MainActor
public enum SuggestedShortcuts {

    struct Entry {
        let name: KeyboardShortcuts.Name
        let title: LocalizedStringKey
        let shortcut: KeyboardShortcuts.Shortcut
    }

    static let all: [Entry] = [
        Entry(
            name: .openPerch, title: "Open Perch",
            shortcut: .init(.p, modifiers: [.control, .option])),
        Entry(
            name: .clipboardPicker, title: "Clipboard history",
            shortcut: .init(.v, modifiers: [.control, .option])),
        Entry(
            name: .focusTimer, title: "Start or pause focus",
            shortcut: .init(.f, modifiers: [.control, .option])),
        Entry(
            name: .cameraPreview, title: "Show the camera",
            shortcut: .init(.m, modifiers: [.control, .option])),
        Entry(
            name: .joinMeeting, title: "Join the current meeting",
            shortcut: .init(.j, modifiers: [.control, .option]))
    ]

    /// Fills in every shortcut that is not set, and returns how many. One
    /// the user already chose is never replaced.
    @discardableResult
    public static func apply() -> Int {
        var set = 0
        for entry in all where KeyboardShortcuts.getShortcut(for: entry.name) == nil {
            KeyboardShortcuts.setShortcut(entry.shortcut, for: entry.name)
            set += 1
        }
        return set
    }
}
