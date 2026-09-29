import AppKit
import Defaults
import PerchCore
import SwiftUI

extension ShortcutFavourites: Defaults.Serializable {}

extension Defaults.Keys {
    static let shortcutFavourites = Key<ShortcutFavourites>(
        "shortcuts_favourites",
        default: ShortcutFavourites()
    )
}

/// The Shortcuts pane in Preferences.
struct ShortcutsSettingsView: View {

    @ObservedObject var service: ShortcutsService

    var body: some View {
        Form {
            favouritesSection
            librarySection
            automationSection
        }
        .formStyle(.grouped)
        // The library is read when somebody looks at it, and at no other
        // time (`CLAUDE.md` §5.1).
        .onAppear { service.refreshLibrary() }
    }

    // MARK: - Favourites

    @ViewBuilder
    private var favouritesSection: some View {
        Section {
            if service.favourites.names.isEmpty {
                Text("None yet. Tick a Shortcut below and it appears on the island.")
                    .foregroundStyle(.secondary)
            }
            ForEach(service.favourites.names, id: \.self) { name in
                HStack {
                    Text(name)
                    if missing.contains(name) {
                        Text("Not in your library").font(.caption).foregroundStyle(.orange)
                    }
                    Spacer()
                    Button {
                        service.moveFavourite(name, by: -1)
                    } label: {
                        Image(systemName: "chevron.up")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(Text("Move \(name) up"))
                    Button {
                        service.setFavourite(name, false)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(Text("Remove \(name)"))
                }
            }
        } header: {
            Text("On the island")
        } footer: {
            Text(
                "Up to \(ShortcutFavourites.capacity), as buttons on the island's home surface."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var missing: [String] {
        service.favourites.missing(from: service.library)
    }

    // MARK: - Library

    @ViewBuilder
    private var librarySection: some View {
        Section {
            if service.isReadingLibrary {
                ProgressView().controlSize(.small)
            } else if service.library.isEmpty {
                Text("No Shortcuts found, or the Shortcuts app could not be read.")
                    .foregroundStyle(.secondary)
            }
            ForEach(service.library, id: \.self) { name in
                Toggle(name, isOn: favouriteBinding(name))
                    .disabled(service.favourites.isFull && !service.favourites.contains(name))
            }
            Button("Read again") { service.refreshLibrary() }
        } header: {
            Text("Your Shortcuts")
        }
    }

    private func favouriteBinding(_ name: String) -> Binding<Bool> {
        Binding(
            get: { service.favourites.contains(name) },
            set: { service.setFavourite(name, $0) }
        )
    }

    // MARK: - Automation

    @ViewBuilder
    private var automationSection: some View {
        Section {
            LabeledContent("Shortcuts app") {
                Text("Show message in island · Add to shelf · Start focus session")
                    .multilineTextAlignment(.trailing)
            }
            copyable("URL", "perch://notify?title=Build%20ok&body=12s")
            copyable("Command line", "ln -s \"\(Self.cliPath)\" /usr/local/bin/perch")

            if let rejection = service.lastRejection {
                LabeledContent("Last request turned away") {
                    Text(String(describing: rejection)).foregroundStyle(.orange)
                }
            }
        } header: {
            Text("Automation")
        } footer: {
            Text(
                """
                A perch:// link can show a message, add a file to the shelf or \
                start a focus session. It cannot run a Shortcut: any web page \
                can open a link, so only your own click on the island runs one. \
                The command-line tool is a short script inside the app; link it \
                onto your PATH to use `perch notify "…"`.
                """
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func copyable(_ label: String, _ value: String) -> some View {
        LabeledContent(label) {
            HStack {
                Text(value)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(value, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text("Copy \(label)"))
            }
        }
    }

    /// The CLI ships inside the app bundle, so its path is wherever the app
    /// is — `/Applications` for most people, not for all.
    static var cliPath: String {
        Bundle.main.resourceURL?.appendingPathComponent("perch").path
            ?? "/Applications/Perch.app/Contents/Resources/perch"
    }
}
