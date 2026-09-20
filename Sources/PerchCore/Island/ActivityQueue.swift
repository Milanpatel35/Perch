import Foundation

/// A bounded, priority-ordered queue of pending activities.
///
/// The rules it enforces, all from `CLAUDE.md` §3:
///
/// - Highest priority wins.
/// - Ties break to the **most recently submitted**.
/// - It is bounded. A misbehaving module cannot grow it without limit
///   (TC-ISL-009); when full, the oldest lowest-priority entry is dropped.
/// - Re-submitting the same `ActivityID` updates in place rather than
///   enqueueing a duplicate (TC-MED-003).
///
/// Pre-emption is *not* here — the queue holds what is waiting, and
/// `IslandReducer` decides what is on screen. Keeping those separate is what
/// makes both testable without a clock.
public struct ActivityQueue<Activity: IslandActivity> {

    /// Chosen so that a runaway module is capped long before memory is, while
    /// still being far more than any real workload. TC-ISL-009 submits 100.
    public static var capacity: Int { 32 }

    /// Monotonic counter standing in for submission order. Deliberately not a
    /// timestamp: two submissions inside the same clock tick must still order
    /// deterministically, and tests must not depend on wall-clock resolution.
    private var sequence: UInt64 = 0

    private struct Entry {
        let activity: Activity
        let sequence: UInt64
    }

    private var entries: [Entry] = []

    public init() {}

    public var isEmpty: Bool { entries.isEmpty }
    public var count: Int { entries.count }

    /// Every queued activity, highest priority first, most recent first
    /// within a priority.
    public var ordered: [Activity] {
        entries
            .sorted { lhs, rhs in
                if lhs.activity.priority != rhs.activity.priority {
                    return lhs.activity.priority > rhs.activity.priority
                }
                return lhs.sequence > rhs.sequence
            }
            .map(\.activity)
    }

    /// The activity that should be presented next, without removing it.
    public var front: Activity? { ordered.first }

    /// Adds an activity, or updates one already queued under the same id.
    ///
    /// - Returns: `true` if this was a new entry, `false` if it updated an
    ///   existing one. Callers use this to decide whether to re-animate: an
    ///   update should change content in place, not re-expand the island.
    @discardableResult
    public mutating func submit(_ activity: Activity) -> Bool {
        sequence += 1

        if let index = entries.firstIndex(where: { $0.activity.id == activity.id }) {
            // Keep the original sequence. An update is not a bump to the front
            // of its priority band — otherwise a chatty module could starve
            // its peers just by refreshing.
            entries[index] = Entry(activity: activity, sequence: entries[index].sequence)
            return false
        }

        entries.append(Entry(activity: activity, sequence: sequence))
        evictIfNeeded()
        return true
    }

    /// Removes a specific activity, whether or not it is currently presented.
    @discardableResult
    public mutating func withdraw(_ id: ActivityID) -> Activity? {
        guard let index = entries.firstIndex(where: { $0.activity.id == id }) else {
            return nil
        }
        return entries.remove(at: index).activity
    }

    /// Removes and returns the highest-priority entry.
    @discardableResult
    public mutating func dequeue() -> Activity? {
        guard let next = front else { return nil }
        return withdraw(next.id)
    }

    /// Drops everything belonging to a module. Called when a module is
    /// switched off — the module must leave nothing behind (TC-MED-007).
    public mutating func withdrawAll(from source: ModuleID) {
        entries.removeAll { $0.activity.source == source }
    }

    public mutating func removeAll() {
        entries.removeAll()
    }

    /// Drops the oldest lowest-priority entry once over capacity.
    ///
    /// Note this never drops a high-priority entry to make room for a low one:
    /// the eviction candidate is chosen from the *bottom* of the same ordering
    /// used for presentation, so a system alert survives a flood of ambient
    /// activities rather than being pushed out by it.
    private mutating func evictIfNeeded() {
        while entries.count > Self.capacity {
            guard
                let victim = entries.min(by: { lhs, rhs in
                    if lhs.activity.priority != rhs.activity.priority {
                        return lhs.activity.priority < rhs.activity.priority
                    }
                    return lhs.sequence < rhs.sequence
                })
            else { return }

            entries.removeAll { $0.activity.id == victim.activity.id }
        }
    }
}
