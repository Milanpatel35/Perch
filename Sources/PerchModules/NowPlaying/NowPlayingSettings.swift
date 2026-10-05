import Defaults
import PerchCore
import SwiftUI

extension Defaults.Keys {

    /// The live audio visualiser beside the notch. On by default — it is the
    /// thing that makes the island feel alive — but it stops dead on pause,
    /// because a perpetual animation is a perpetual wakeup (`CLAUDE.md` §5.1).
    static let nowPlayingVisualiser = Key<Bool>(
        "nowPlaying_visualiser",
        default: true
    )

    /// A two-second peek when the track changes.
    static let nowPlayingSneakPeek = Key<Bool>(
        "nowPlaying_sneakPeek",
        default: true
    )

    /// Which app owns the island when more than one is playing. Empty means
    /// "whichever the system says is active", which is almost always right.
    static let nowPlayingPreferredSource = Key<String>(
        "nowPlaying_preferredSource",
        default: ""
    )
}

/// The Now Playing pane in Preferences.
struct NowPlayingSettingsView: View {

    @Default(.nowPlayingVisualiser) private var visualiser
    @Default(.nowPlayingSneakPeek) private var sneakPeek
    @Default(.nowPlayingPreferredSource) private var preferredSource
    @Default(.nowPlayingAllApps) private var allApps

    /// Apps seen playing this session.
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
                    Text("Whichever changed last").tag("")
                    ForEach(knownSources) { source in
                        Text(source.name).tag(source.bundleID)
                    }
                }
                .pickerStyle(.radioGroup)
            }

            Section {
                Toggle("Show music from every app, browsers included", isOn: $allApps)
                Text(
                    allApps
                        ? """
                        Chrome, Safari, Prime Video, YouTube, Podcasts — anything \
                        that tells macOS it is playing. Since macOS 15.4 only \
                        Apple's own programs may ask what is playing, so Perch \
                        asks through Apple's perl, with a small helper of its own \
                        that runs while this module is on. It reads, and sends \
                        play, pause and skip; it makes no network request. If \
                        macOS refuses it, Perch goes back to Music and Spotify.
                        """
                        : """
                        Apple Music and Spotify only, asked directly. The first \
                        time a song plays, macOS asks whether Perch may talk to \
                        the player — that is for the position and the buttons.
                        """
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("Which apps")
            } footer: {
                Text("Takes effect the next time Now Playing is switched on.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
