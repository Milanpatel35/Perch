import Foundation

/// The island's state machine.
///
/// Pure: given a state, a queue and an event, it returns the new state and a
/// list of effects. No clock, no panel, no screen. That is what makes the
/// whole of `TEST-PLAN.md` § ISL testable as fast unit tests.
///
/// **This is the most important type in the project.** Eighteen modules are
/// written against it. If you are adding a feature you are adding an
/// `IslandActivity` conformer and a view — you are almost never changing this.
public struct IslandReducer<Activity: IslandActivity> {

    /// How long the island waits after the pointer leaves before collapsing.
    ///
    /// Not zero, because the pointer crosses the island's edge constantly on
    /// the way to the menu bar, and collapsing instantly makes it feel
    /// twitchy (TC-ISL-005).
    public static var hoverGracePeriod: Duration { .milliseconds(400) }

    public init() {}

    /// Applies an event.
    ///
    /// - Parameters:
    ///   - state: mutated in place.
    ///   - queue: mutated in place — pre-emption re-queues rather than drops.
    /// - Returns: the effects the UI layer must perform, in order.
    @discardableResult
    public func reduce(
        state: inout IslandState,
        queue: inout ActivityQueue<Activity>,
        event: IslandEvent
    ) -> [IslandEffect] {

        switch event {
        case .activitySubmitted:
            // The queue already holds it; decide whether it displaces what is
            // on screen. A higher-priority arrival pre-empts immediately, and
            // the displaced activity stays queued rather than being dropped
            // (TC-ISL-003).
            return presentFrontIfWarranted(state: &state, queue: &queue)

        case .activityWithdrawn(let id):
            return withdraw(id, state: &state, queue: &queue)

        case .timeToLiveExpired(let id):
            return expire(id, state: &state, queue: &queue)

        case .hoverBegan:
            return hoverBegan(state: &state, queue: queue)

        case .hoverEnded:
            return hoverEnded(state: &state)

        case .clicked:
            return clicked(state: &state, queue: &queue)

        case .dragEntered:
            return dragEntered(state: &state)

        case .moduleDisabled(let module):
            return disable(module, state: &state, queue: &queue)

        case .collapseRequested:
            return collapse(state: &state, queue: &queue)
        }
    }

    // MARK: - Event handlers

    private func withdraw(
        _ id: ActivityID,
        state: inout IslandState,
        queue: inout ActivityQueue<Activity>
    ) -> [IslandEffect] {
        queue.withdraw(id)
        guard state.presentation.activityID == id else { return [] }
        // What was on screen is gone: collapse cleanly and let the queue
        // advance (TC-ISL-007).
        state.isUserPinned = false
        return advance(state: &state, queue: &queue)
    }

    private func expire(
        _ id: ActivityID,
        state: inout IslandState,
        queue: inout ActivityQueue<Activity>
    ) -> [IslandEffect] {
        // Ignore a stale timer for something no longer presented.
        guard state.presentation.activityID == id else { return [] }
        // A person hovering, or having deliberately opened it, outranks the
        // clock. Re-arm rather than yanking it away mid-read.
        guard !state.isHovered, !state.isUserPinned else {
            return rearmCollapse(for: id, queue: queue)
        }

        // An activity that declared no TTL owns its own lifetime — a focus
        // timer mid-session, a shelf holding files, the home surface. No
        // expiry event may *close* one, however it arrived: a stale timer
        // from a previous activity that reused this id would otherwise
        // silently stop a running session.
        //
        // It must still collapse, though. This event is also how the grace
        // period after the pointer leaves arrives (TC-ISL-005), and without
        // this branch an island opened by hovering the home surface stayed
        // expanded for ever — there was no path back to a peek that did not
        // also withdraw the activity.
        guard activity(id, in: queue)?.timeToLive != nil else {
            guard state.presentation == .expanded(id) else { return [] }
            state.presentation = .peek(id)
            return [.animate(to: .peek(id))]
        }

        queue.withdraw(id)
        return advance(state: &state, queue: &queue)
    }

    private func hoverBegan(
        state: inout IslandState,
        queue: ActivityQueue<Activity>
    ) -> [IslandEffect] {
        state.isHovered = true
        guard let id = state.presentation.activityID else { return [] }
        guard isExpandable(id, in: queue) else {
            return [.cancelScheduledCollapse]
        }
        state.presentation = .expanded(id)
        return [.cancelScheduledCollapse, .animate(to: .expanded(id))]
    }

    private func hoverEnded(state: inout IslandState) -> [IslandEffect] {
        state.isHovered = false
        guard let id = state.presentation.activityID, !state.isUserPinned else {
            return []
        }
        return [.scheduleCollapse(id, after: Self.hoverGracePeriod)]
    }

    private func clicked(
        state: inout IslandState,
        queue: inout ActivityQueue<Activity>
    ) -> [IslandEffect] {
        guard let id = state.presentation.activityID else { return [] }

        // A second click on a pinned island dismisses it.
        if state.isUserPinned {
            state.isUserPinned = false
            queue.withdraw(id)
            return advance(state: &state, queue: &queue)
        }

        // Clicking makes it interactive and stops the clock. It must not steal
        // key focus from the frontmost app — that is the panel's job, not the
        // reducer's (TC-ISL-008).
        state.isUserPinned = true
        state.presentation = .expanded(id)
        return [.cancelScheduledCollapse, .animate(to: .expanded(id))]
    }

    private func dragEntered(state: inout IslandState) -> [IslandEffect] {
        // A drag over the notch is the shelf's entry gesture. Expanding here
        // rather than waiting for the drop is what makes the target findable.
        guard let id = state.presentation.activityID else { return [] }
        state.presentation = .expanded(id)
        return [.cancelScheduledCollapse, .animate(to: .expanded(id))]
    }

    private func disable(
        _ module: ModuleID,
        state: inout IslandState,
        queue: inout ActivityQueue<Activity>
    ) -> [IslandEffect] {
        queue.withdrawAll(from: module)
        guard let current = state.presentation.activityID,
            queue.ordered.allSatisfy({ $0.id != current })
        else { return [] }
        state.isUserPinned = false
        return advance(state: &state, queue: &queue)
    }

    private func collapse(
        state: inout IslandState,
        queue: inout ActivityQueue<Activity>
    ) -> [IslandEffect] {
        guard let id = state.presentation.activityID else { return [] }
        state.isUserPinned = false
        queue.withdraw(id)
        return advance(state: &state, queue: &queue)
    }

    // MARK: - Transitions

    /// Presents the queue front if it outranks what is on screen.
    private func presentFrontIfWarranted(
        state: inout IslandState,
        queue: inout ActivityQueue<Activity>
    ) -> [IslandEffect] {

        guard let next = queue.front else { return [] }

        // Already showing the front: it was an in-place update, so leave the
        // presentation alone. The island must not re-expand on a track change
        // (TC-MED-003).
        if state.presentation.activityID == next.id { return [] }

        // A pinned expansion is only displaced by something that outranks it.
        if pinnedExpansionHoldsAgainst(next, state: state, queue: queue) {
            return []
        }

        state.isUserPinned = false
        return present(next, state: &state)
    }

    /// Moves to whatever is next in the queue, or to idle.
    private func advance(
        state: inout IslandState,
        queue: inout ActivityQueue<Activity>
    ) -> [IslandEffect] {

        guard let next = queue.front else {
            state.presentation = .idle
            return [
                .cancelScheduledCollapse,
                .setMouseEventsEnabled(false),
                .animate(to: .idle)
            ]
        }
        return present(next, state: &state)
    }

    private func present(
        _ activity: Activity,
        state: inout IslandState
    ) -> [IslandEffect] {

        // Hovering the island while a new activity arrives means the person is
        // already looking at it — open it fully rather than flashing a peek.
        let presentation: IslandPresentation =
            (state.isHovered && activity.isExpandable)
            ? .expanded(activity.id)
            : .peek(activity.id)

        state.presentation = presentation

        var effects: [IslandEffect] = [
            .setMouseEventsEnabled(true),
            .animate(to: presentation)
        ]

        if let ttl = activity.timeToLive, !state.isHovered {
            effects.append(.scheduleCollapse(activity.id, after: ttl))
        } else {
            effects.append(.cancelScheduledCollapse)
        }

        return effects
    }

    /// Whether a user-pinned expansion should keep the island against an
    /// arriving activity.
    ///
    /// A person who deliberately opened something outranks anything merely
    /// equal to it. Only a strictly higher priority takes the island away.
    private func pinnedExpansionHoldsAgainst(
        _ next: Activity,
        state: IslandState,
        queue: ActivityQueue<Activity>
    ) -> Bool {
        guard state.isUserPinned,
            let currentID = state.presentation.activityID,
            let current = activity(currentID, in: queue)
        else { return false }

        return next.priority <= current.priority
    }

    private func rearmCollapse(
        for id: ActivityID,
        queue: ActivityQueue<Activity>
    ) -> [IslandEffect] {
        guard let ttl = activity(id, in: queue)?.timeToLive else { return [] }
        return [.scheduleCollapse(id, after: ttl)]
    }

    // MARK: - Lookup

    private func activity(
        _ id: ActivityID,
        in queue: ActivityQueue<Activity>
    ) -> Activity? {
        queue.ordered.first { $0.id == id }
    }

    private func isExpandable(
        _ id: ActivityID,
        in queue: ActivityQueue<Activity>
    ) -> Bool {
        activity(id, in: queue)?.isExpandable ?? false
    }
}
