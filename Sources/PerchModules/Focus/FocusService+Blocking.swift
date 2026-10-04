import Defaults
import Foundation
import PerchCore

/// Distraction blocking, the half of the focus module that reaches outside
/// Perch (`docs/FEATURES.md` §4).
extension FocusService {

    /// Starts, updates or stops the blocker to match the session. The only
    /// place that decides — `DistractionBlocklist.isEnforced(during:)`
    /// holds the rule (TC-FOC-013).
    func syncBlocking() {
        blocker.update(blocklist, enforced: isActive && blocklist.isEnforced(during: timer))
        objectWillChange.send()
    }

    func setBlocklist(_ updated: DistractionBlocklist) {
        blocklist = updated
        Defaults[.distractionBlocklist] = updated
        syncBlocking()
    }

    /// A new work session starts the count again; resuming one does not.
    func startCountingBlocks() {
        if timer.phase == .work { blockedThisSession = 0 }
    }

    func blocked(_ name: String) {
        guard isActive else { return }
        blockedThisSession += 1
        island.submit(FocusBlockedActivity(name: name, count: blockedThisSession))
    }
}

extension DistractionBlocklist: Defaults.Serializable {}

extension Defaults.Keys {
    /// Off, and empty, until somebody fills it in.
    static let distractionBlocklist = Key<DistractionBlocklist>(
        "focus_blocklist",
        default: DistractionBlocklist()
    )
}
