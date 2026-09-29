import Foundation

/// What the island is doing right now.
///
///     idle → peek → expanded → idle
///
/// `idle` is not "hidden" — on a notched Mac the island is always physically
/// there. It means *nothing is presented*, the panel ignores mouse events, and
/// no module is doing work.
public enum IslandPresentation: Equatable, Sendable {

    /// Nothing to show. Panel is inert (TC-ISL-001).
    case idle

    /// A brief, non-interactive presentation that collapses on its own.
    case peek(ActivityID)

    /// Full presentation, interactive, stays until dismissed.
    case expanded(ActivityID)

    public var activityID: ActivityID? {
        switch self {
        case .idle: nil
        case .peek(let id), .expanded(let id): id
        }
    }

    public var isIdle: Bool { self == .idle }

    /// Whether the panel should accept mouse events in this state.
    public var acceptsMouseEvents: Bool {
        switch self {
        case .idle: false
        case .peek, .expanded: true
        }
    }
}

/// The complete island state. `PerchUI` reads this; it never owns it.
public struct IslandState: Equatable, Sendable {
    public var presentation: IslandPresentation = .idle

    /// True while the pointer is over the island's hit area. Hover is an
    /// input, not a state — it is recorded here so the reducer can decide
    /// whether a TTL expiry should actually collapse (TC-ISL-005).
    public var isHovered: Bool = false

    /// Set when the user has explicitly expanded. A user-pinned expansion
    /// outlives its activity's TTL — the clock does not close something a
    /// person deliberately opened.
    public var isUserPinned: Bool = false

    /// Which pointer gestures the person has left switched on
    /// (`docs/FEATURES.md` §18). Part of the state rather than a check in the
    /// view, so that "off" is a reducer rule with a test behind it.
    public var gestures = IslandGestures()

    public init() {}
}

/// The island's pointer gestures, each individually switchable in General.
public struct IslandGestures: Equatable, Sendable {

    /// Hovering the island opens it. Off, only a click does.
    public var hoverExpands = true

    /// A click keeps the island open until a second click. Off, a click opens
    /// it the same way hovering does, and it closes when the pointer leaves.
    public var clickPins = true

    public init(hoverExpands: Bool = true, clickPins: Bool = true) {
        self.hoverExpands = hoverExpands
        self.clickPins = clickPins
    }
}

/// Everything that can move the island.
public enum IslandEvent: Equatable, Sendable {
    case activitySubmitted(ActivityID)
    case activityWithdrawn(ActivityID)
    case timeToLiveExpired(ActivityID)
    case hoverBegan
    case hoverEnded
    case clicked
    case dragEntered
    case moduleDisabled(ModuleID)
    case collapseRequested
    case gesturesChanged(IslandGestures)
}

/// What the UI layer must do as a result of a transition.
///
/// The reducer never performs side effects — it returns them. That is what
/// lets the entire state machine be tested without a panel, a screen, or a
/// clock (`CLAUDE.md` §3).
public enum IslandEffect: Equatable, Sendable {

    /// Start the TTL countdown for an activity. Cancelled implicitly whenever
    /// a different activity is presented.
    case scheduleCollapse(ActivityID, after: Duration)

    /// Stop any pending countdown.
    case cancelScheduledCollapse

    /// Tell the panel whether to take mouse events.
    case setMouseEventsEnabled(Bool)

    /// Animate to a new presentation. The UI chooses spring vs cross-fade
    /// based on Reduce Motion (TC-ISL-012); the reducer does not care which.
    case animate(to: IslandPresentation)
}
