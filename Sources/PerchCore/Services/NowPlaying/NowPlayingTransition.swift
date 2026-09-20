import Foundation

/// What the island should do about a change in what is playing.
///
/// Pure, and separated from the adapter on purpose. The rule that matters
/// here — a track change peeks, a position update does not — is the
/// difference between an island that tells you something and an island that
/// flashes at you every second (TC-MED-003). It is worth being able to test
/// it without anything playing.
public enum NowPlayingTransition: Equatable, Sendable {

    /// Nothing worth redrawing.
    case unchanged

    /// Same track, new detail: position moved, artwork arrived late, the
    /// title was corrected. Update content in place; do not re-present.
    case updateInPlace

    /// A different track. Worth a two-second sneak peek
    /// (`docs/FEATURES.md` §1).
    case peek

    /// Playback stopped, or the last source went away. Take the island back.
    case withdraw

    /// Decides the transition between two snapshots.
    ///
    /// - Parameters:
    ///   - old: what the island is currently showing, if anything.
    ///   - new: what the source now reports, or `nil` if nothing is playing.
    public static func between(
        _ old: NowPlayingSnapshot?,
        _ new: NowPlayingSnapshot?
    ) -> Self {
        switch (old, new) {
        case (_, .none):
            return .withdraw

        case (.none, .some(let new)):
            // A track that is already paused when Perch starts, or when the
            // module is switched on, must not announce itself. The user did
            // not just do anything.
            return new.isPlaying ? .peek : .updateInPlace

        case (.some(let old), .some(let new)):
            if old == new { return .unchanged }
            // A pause or an unpause is a state change worth showing, but not
            // worth a peek — the user pressed the key, they know.
            guard !old.isSameTrack(as: new) else { return .updateInPlace }
            return new.isPlaying ? .peek : .updateInPlace
        }
    }
}
