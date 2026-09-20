import Foundation
import PerchCore

/// A focus session, counting down in the collapsed island.
///
/// `docs/FEATURES.md` §4: "not a window, not a menu-bar string". The whole
/// point of this module is that the timer lives where you already look.
///
/// **No time to live.** The session decides when it is over, not the clock on
/// the island — that is exactly the case the `timeToLive: nil` contract in
/// `IslandActivity` was written for.
struct FocusActivity: IslandActivity {

    static let identifier = ActivityID("focus.session")

    let id = Self.identifier
    let source: ModuleID = .focus

    /// Ambient while it runs. A countdown is a thing you glance at, and it
    /// must not hold the island against something more urgent.
    let priority: ActivityPriority = .ambient

    let timeToLive: Duration? = nil

    let timer: PomodoroTimer
    let sessionsToday: Int
    let streakDays: Int
}

/// A session that has just ended.
///
/// **The one thing in this module that interrupts.** `timerFinishing` sits
/// above `nowPlaying` in `CLAUDE.md` §3's order, so a finished session takes
/// the island from whatever was playing — which is TC-FOC-002, and the reason
/// the priority ladder exists at all.
struct FocusFinishedActivity: IslandActivity {

    static let identifier = ActivityID("focus.finished")

    let id = Self.identifier
    let source: ModuleID = .focus
    let priority: ActivityPriority = .timerFinishing

    /// Long enough to be noticed from across a desk. A finished Pomodoro that
    /// vanishes in two seconds is one you miss, and then the technique does
    /// not work.
    let timeToLive: Duration? = .seconds(12)

    /// The phase that just ended, not the one coming next.
    let finished: PomodoroTimer.Phase

    /// What is queued, so the island can offer to start it.
    let next: PomodoroTimer.Phase
    let sessionsToday: Int
    let streakDays: Int
}
