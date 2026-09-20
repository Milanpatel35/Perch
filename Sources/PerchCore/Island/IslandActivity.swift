import Foundation

/// The contract every module implements to put something in the island.
///
/// All eighteen modules in `docs/FEATURES.md` conform to this. Adding a
/// feature means adding a conformer plus a view — you are almost never
/// changing the reducer. Get this protocol right before anything depends on
/// it.
///
/// Conformers live in `PerchCore` where they can, so they stay testable.
/// Nothing here may import SwiftUI or AppKit.
public protocol IslandActivity: Sendable, Identifiable where ID == ActivityID {

    /// Stable across updates to the same logical activity.
    ///
    /// A track change updates the existing Now Playing activity in place
    /// rather than pushing a second one, because both carry the same id.
    var id: ActivityID { get }

    /// Which module produced this. Used for the per-module off switch, and
    /// for the exclusivity rule in `ActivityQueue`.
    var source: ModuleID { get }

    /// Higher wins. See `ActivityPriority`.
    var priority: ActivityPriority { get }

    /// How long the activity stays on screen unattended before collapsing.
    ///
    /// `nil` means "until withdrawn" — a focus timer or a held shelf stays up
    /// because the module decides when it is done, not the clock.
    var timeToLive: Duration? { get }

    /// Whether hovering should expand this beyond its peek presentation.
    var isExpandable: Bool { get }
}

public extension IslandActivity {
    var isExpandable: Bool { true }
    var timeToLive: Duration? { .seconds(3) }
}

/// Identity for an activity. Modules mint these; the queue only compares them.
public struct ActivityID: Hashable, Sendable {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

/// One per module folder under `Sources/PerchModules/`.
public enum ModuleID: String, CaseIterable, Sendable {
    case nowPlaying
    case shelf
    case clipboard
    case focus
    case calendar
    case hud
    case battery
    case notifications
    case camera
    case systemStats
    case weather
    case windows
    case shortcuts
    case notes
    case voice
    case screenshot
    case hideNotch
}

/// Priority order from `CLAUDE.md` §3, highest first:
///
///     system alert > timer finishing > incoming call > file drop
///                  > now playing > ambient
///
/// Ties break to the most recent — that rule lives in `ActivityQueue`, not
/// here, because it depends on submission order rather than on the value.
public enum ActivityPriority: Int, Comparable, Sendable, CaseIterable {
    case ambient = 0
    case nowPlaying = 1
    case fileDrop = 2
    case incomingCall = 3
    case timerFinishing = 4
    case systemAlert = 5

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
