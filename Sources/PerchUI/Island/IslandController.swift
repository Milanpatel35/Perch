import Combine
import Foundation
import PerchCore

/// The runtime around `IslandReducer`.
///
/// Core decides; this performs. It owns the queue, turns the reducer's
/// effects into real work (one cancellable timer, at most), and publishes the
/// result for the views to read. It owns no presentation logic of its own —
/// if you are tempted to add an `if` here, the rule it encodes probably
/// belongs in the reducer, where it can be tested.
///
/// Deliberately free of AppKit so the whole runtime can be driven from a test
/// without a panel. The panel observes it, not the other way round.
@MainActor
public final class IslandController: ObservableObject {

    /// The island's current state, straight from the reducer.
    @Published public private(set) var state = IslandState()

    /// The activity currently on screen, if any.
    @Published public private(set) var presented: AnyIslandActivity?

    /// Whether the panel should accept mouse events. Driven by the reducer's
    /// `.setMouseEventsEnabled` effect, never set directly (TC-ISL-001).
    @Published public private(set) var acceptsMouseEvents = false

    /// Everything waiting, highest priority first. The expanded island shows
    /// this as the "stack" badge.
    @Published public private(set) var queued: [AnyIslandActivity] = []

    /// Whether something currently on the island needs the keyboard.
    ///
    /// Almost always false. The island is a surface you touch, not one you
    /// focus, and typing has to keep going to the app in front (TC-ISL-008).
    /// The clipboard's search field is the only thing that raises this, and
    /// it lowers it again the moment the picker closes.
    @Published public private(set) var requiresKeyFocus = false

    /// The motion token for the transition the island is currently making.
    ///
    /// Held here rather than derived in the view because the view only sees
    /// the new presentation — the token depends on the one it replaced.
    @Published public private(set) var transition: IslandMotion.Token = .peek

    private var previousPresentation: IslandPresentation = .idle

    private var queue = ActivityQueue<AnyIslandActivity>()
    private let reducer = IslandReducer<AnyIslandActivity>()

    /// The single pending collapse. There is never more than one, which is
    /// the whole reason the reducer returns `.cancelScheduledCollapse`
    /// explicitly rather than leaving the runtime to guess.
    private var collapseTask: Task<Void, Never>?

    /// Injected so tests can run the whole runtime without waiting in real
    /// time. Production passes `Task.sleep`.
    private let sleep: @Sendable (Duration) async throws -> Void

    public init(
        sleep: @escaping @Sendable (Duration) async throws -> Void = {
            try await Task.sleep(for: $0)
        }
    ) {
        self.sleep = sleep
    }

    deinit {
        collapseTask?.cancel()
    }

    // MARK: - Module API

    /// Puts an activity on the island, or updates one already there.
    ///
    /// Re-submitting the same `ActivityID` updates in place — the island does
    /// not re-expand on a track change (TC-MED-003).
    public func submit(_ activity: any IslandActivity) {
        let erased = AnyIslandActivity(activity)
        queue.submit(erased)
        send(.activitySubmitted(erased.id))
    }

    /// Removes an activity whether or not it is currently presented.
    public func withdraw(_ id: ActivityID) {
        send(.activityWithdrawn(id))
    }

    /// Drops everything a module owns. Called when a module is switched off:
    /// it must leave nothing behind (TC-MED-007).
    public func withdrawAll(from module: ModuleID) {
        send(.moduleDisabled(module))
    }

    /// Asks the panel for key focus, for as long as a module genuinely needs
    /// it. Modules lower this themselves; nothing does it for them.
    public func setRequiresKeyFocus(_ required: Bool) {
        guard requiresKeyFocus != required else { return }
        requiresKeyFocus = required
    }

    // MARK: - Input

    public func send(_ event: IslandEvent) {
        let effects = reducer.reduce(state: &state, queue: &queue, event: event)
        publish()
        for effect in effects {
            apply(effect)
        }
    }

    // MARK: - Effects

    private func apply(_ effect: IslandEffect) {
        switch effect {
        case .scheduleCollapse(let id, let delay):
            scheduleCollapse(of: id, after: delay)

        case .cancelScheduledCollapse:
            collapseTask?.cancel()
            collapseTask = nil

        case .setMouseEventsEnabled(let enabled):
            acceptsMouseEvents = enabled

        case .animate:
            // The presentation is already in `state`; the views animate off
            // it. Nothing imperative to do — which is the point of the
            // reducer returning effects rather than calling into the UI.
            break
        }
    }

    private func scheduleCollapse(of id: ActivityID, after delay: Duration) {
        collapseTask?.cancel()
        collapseTask = Task { [weak self, sleep] in
            do {
                try await sleep(delay)
            } catch {
                return  // Cancelled: something else took the island.
            }
            guard !Task.isCancelled else { return }
            self?.send(.timeToLiveExpired(id))
        }
    }

    private func publish() {
        if state.presentation != previousPresentation {
            transition = IslandMotion.token(
                from: previousPresentation,
                to: state.presentation
            )
            previousPresentation = state.presentation
        }

        queued = queue.ordered
        presented = state.presentation.activityID.flatMap { id in
            queued.first { $0.id == id }
        }
        // `.setMouseEventsEnabled` is only emitted on a transition into or
        // out of idle, so keep the published flag honest for every other
        // path too.
        acceptsMouseEvents = state.presentation.acceptsMouseEvents
    }
}
