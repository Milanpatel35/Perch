import AppKit
import Foundation
import PerchCore

/// The bridge to `MediaRemote`, macOS's system-wide now-playing service.
///
/// **Why this is a fifth file in a module folder.** `CLAUDE.md` §4 asks for
/// four. This is the one piece of the app that talks to a private framework,
/// and it is worth having it alone in a file where it can be read, audited
/// and replaced without touching the module around it.
///
/// **Why a private framework at all.** There is no public API on macOS that
/// reports what another application is playing. `MPNowPlayingInfoCenter`
/// publishes your own app's state and reads nobody else's. Scripting
/// individual players covers Music and Spotify and nothing else — not a
/// browser tab, which is where most listening now happens (the probe that
/// informed this file found Chrome holding the session).
///
/// **How the risk is contained.** Everything is resolved by `dlsym` at
/// activation, nothing is linked, and every entry point is optional. If a
/// future macOS removes or restricts a symbol, `isAvailable` goes false, the
/// module reports itself unavailable, and the rest of Perch is unaffected.
/// Nothing here can fail at launch, because nothing here runs at launch.
@MainActor
final class MediaRemoteBridge {

    /// Commands, as `MRMediaRemoteSendCommand` numbers them.
    enum Command: Int {
        case play = 0
        case pause = 1
        case togglePlayPause = 2
        case nextTrack = 4
        case previousTrack = 5
    }

    private typealias GetInfo =
        @convention(c) (DispatchQueue, @escaping ([String: Any]) -> Void) -> Void
    private typealias Register = @convention(c) (DispatchQueue) -> Void
    private typealias Unregister = @convention(c) () -> Void
    private typealias Send = @convention(c) (Int, [String: Any]?) -> Bool
    private typealias SetElapsed = @convention(c) (Double) -> Void
    private typealias GetClient =
        @convention(c) (DispatchQueue, @escaping (AnyObject?) -> Void) -> Void
    private typealias ClientBundleID = @convention(c) (AnyObject) -> String?

    private static let frameworkPath =
        "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote"

    /// The notifications MediaRemote posts. Names are its own, and are read
    /// as plain strings rather than linked constants for the same reason the
    /// functions are: a missing one must degrade, not fail to launch.
    static let infoDidChange =
        Notification.Name("kMRMediaRemoteNowPlayingInfoDidChangeNotification")
    static let isPlayingDidChange = Notification.Name(
        "kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification"
    )
    static let applicationDidChange = Notification.Name(
        "kMRMediaRemoteNowPlayingApplicationDidChangeNotification"
    )

    private var handle: UnsafeMutableRawPointer?
    private var getInfo: GetInfo?
    private var register: Register?
    private var unregister: Unregister?
    private var send: Send?
    private var setElapsed: SetElapsed?
    private var getClient: GetClient?
    private var clientBundleID: ClientBundleID?

    private var isRegistered = false

    /// The queue MediaRemote calls back on. Its own, so a slow decode of a
    /// megabyte of artwork never lands on the main thread.
    private let callbackQueue = DispatchQueue(
        label: "app.perch.mediaremote",
        qos: .utility
    )

    /// Whether the framework and the symbols this module needs are all
    /// present. False means the module reports itself unavailable rather
    /// than silently showing nothing.
    var isAvailable: Bool { getInfo != nil }

    // MARK: - Lifecycle

    /// Opens the framework and resolves the symbols. Called on activation,
    /// never at launch.
    func open() {
        if handle == nil {
            handle = dlopen(Self.frameworkPath, RTLD_LAZY)
        }
        guard handle != nil else { return }

        getInfo = symbol("MRMediaRemoteGetNowPlayingInfo")
        register = symbol("MRMediaRemoteRegisterForNowPlayingNotifications")
        unregister = symbol("MRMediaRemoteUnregisterForNowPlayingNotifications")
        send = symbol("MRMediaRemoteSendCommand")
        setElapsed = symbol("MRMediaRemoteSetElapsedTime")
        getClient = symbol("MRMediaRemoteGetNowPlayingClient")
        clientBundleID = symbol("MRNowPlayingClientGetBundleIdentifier")
    }

    /// Starts MediaRemote posting notifications. Idempotent.
    func startListening() {
        guard !isRegistered, let register else { return }
        register(callbackQueue)
        isRegistered = true
    }

    /// Stops them. Part of costing nothing when off (TC-MED-007).
    func stopListening() {
        guard isRegistered else { return }
        unregister?()
        isRegistered = false
    }

    /// Makes the bridge inert. After this `isAvailable` is false until
    /// `open()` is called again.
    ///
    /// **The handle is deliberately not `dlclose`d.** MediaRemote installs
    /// process-wide state when it is registered for notifications, and
    /// unloading the image out from under that crashes on a second
    /// enable/disable cycle — which is a thing a person does by flicking a
    /// switch in Preferences twice, and which macOS 14 does reliably enough
    /// for CI to catch it.
    ///
    /// Keeping one handle to a system framework for the life of the process
    /// costs nothing: the image is shared, it is already resident for every
    /// other process using it, and none of it runs. What actually matters for
    /// "an off module costs nothing" is below — the registration is dropped
    /// and every function pointer goes, so there is no path back into the
    /// framework at all (TC-MED-007).
    func close() {
        stopListening()
        getInfo = nil
        register = nil
        unregister = nil
        send = nil
        setElapsed = nil
        getClient = nil
        clientBundleID = nil
    }

    // MARK: - Reading

    /// Reads what is playing, and translates it before handing it back.
    ///
    /// The translation happens on MediaRemote's callback queue rather than
    /// on the main one, for two reasons. The dictionary it answers with is
    /// `[String: Any]` and so cannot cross an isolation boundary at all; and
    /// it carries the artwork, which can be a megabyte and has no business
    /// being copied on the thread drawing the island.
    ///
    /// Never call this *on* the main queue and then wait for it. MediaRemote
    /// answers on the queue you hand it, and handing it one you are blocking
    /// deadlocks — which is exactly what the first probe of this API did.
    func readNowPlaying(
        sourceBundleID: String?,
        _ completion: @escaping @Sendable (NowPlayingSnapshot?) -> Void
    ) {
        guard let getInfo else {
            completion(nil)
            return
        }
        getInfo(callbackQueue) { info in
            completion(
                NowPlayingSnapshot(
                    mediaRemoteInfo: info,
                    sourceBundleID: sourceBundleID
                )
            )
        }
    }

    /// The bundle identifier of whichever app currently owns playback.
    ///
    /// This is what makes TC-MED-008 work: with two players running, the
    /// island follows the one the *system* considers active rather than
    /// guessing.
    func readOwningBundleID(_ completion: @escaping @Sendable (String?) -> Void) {
        guard let getClient, let clientBundleID else {
            completion(nil)
            return
        }
        getClient(callbackQueue) { client in
            completion(client.flatMap { clientBundleID($0) })
        }
    }

    // MARK: - Writing

    @discardableResult
    func perform(_ command: Command) -> Bool {
        send?(command.rawValue, nil) ?? false
    }

    /// Seeks. The scrubber's drag ends here.
    func seek(to position: Duration) {
        setElapsed?(position.seconds)
    }

    // MARK: - Symbols

    private func symbol<T>(_ name: String) -> T? {
        guard let handle, let pointer = dlsym(handle, name) else { return nil }
        return unsafeBitCast(pointer, to: T.self)
    }
}

// MARK: - MediaRemote's dictionary, translated

extension NowPlayingSnapshot {

    /// Builds a snapshot from MediaRemote's info dictionary.
    ///
    /// Every key is optional and every value is loosely typed, because this
    /// is a dictionary from a private framework populated by whichever app
    /// happens to be playing. A browser reports less than Music.app does; a
    /// live stream reports no duration at all. Nothing here may trap
    /// (TC-MED-004).
    init?(mediaRemoteInfo info: [String: Any], sourceBundleID: String?) {
        let title = info["kMRMediaRemoteNowPlayingInfoTitle"] as? String ?? ""
        let artist = info["kMRMediaRemoteNowPlayingInfoArtist"] as? String ?? ""
        let album = info["kMRMediaRemoteNowPlayingInfoAlbum"] as? String ?? ""

        // Nothing identifiable means nothing is playing, whatever else the
        // dictionary contains.
        guard !title.isEmpty || !artist.isEmpty else { return nil }

        let rate =
            (info["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? NSNumber)?
            .doubleValue ?? 0
        let elapsed =
            (info["kMRMediaRemoteNowPlayingInfoElapsedTime"] as? NSNumber)?
            .doubleValue ?? 0
        let duration = (info["kMRMediaRemoteNowPlayingInfoDuration"] as? NSNumber)?
            .doubleValue

        // The elapsed time is true as of this timestamp, not as of now. Using
        // `now` instead makes the scrubber jump backwards every time the
        // island reopens after a pause.
        let asOf = info["kMRMediaRemoteNowPlayingInfoTimestamp"] as? Date ?? .now

        self.init(
            title: title,
            artist: artist,
            album: album,
            progress: PlaybackProgress(
                elapsed: .seconds(max(0, elapsed)),
                rate: rate,
                asOf: asOf,
                duration: .seconds(validating: duration)
            ),
            artwork: info["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data,
            sourceBundleID: sourceBundleID,
            // Left unset here on purpose. Resolving an app's display name
            // means asking AppKit, and this runs on MediaRemote's own queue.
            // `NowPlayingService` fills it in on the main actor.
            sourceName: nil
        )
    }
}
