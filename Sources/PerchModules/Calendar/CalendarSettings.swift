import Defaults
import KeyboardShortcuts
import PerchCore
import SwiftUI

extension Agenda.Configuration: Defaults.Serializable {}

extension Defaults.Keys {

    static let agendaConfiguration = Key<Agenda.Configuration>(
        "calendar.agenda",
        default: Agenda.Configuration()
    )
}

/// The Calendar pane in Preferences.
struct CalendarSettingsView: View {

    let access: EventKitBridge.Access
    let remindersAccess: EventKitBridge.Access
    let configuration: Agenda.Configuration
    let calendarTitles: [String]
    let reminderCount: Int
    let onChange: (Agenda.Configuration) -> Void
    let onEnableReminders: () -> Void

    private static let leadChoices = [1, 2, 5, 10, 15, 30]

    var body: some View {
        Form {
            accessSection

            Section("Countdown") {
                Picker("Show", selection: leadBinding) {
                    ForEach(Self.leadChoices, id: \.self) { minutes in
                        Text("^[\(minutes) minute](inflect: true) before").tag(minutes)
                    }
                }

                Toggle("Keep it up while the event runs", isOn: showsDuringEventBinding)
                Toggle("Include invitations you have not answered", isOn: showsTentativeBinding)
            }

            if !calendarTitles.isEmpty {
                Section {
                    ForEach(calendarTitles, id: \.self) { title in
                        Toggle(
                            title,
                            isOn: Binding(
                                get: { !configuration.excludedCalendars.contains(title) },
                                set: { isOn in
                                    var updated = configuration
                                    if isOn {
                                        updated.excludedCalendars.remove(title)
                                    } else {
                                        updated.excludedCalendars.insert(title)
                                    }
                                    onChange(updated)
                                }
                            )
                        )
                    }
                } header: {
                    Text("Calendars")
                } footer: {
                    Text("A calendar switched off here is not read at all.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            remindersSection

            Section("Shortcut") {
                KeyboardShortcuts.Recorder("Join the current meeting", name: .joinMeeting)
            }

            Section {
                Text(
                    """
                    Mute, video and leave are driven through the meeting app's own \
                    menu bar, which needs Accessibility. Perch asks for it the first \
                    time you press one of them, never before. Zoom is the one client \
                    this is verified against; Teams and Webex are best effort, and \
                    the controls say so when they cannot find their menus.
                    """
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            } header: {
                Text("Meeting controls")
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Access

    @ViewBuilder
    private var accessSection: some View {
        switch access {
        case .granted:
            EmptyView()

        case .notDetermined:
            Section {
                Text("Perch will ask for calendar access when it next reads your events.")
                    .font(.callout)
            }

        case .denied, .restricted, .writeOnly:
            // TC-CAL-001. An explanation with somewhere to go, not an error.
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(deniedMessage)
                        .font(.callout)

                    Button("Open Privacy Settings…") {
                        if let url = URL(string: Self.privacyPane) {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            } header: {
                Text("Calendar access")
            }
        }
    }

    private static let privacyPane =
        "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars"

    /// Three refusals, three different things to do about them. "Denied"
    /// covering all of them is what makes "but I did grant it" unanswerable
    /// — write-only access looks granted in System Settings (TC-CAL-001).
    private var deniedMessage: String {
        switch access {
        case .writeOnly:
            String(
                localized: """
                    Perch has write-only calendar access, which cannot read your \
                    events. Full access is needed to show the next one.
                    """
            )
        case .restricted:
            String(
                localized: """
                    Calendar access is restricted on this Mac, so the countdown \
                    cannot be shown. Everything else in Perch still works.
                    """
            )
        default:
            String(
                localized: """
                    Calendar access is off, so there is nothing to count down to. \
                    Everything else in Perch still works.
                    """
            )
        }
    }

    // MARK: - Reminders

    @ViewBuilder
    private var remindersSection: some View {
        Section {
            if remindersAccess == .granted {
                LabeledContent("Due soon", value: "\(reminderCount)")
            } else {
                Button("Show reminders in the island…", action: onEnableReminders)
            }
        } header: {
            Text("Reminders")
        } footer: {
            Text("Asked for separately, and only if you want it.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Bindings

    private var leadBinding: Binding<Int> {
        Binding(
            get: { Int(configuration.leadTime.seconds / 60) },
            set: { minutes in
                var updated = configuration
                updated.leadTime = .seconds(minutes * 60)
                onChange(updated)
            }
        )
    }

    private var showsDuringEventBinding: Binding<Bool> {
        Binding(
            get: { configuration.showsDuringEvent },
            set: { isOn in
                var updated = configuration
                updated.showsDuringEvent = isOn
                onChange(updated)
            }
        )
    }

    private var showsTentativeBinding: Binding<Bool> {
        Binding(
            get: { configuration.showsTentative },
            set: { isOn in
                var updated = configuration
                updated.showsTentative = isOn
                onChange(updated)
            }
        )
    }
}
