import Foundation
import PerchCore

/// What is playing, as the island sees it.
///
/// Module 1 of `docs/FEATURES.md`. Every competitor ships this, so it is
/// judged on motion quality rather than novelty — which is also why it is the
/// first module built: it is the honest benchmark for whether the panel and
/// the motion tokens are good enough to carry the other sixteen.
///
/// Pure Foundation. The drawing half is in `NowPlayingView.swift`.
struct NowPlayingActivity: IslandActivity {

    /// One stable id for the whole module.
    ///
    /// Not per-track, deliberately. A track change must update the activity
    /// already on screen rather than queue a second one behind it — same id,
    /// same activity, new content (TC-MED-003).
    static let identifier = ActivityID("nowplaying.current")

    let id = Self.identifier
    let source: ModuleID = .nowPlaying
    let priority: ActivityPriority = .nowPlaying

    var snapshot: NowPlayingSnapshot

    /// Whether this arrived as a track change, which is the only thing that
    /// earns a sneak peek.
    var isSneakPeek: Bool

    /// A sneak peek is two seconds and then it gets out of the way
    /// (`docs/FEATURES.md` §1). Anything else stays: music is ambient, and an
    /// island that keeps the artwork up while a track plays is the point.
    var timeToLive: Duration? {
        isSneakPeek ? .seconds(2) : nil
    }

    init(snapshot: NowPlayingSnapshot, isSneakPeek: Bool = false) {
        self.snapshot = snapshot
        self.isSneakPeek = isSneakPeek
    }
}
