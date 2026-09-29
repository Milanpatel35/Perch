import Foundation

/// A music player that says what it is playing.
///
/// Apple Music and Spotify both post a *distributed notification* on every
/// track change, play, pause and stop, with the track in its `userInfo`.
/// That is public, needs no permission and costs nothing between changes —
/// which is why these two are the players Perch supports since macOS 15.4
/// closed MediaRemote to third-party apps (ADR 0008).
public enum MusicPlayer: String, CaseIterable, Sendable, Codable {
    case music
    case spotify

    public var bundleID: String {
        switch self {
        case .music: "com.apple.Music"
        case .spotify: "com.spotify.client"
        }
    }

    /// The name AppleScript addresses it by.
    public var scriptingName: String {
        switch self {
        case .music: "Music"
        case .spotify: "Spotify"
        }
    }

    public var displayName: String {
        switch self {
        case .music: String(localized: "Music")
        case .spotify: String(localized: "Spotify")
        }
    }

    /// The distributed notification it posts.
    public var notificationName: String {
        switch self {
        case .music: "com.apple.Music.playerInfo"
        case .spotify: "com.spotify.client.PlaybackStateChanged"
        }
    }

    public init?(notificationName: String) {
        guard let player = Self.allCases.first(where: { $0.notificationName == notificationName })
        else { return nil }
        self = player
    }
}

/// What one of those notifications said.
public struct PlayerNotification: Equatable, Sendable {

    public enum State: Equatable, Sendable {
        case playing
        case paused
        case stopped
    }

    public let player: MusicPlayer
    public let state: State
    public let title: String
    public let artist: String
    public let album: String
    public let duration: Duration?

    /// Only Spotify says where it has got to. Music's notification carries no
    /// position, so the source asks Music for it separately.
    public let position: Duration?

    public init(
        player: MusicPlayer,
        state: State,
        title: String,
        artist: String = "",
        album: String = "",
        duration: Duration? = nil,
        position: Duration? = nil
    ) {
        self.player = player
        self.state = state
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.position = position
    }

    /// Reads a notification's `userInfo`.
    ///
    /// Tolerant by design: the keys are each app's own and undocumented, so
    /// every field is optional except the state. A stop, or anything without
    /// a title, means nothing is playing.
    public static func parse(player: MusicPlayer, userInfo: [AnyHashable: Any]) -> Self? {
        let state: State =
            switch (userInfo["Player State"] as? String)?.lowercased() {
            case "playing": .playing
            case "paused": .paused
            default: .stopped
            }

        guard state != .stopped,
            let title = (userInfo["Name"] as? String)?.trimmingCharacters(in: .whitespaces),
            !title.isEmpty
        else { return nil }

        // Music reports "Total Time" and Spotify "Duration", both in
        // milliseconds. Spotify's "Playback Position" is in seconds.
        let milliseconds = number(userInfo["Total Time"]) ?? number(userInfo["Duration"])
        let duration = milliseconds.flatMap { $0 > 0 ? Duration.milliseconds(Int64($0)) : nil }
        let position = number(userInfo["Playback Position"]).map { Duration.seconds($0) }

        return Self(
            player: player,
            state: state,
            title: title,
            artist: userInfo["Artist"] as? String ?? "",
            album: userInfo["Album"] as? String ?? "",
            duration: duration,
            position: position
        )
    }

    /// The snapshot the rest of the module works with.
    ///
    /// `position` is the best known elapsed time — the notification's own,
    /// or one read from the player, or zero at the start of a track.
    public func snapshot(
        position known: Duration?,
        at now: Date,
        artwork: Data? = nil
    ) -> NowPlayingSnapshot {
        NowPlayingSnapshot(
            title: title,
            artist: artist,
            album: album,
            progress: PlaybackProgress(
                elapsed: known ?? position ?? .zero,
                rate: state == .playing ? 1 : 0,
                asOf: now,
                duration: duration
            ),
            artwork: artwork,
            sourceBundleID: player.bundleID,
            sourceName: player.displayName
        )
    }

    private static func number(_ value: Any?) -> Double? {
        switch value {
        case let number as NSNumber: number.doubleValue
        case let double as Double: double
        case let int as Int: Double(int)
        case let string as String: Double(string)
        default: nil
        }
    }
}
