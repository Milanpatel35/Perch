import AppKit
import Foundation
import PerchCore

/// Now Playing for Apple Music and Spotify, through their public interfaces.
///
/// **Why only these two.** Since macOS 15.4 MediaRemote refuses third-party
/// apps ("Operation not permitted"), which left the island empty whatever
/// was playing. The supported ways in are each player's own: a distributed
/// notification on every change, and AppleScript for everything else. ADR
/// 0008 records the choice and what it costs — browser tabs are no longer
/// covered.
///
/// **What needs permission, and when.** Hearing the notifications needs
/// none. Reading the position and the artwork, and the transport buttons,
/// talk to the player, and macOS asks once per player the first time that
/// happens — which is while something is already playing and the module is
/// on, never at launch (`CLAUDE.md` §5.3). Refused, the island still shows
/// the track; it just cannot show the position or skip.
///
/// Nothing polls. The one read per change is the answer to that change.
@MainActor
final class PlayerScriptingSource: NowPlayingSourcing {

    /// Always true: the notifications are public on every macOS this app
    /// supports, whether or not either player is installed.
    let isAvailable = true

    private var observers: [NSObjectProtocol] = []
    private var onChange: (@MainActor () -> Void)?

    /// The most recent thing each player said, and when.
    private var latest: [MusicPlayer: (note: PlayerNotification, at: Date)] = [:]

    /// The player whose track is on the island — the one that spoke last.
    private var current: MusicPlayer?

    private let runner = AppleScriptRunner()

    func start(onChange: @escaping @MainActor () -> Void) {
        guard observers.isEmpty else { return }
        self.onChange = onChange

        let center = DistributedNotificationCenter.default()
        for player in MusicPlayer.allCases {
            let observer = center.addObserver(
                forName: Notification.Name(player.notificationName),
                object: nil,
                queue: .main
            ) { [weak self] notification in
                let info = notification.userInfo ?? [:]
                let note = PlayerNotification.parse(player: player, userInfo: info)
                MainActor.assumeIsolated {
                    self?.heard(player, note)
                }
            }
            observers.append(observer)
        }

        // Something may already be playing. Asked only if the player is
        // running, so a Mac with neither open is never asked anything.
        seedFromRunningPlayer()
    }

    func stop() {
        let center = DistributedNotificationCenter.default()
        for observer in observers {
            center.removeObserver(observer)
        }
        observers = []
        latest = [:]
        current = nil
        onChange = nil
    }

    func readSnapshot() async -> NowPlayingSnapshot? {
        guard let current, let (note, at) = latest[current] else { return nil }

        // Spotify says where it is; Music does not, so ask it. A refusal or
        // a timeout reads as "unknown", and the snapshot still shows.
        var position = note.position
        var stamp = at
        if position == nil, isRunning(current) {
            if let seconds = await runner.number("player position", in: current) {
                position = .seconds(seconds)
                stamp = Date()
            }
        }

        let artwork: Data? =
            current == .music && isRunning(.music)
            ? await runner.data("raw data of artwork 1 of current track", in: .music)
            : nil

        return note.snapshot(position: position, at: stamp, artwork: artwork)
    }

    func perform(_ command: NowPlayingCommand) {
        guard let player = current else { return }
        let verb =
            switch command {
            case .togglePlayPause: "playpause"
            case .nextTrack: "next track"
            case .previousTrack: "previous track"
            }
        Task { await runner.run(verb, in: player) }
    }

    func seek(to position: Duration) {
        guard let player = current else { return }
        let seconds =
            Double(position.components.seconds)
            + Double(position.components.attoseconds) / 1e18
        Task { await runner.run("set player position to \(seconds)", in: player) }
    }

    // MARK: - Internals

    private func heard(_ player: MusicPlayer, _ note: PlayerNotification?) {
        if let note {
            latest[player] = (note, Date())
            current = player
        } else {
            latest[player] = nil
            // The player that stopped was the one on the island: fall back
            // to the other if it is still playing, otherwise nothing is.
            if current == player {
                current = latest.first { $0.value.note.state == .playing }?.key
            }
        }
        onChange?()
    }

    private func seedFromRunningPlayer() {
        for player in MusicPlayer.allCases where isRunning(player) {
            Task { [weak self, runner] in
                guard let info = await runner.currentTrack(in: player) else { return }
                self?.heard(player, PlayerNotification.parse(player: player, userInfo: info))
            }
        }
    }

    private func isRunning(_ player: MusicPlayer) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: player.bundleID).isEmpty
    }
}

/// Runs short AppleScript commands against a player, off the main thread,
/// one at a time, and never for long.
///
/// `with timeout of 2 seconds` is the point: an Apple Event to a player that
/// is busy or hung otherwise waits two minutes, and `readSnapshot` must
/// always return.
private final class AppleScriptRunner: @unchecked Sendable {

    private let queue = DispatchQueue(label: "app.perch.nowplaying.applescript")

    func run(_ command: String, in player: MusicPlayer) async {
        _ = await execute("\(command)", in: player)
    }

    func number(_ expression: String, in player: MusicPlayer) async -> Double? {
        await execute("get \(expression)", in: player).flatMap { descriptor in
            descriptor.descriptorType == typeNull ? nil : descriptor.doubleValue
        }
    }

    func data(_ expression: String, in player: MusicPlayer) async -> Data? {
        await execute("get \(expression)", in: player).flatMap { descriptor in
            let data = descriptor.data
            return data.isEmpty ? nil : data
        }
    }

    /// The current track, in the same shape as the player's notification, so
    /// the one parser reads both.
    func currentTrack(in player: MusicPlayer) async -> [AnyHashable: Any]? {
        let script = """
            if player state is stopped then return {"Stopped", "", "", "", 0}
            set t to current track
            return {player state as text, name of t, artist of t, album of t, duration of t}
            """
        guard let list = await execute(script, in: player), list.numberOfItems >= 5 else {
            return nil
        }

        let state = list.atIndex(1)?.stringValue ?? "stopped"
        // Music reports duration in seconds; Spotify in milliseconds.
        let rawDuration = list.atIndex(5)?.doubleValue ?? 0
        let milliseconds = player == .music ? rawDuration * 1_000 : rawDuration

        return [
            "Player State": state.capitalized,
            "Name": list.atIndex(2)?.stringValue ?? "",
            "Artist": list.atIndex(3)?.stringValue ?? "",
            "Album": list.atIndex(4)?.stringValue ?? "",
            "Total Time": milliseconds
        ]
    }

    private func execute(_ body: String, in player: MusicPlayer) async -> NSAppleEventDescriptor? {
        let source = """
            with timeout of 2 seconds
                tell application "\(player.scriptingName)"
                    \(body)
                end tell
            end timeout
            """

        return await withCheckedContinuation { continuation in
            queue.async {
                var error: NSDictionary?
                let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
                continuation.resume(returning: error == nil ? result : nil)
            }
        }
    }
}
