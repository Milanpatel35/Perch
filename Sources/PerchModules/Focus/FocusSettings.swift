import Defaults
import KeyboardShortcuts
import PerchCore
import SwiftUI

extension PomodoroTimer.Configuration: Defaults.Serializable {}

extension Defaults.Keys {

    /// 25/5/15, four sessions to the long break — the Pomodoro technique's
    /// own numbers, and what every other app defaults to.
    static let pomodoroConfiguration = Key<PomodoroTimer.Configuration>(
        "focus.configuration",
        default: PomodoroTimer.Configuration()
    )
}

/// The Focus pane in Preferences.
struct FocusSettingsView: View {

    let configuration: PomodoroTimer.Configuration
    let sessionsToday: Int
    let totalSessions: Int
    let streakDays: Int
    let onChange: (PomodoroTimer.Configuration) -> Void

    private static let workChoices = [15, 20, 25, 30, 45, 50, 60]
    private static let shortBreakChoices = [3, 5, 10, 15]
    private static let longBreakChoices = [10, 15, 20, 30]

    var body: some View {
        Form {
            Section("Lengths") {
                picker("Focus", minutes: Self.workChoices, current: configuration.work) {
                    var updated = configuration
                    updated.work = .seconds($0 * 60)
                    onChange(updated)
                }
                picker(
                    "Short break",
                    minutes: Self.shortBreakChoices,
                    current: configuration.shortBreak
                ) {
                    var updated = configuration
                    updated.shortBreak = .seconds($0 * 60)
                    onChange(updated)
                }
                picker(
                    "Long break",
                    minutes: Self.longBreakChoices,
                    current: configuration.longBreak
                ) {
                    var updated = configuration
                    updated.longBreak = .seconds($0 * 60)
                    onChange(updated)
                }
            }

            Section {
                Picker("Long break after", selection: cycleBinding) {
                    ForEach([2, 3, 4, 5, 6], id: \.self) { count in
                        Text("\(count) sessions").tag(count)
                    }
                }
            } footer: {
                Text("A change applies to the next phase, never to one already running.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Shortcut") {
                KeyboardShortcuts.Recorder("Start or pause", name: .focusTimer)
            }

            Section {
                LabeledContent("Today", value: "\(sessionsToday)")
                LabeledContent("Streak", value: streakDays == 1 ? "1 day" : "\(streakDays) days")
                LabeledContent("All time", value: "\(totalSessions)")
            } header: {
                Text("Sessions")
            } footer: {
                Text(
                    """
                    The streak counts days with at least one finished focus \
                    session, not sessions. Four on Tuesday is one day.
                    """
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section {
                Text(
                    """
                    Turning on a macOS Focus for the length of a session is \
                    not here. There is no interface for setting one — the \
                    entitlement belongs to Apple's own apps — so Perch can \
                    read which Focus is on, and show it, but not change it. \
                    docs/FEATURES.md §4 records it.
                    """
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    /// Bindings that report on set, rather than `onChange` — deprecated on
    /// newer SDKs, and its replacement does not exist on the macOS 13 floor.
    private func picker(
        _ label: String,
        minutes choices: [Int],
        current: Duration,
        set: @escaping (Int) -> Void
    ) -> some View {
        let selection = Binding<Int>(
            get: { Int(current.seconds / 60) },
            set: { set($0) }
        )

        return Picker(label, selection: selection) {
            ForEach(choices, id: \.self) { minutes in
                Text("\(minutes) min").tag(minutes)
            }
        }
    }

    private var cycleBinding: Binding<Int> {
        Binding(
            get: { configuration.sessionsBeforeLongBreak },
            set: { newValue in
                var updated = configuration
                updated.sessionsBeforeLongBreak = newValue
                onChange(updated)
            }
        )
    }
}
