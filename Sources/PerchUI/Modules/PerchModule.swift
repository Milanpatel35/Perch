import Foundation
import PerchCore

/// What every one of the seventeen modules is.
///
/// The contract is short because the hard part is not the interface, it is
/// `deactivate()`: a module that is off must cost **nothing**. Not a slower
/// timer, not a cheap observer, not a sleeping publisher — nothing
/// (`CLAUDE.md` §4 and §5.1). Every module's `TC-…-007`-shaped test checks
/// exactly that, and `ModuleHost` is what calls it.
@MainActor
public protocol PerchModule: AnyObject {

    /// Which module this is. Matches the directory under
    /// `Sources/PerchModules/`.
    static var moduleID: ModuleID { get }

    /// Whether the module currently holds any resource at all.
    var isActive: Bool { get }

    /// Start observing. Called when the switch goes on, and at launch for
    /// modules already switched on.
    ///
    /// This is also where a module asks for its permission — never before
    /// (`CLAUDE.md` §5.3, TC-PRV-002).
    func activate()

    /// Release everything: observers removed, timers invalidated, sessions
    /// stopped, caches dropped, activities withdrawn.
    ///
    /// Must be safe to call when already inactive, and must leave nothing
    /// behind that a later `activate()` would double up on.
    func deactivate()
}

public extension PerchModule {
    var moduleID: ModuleID { Self.moduleID }
}
