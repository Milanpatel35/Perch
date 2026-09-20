import Foundation

/// What is playing, at one moment, from one source.
///
/// A plain value with no reference to a media framework, which is what lets
/// the whole of `TEST-PLAN.md` § MED run without anything playing. `PerchUI`
/// builds these from whichever adapter is available; tests build them by
/// hand.
public struct NowPlayingSnapshot: Sendable {

    public var title: String
    public var artist: String
    public var album: String

    public var progress: PlaybackProgress

    /// Raw artwork bytes, in whatever format the source handed over.
    ///
    /// Deliberately excluded from equality — see `==`. Comparing a megabyte
    /// of JPEG on every tick to decide whether a label changed is the kind of
    /// thing that does not show up until someone's fans come on.
    public var artwork: Data?

    /// Cheap stand-in for the artwork in equality and in view identity.
    public let artworkFingerprint: Int

    /// Bundle identifier of the app that owns playback. Used for the
    /// per-app source switch, and to show whose island it is.
    public var sourceBundleID: String?
    public var sourceName: String?

    public init(
        title: String,
        artist: String = "",
        album: String = "",
        progress: PlaybackProgress,
        artwork: Data? = nil,
        sourceBundleID: String? = nil,
        sourceName: String? = nil
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.progress = progress
        self.artwork = artwork
        self.artworkFingerprint = artwork?.hashValue ?? 0
        self.sourceBundleID = sourceBundleID
        self.sourceName = sourceName
    }

    public var isPlaying: Bool { progress.isAdvancing }

    /// Whether two snapshots describe the same *track*, ignoring where it has
    /// got to.
    ///
    /// This is the test for TC-MED-003: a position update must change content
    /// in place, and only a genuine track change may peek.
    public func isSameTrack(as other: Self) -> Bool {
        title == other.title
            && artist == other.artist
            && album == other.album
            && sourceBundleID == other.sourceBundleID
    }
}

extension NowPlayingSnapshot: Equatable {

    /// Artwork bytes are compared by fingerprint, never byte by byte.
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.title == rhs.title
            && lhs.artist == rhs.artist
            && lhs.album == rhs.album
            && lhs.progress == rhs.progress
            && lhs.artworkFingerprint == rhs.artworkFingerprint
            && lhs.sourceBundleID == rhs.sourceBundleID
            && lhs.sourceName == rhs.sourceName
    }
}
