import Defaults
import PerchCore
import SwiftUI

extension Defaults.Keys {

    /// The live audio visualiser beside the notch. On by default — it is the
    /// thing that makes the island feel alive — but it stops dead on pause,
    /// because a perpetual animation is a perpetual wakeup (`CLAUDE.md` §5.1).
    static let nowPlayingVisualiser = Key<Bool>(
        "nowPlaying.visualiser",
        default: true
    )

    /// A two-second peek when the track changes.
    static let nowPlayingSneakPeek = Key<Bool>(
        "nowPlaying.sneakPeek",
        default: true
    )

    /// Which app owns the island when more than one is playing. Empty means
    /// "whichever the system says is active", which is almost always right.
    static let nowPlayingPreferredSource = Key<String>(
        "nowPlaying.preferredSource",
        default: ""
    )
}

/// The Now Playing pane in Preferences.
struct NowPlayingSettingsView: View {

    @Default(.nowPlayingVisualiser) private var visualiser
    @Default(.nowPlayingSneakPeek) private var sneakPeek
    @Default(.nowPlayingPreferredSource) private var preferredSource

    /// Apps seen holding the media session this session. Discovered, not
    /// hardcoded — a browser tab is as valid a source as Music.app.
    let knownSources: [NowPlayingSource]

    var body: some View {
        Form {
            Section {
                Toggle("Show the audio visualiser", isOn: $visualiser)
                Toggle("Peek when the track changes", isOn: $sneakPeek)
            } footer: {
                Text("The visualiser stops the moment playback pauses.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("When more than one app is playing") {
                Picker("Follow", selection: $preferredSource) {
                    Text("Whichever macOS says is active").tag("")
                    ForEach(knownSources) { source in
                        Text(source.name).tag(source.bundleID)
                    }
                }
                .pickerStyle(.radioGroup)
            }
        }
        .formStyle(.grouped)
    }
}

/// An app that has held the media session.
struct NowPlayingSource: Identifiable, Hashable, Sendable {
    let bundleID: String
    let name: String

    var id: String { bundleID }
}
