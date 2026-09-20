import Foundation

/// A type-erased `IslandActivity`.
///
/// The reducer and the queue are generic so they can be tested against a
/// fixture, but at runtime there is exactly one island and seventeen modules
/// feeding it. This is the concrete type they all funnel through:
/// `ActivityQueue<AnyIslandActivity>`.
///
/// It carries the original value untouched in `base`, which is how `PerchUI`
/// recovers a module's own activity type to build its view. Core never looks
/// inside — it only reads the four properties the reducer needs, which is
/// what keeps the state machine ignorant of what a module is.
public struct AnyIslandActivity: IslandActivity {

    /// The module's own activity value, unmodified.
    public let base: any IslandActivity

    public var id: ActivityID { base.id }
    public var source: ModuleID { base.source }
    public var priority: ActivityPriority { base.priority }
    public var timeToLive: Duration? { base.timeToLive }
    public var isExpandable: Bool { base.isExpandable }

    /// Wrapping an already-wrapped activity returns the inner value rather
    /// than nesting. Without this, a module that round-trips an activity
    /// through the controller would end up with a box inside a box, and the
    /// `as?` cast in the view layer would silently stop matching.
    public init(_ base: any IslandActivity) {
        if let erased = base as? Self {
            self.base = erased.base
        } else {
            self.base = base
        }
    }

    /// Recovers the module's own type.
    public func unwrap<A: IslandActivity>(as type: A.Type = A.self) -> A? {
        base as? A
    }
}
