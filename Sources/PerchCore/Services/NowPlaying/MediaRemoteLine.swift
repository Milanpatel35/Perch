import Foundation

/// One line from the Now Playing helper (ADR 0010), read.
///
/// The helper prints a JSON object per change: the track, or `{"empty":
/// true}` when nothing is playing, or `{"error": …}` when MediaRemote
/// refused. Reading it is here, in Core, so every rule about a malformed or
/// partial line is a unit test rather than a guess at what the helper sent.
public enum MediaRemoteLine: Equatable, Sendable {

    case playing(NowPlayingSnapshot)
    case nothing
    case failed(String)

    /// Nil for a line that is not a JSON object at all — skipped rather
    /// than taken to mean anything.
    public init?(_ line: Data, receivedAt now: Date = Date()) {
        guard
            let object = try? JSONSerialization.jsonObject(with: line),
            let fields = object as? [String: Any]
        else { return nil }

        if let error = fields["error"] as? String {
            self = .failed(error)
            return
        }

        guard fields["empty"] as? Bool != true,
            let title = fields["title"] as? String, !title.isEmpty
        else {
            self = .nothing
            return
        }

        let elapsed = (fields["elapsed"] as? Double).map(Duration.seconds) ?? .zero
        let duration = (fields["duration"] as? Double)
            .flatMap { $0 > 0 ? Duration.seconds($0) : nil }
        let isPlaying = fields["playing"] as? Bool ?? false
        // MediaRemote reports the rate a track was *started* at even after a
        // pause in some players, so a stopped player is taken at its word.
        let rate = isPlaying ? (fields["rate"] as? Double).flatMap { $0 > 0 ? $0 : nil } ?? 1 : 0
        // Elapsed is "as of" MediaRemote's timestamp, not as of now.
        let asOf = (fields["timestamp"] as? Double).map(Date.init(timeIntervalSince1970:)) ?? now
        let bundle = (fields["bundle"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let artwork = (fields["artwork"] as? String).flatMap { Data(base64Encoded: $0) }

        self = .playing(
            NowPlayingSnapshot(
                title: title,
                artist: fields["artist"] as? String ?? "",
                album: fields["album"] as? String ?? "",
                progress: PlaybackProgress(
                    elapsed: elapsed, rate: rate, asOf: asOf, duration: duration),
                artwork: artwork,
                sourceBundleID: bundle
            )
        )
    }
}
