import XCTest

@testable import PerchCore

/// Covers `TEST-PLAN.md` § ISL. Every test name carries its case ID.
///
/// All of these are level **U**: no UI, no sleeping, no real system services.
/// The reducer is pure, so TTL expiry is delivered as an event rather than
/// waited for — a test that sleeps is a test that will flake in CI.
final class IslandReducerTests: XCTestCase {

    private var state = IslandState()
    private var queue = ActivityQueue<TestActivity>()
    private let reducer = IslandReducer<TestActivity>()

    override func setUp() {
        super.setUp()
        state = IslandState()
        queue = ActivityQueue<TestActivity>()
    }

    @discardableResult
    private func submit(_ activity: TestActivity) -> [IslandEffect] {
        queue.submit(activity)
        return reducer.reduce(
            state: &state,
            queue: &queue,
            event: .activitySubmitted(activity.id)
        )
    }

    @discardableResult
    private func send(_ event: IslandEvent) -> [IslandEffect] {
        reducer.reduce(state: &state, queue: &queue, event: event)
    }

    // MARK: - TC-ISL-001

    func test_TC_ISL_001_idleWithNoActivitiesIgnoresMouseEvents() {
        XCTAssertEqual(state.presentation, .idle)
        XCTAssertFalse(state.presentation.acceptsMouseEvents)
        XCTAssertTrue(queue.isEmpty)
    }

    // MARK: - TC-ISL-002

    func test_TC_ISL_002_singleActivityPeeksThenAutoCollapses() {
        let effects = submit(TestActivity("a", timeToLive: .seconds(3)))

        XCTAssertEqual(state.presentation, .peek("a"))
        XCTAssertTrue(state.presentation.acceptsMouseEvents)
        XCTAssertTrue(effects.contains(.scheduleCollapse("a", after: .seconds(3))))

        send(.timeToLiveExpired("a"))

        XCTAssertEqual(state.presentation, .idle)
        XCTAssertTrue(queue.isEmpty)
    }

    // MARK: - TC-ISL-003

    func test_TC_ISL_003_higherPriorityPreemptsAndLowerIsRequeued() {
        submit(TestActivity("music", priority: .nowPlaying))
        XCTAssertEqual(state.presentation, .peek("music"))

        submit(TestActivity("alert", source: .systemStats, priority: .systemAlert))

        XCTAssertEqual(state.presentation, .peek("alert"))

        // The pre-empted activity is re-queued, not dropped.
        XCTAssertEqual(queue.count, 2)
        XCTAssertTrue(queue.ordered.contains { $0.id == "music" })

        // ...and it comes back when the alert is done.
        send(.timeToLiveExpired("alert"))
        XCTAssertEqual(state.presentation, .peek("music"))
    }

    // MARK: - TC-ISL-005

    func test_TC_ISL_005_mouseLeaveCollapsesAfterGraceNotInstantly() {
        submit(TestActivity("a"))
        send(.hoverBegan)
        XCTAssertEqual(state.presentation, .expanded("a"))

        let effects = send(.hoverEnded)

        // Still expanded — the collapse is scheduled, not immediate.
        XCTAssertEqual(state.presentation, .expanded("a"))
        XCTAssertTrue(
            effects.contains(
                .scheduleCollapse("a", after: IslandReducer<TestActivity>.hoverGracePeriod)
            )
        )
    }

    // MARK: - TC-ISL-006

    func test_TC_ISL_006_equalPriorityMostRecentWinsOtherStaysQueued() {
        submit(TestActivity("first", priority: .nowPlaying))
        submit(TestActivity("second", priority: .nowPlaying))

        XCTAssertEqual(state.presentation, .peek("second"))
        XCTAssertEqual(queue.count, 2)
        XCTAssertEqual(queue.front?.id, "second")
    }

    // MARK: - TC-ISL-007

    func test_TC_ISL_007_cancelledWhilePresentedCollapsesAndQueueAdvances() {
        submit(TestActivity("a", priority: .nowPlaying))
        submit(TestActivity("b", priority: .fileDrop))
        XCTAssertEqual(state.presentation, .peek("b"))

        send(.activityWithdrawn("b"))

        XCTAssertEqual(state.presentation, .peek("a"))
        XCTAssertEqual(queue.count, 1)
    }

    func test_TC_ISL_007_withdrawingTheLastActivityReturnsToIdle() {
        submit(TestActivity("only"))
        send(.activityWithdrawn("only"))

        XCTAssertEqual(state.presentation, .idle)
        XCTAssertFalse(state.presentation.acceptsMouseEvents)
    }

    // MARK: - TC-ISL-009

    func test_TC_ISL_009_queueOverflowIsBoundedAndDropsLowestPriorityFirst() {
        // One activity that must survive the flood.
        queue.submit(TestActivity("important", priority: .systemAlert))

        for index in 0..<100 {
            queue.submit(TestActivity("ambient-\(index)", priority: .ambient))
        }

        XCTAssertLessThanOrEqual(queue.count, ActivityQueue<TestActivity>.capacity)
        XCTAssertTrue(
            queue.ordered.contains { $0.id == "important" },
            "A flood of low-priority activities must not evict a system alert"
        )
    }

    // MARK: - TC-ISL-012
    //
    // The reducer is motion-agnostic: it emits `.animate(to:)` and the UI
    // decides how. Proving that here is what stops a module sneaking a
    // duration into the state machine. The spring/fade choice itself is
    // covered by IslandMotionTests.

    func test_TC_ISL_012_reducerEmitsNoMotionSpecifics() {
        let effects = submit(TestActivity("a"))

        let animations = effects.filter {
            if case .animate = $0 { return true }
            return false
        }

        XCTAssertEqual(animations, [.animate(to: .peek("a"))])
    }

    // MARK: - Update in place (TC-MED-003 at the reducer level)

    func test_TC_MED_003_updatingPresentedActivityDoesNotReExpand() {
        submit(TestActivity("track", priority: .nowPlaying))
        send(.hoverBegan)
        XCTAssertEqual(state.presentation, .expanded("track"))

        // Same id, new content — a track change.
        let effects = submit(TestActivity("track", priority: .nowPlaying))

        XCTAssertEqual(state.presentation, .expanded("track"))
        XCTAssertTrue(
            effects.isEmpty,
            "An in-place update must not re-animate the island"
        )
    }

    // MARK: - Module disabled (TC-MED-007 at the reducer level)

    func test_TC_MED_007_disablingModuleWithdrawsAllOfItsActivities() {
        submit(TestActivity("m1", source: .nowPlaying))
        submit(TestActivity("m2", source: .nowPlaying))
        submit(TestActivity("shelf", source: .shelf, priority: .fileDrop))

        send(.moduleDisabled(.nowPlaying))

        XCTAssertFalse(queue.ordered.contains { $0.source == .nowPlaying })
        XCTAssertEqual(state.presentation, .peek("shelf"))
    }

    // MARK: - User intent outranks the clock

    func test_clickPinsExpansionAndTTLDoesNotCollapseIt() {
        submit(TestActivity("a", timeToLive: .seconds(3)))
        send(.clicked)

        XCTAssertEqual(state.presentation, .expanded("a"))
        XCTAssertTrue(state.isUserPinned)

        send(.timeToLiveExpired("a"))

        XCTAssertEqual(
            state.presentation, .expanded("a"),
            "A deliberately opened island must not be closed by its own timer"
        )
    }

    func test_activityWithNoTTLStaysUntilWithdrawn() {
        let effects = submit(TestActivity("timer", timeToLive: nil))

        XCTAssertFalse(
            effects.contains { effect in
                if case .scheduleCollapse = effect { return true }
                return false
            })

        send(.timeToLiveExpired("timer"))
        XCTAssertEqual(state.presentation, .peek("timer"))
    }

    // MARK: - TC-ISL-016

    /// The bug a real screen found: click the home surface open, click it
    /// again to close, and the island never answered hover again.
    func test_TC_ISL_016_closingTheHomeSurfaceByClickKeepsItOnTheIsland() {
        submit(TestActivity("home", timeToLive: nil))
        send(.clicked)
        XCTAssertEqual(state.presentation, .expanded("home"))

        send(.clicked)

        XCTAssertEqual(state.presentation, .peek("home"))
        XCTAssertEqual(queue.ordered.map(\.id), ["home"], "the home surface is still queued")

        send(.hoverBegan)
        XCTAssertEqual(state.presentation, .expanded("home"), "and hovering opens it again")
    }

    func test_TC_ISL_016_aModuleAskingToCollapseDoesNotThrowAwayAHeldActivity() {
        submit(TestActivity("gauge", priority: .ambient, timeToLive: nil))
        send(.hoverBegan)
        XCTAssertEqual(state.presentation, .expanded("gauge"))

        send(.collapseRequested)

        XCTAssertEqual(state.presentation, .peek("gauge"))
        XCTAssertEqual(queue.ordered.map(\.id), ["gauge"])
        XCTAssertFalse(state.isUserPinned)
    }

    /// Something with a clock is still dismissed outright by a second click,
    /// as before — a banner you have read is done with.
    func test_TC_ISL_016_anActivityWithATimeToLiveIsStillDismissed() {
        submit(TestActivity("home", timeToLive: nil))
        submit(TestActivity("alert", priority: .systemAlert, timeToLive: .seconds(3)))
        send(.clicked)
        send(.clicked)

        XCTAssertEqual(
            state.presentation, .peek("home"), "the alert is gone, the home surface is back")
        XCTAssertFalse(queue.ordered.contains { $0.id == "alert" })
    }

    func test_TC_ISL_016_collapsingAPeekIsHarmless() {
        submit(TestActivity("home", timeToLive: nil))

        XCTAssertEqual(send(.collapseRequested), [.cancelScheduledCollapse])
        XCTAssertEqual(state.presentation, .peek("home"))
    }

    // MARK: - TC-ISL-018

    /// A panel somebody opened from a tile has no clock — it stays while it
    /// is read — but nothing else will ever withdraw it. Folded to a peek,
    /// the battery list sat above the home surface until relaunch.
    func test_TC_ISL_018_aSecondClickThrowsAwayAnOpenedPanel() {
        submit(TestActivity("home", timeToLive: nil))
        submit(TestActivity("battery", priority: .fileDrop, timeToLive: nil, endsWhenClosed: true))
        send(.clicked)
        XCTAssertEqual(state.presentation, .expanded("battery"))

        send(.clicked)

        XCTAssertEqual(state.presentation, .peek("home"))
        XCTAssertEqual(queue.ordered.map(\.id), ["home"])
    }

    func test_TC_ISL_018_leavingAnOpenedPanelThrowsItAway() {
        submit(TestActivity("home", timeToLive: nil))
        send(.hoverBegan)
        submit(TestActivity("battery", priority: .fileDrop, timeToLive: nil, endsWhenClosed: true))
        XCTAssertEqual(state.presentation, .expanded("battery"))

        XCTAssertEqual(
            send(.hoverEnded),
            [.scheduleCollapse("battery", after: IslandReducer<TestActivity>.hoverGracePeriod)]
        )
        send(.timeToLiveExpired("battery"))

        XCTAssertEqual(
            state.presentation, .peek("home"),
            "back to the home surface, not a stuck peek"
        )
        XCTAssertEqual(queue.ordered.map(\.id), ["home"])
    }

    /// The camera closes when the island stops showing it (TC-CAM-006).
    /// Folding the preview to its peek kept the id on screen, so the device
    /// stayed open with the light on.
    func test_TC_ISL_018_closingTheCameraTakesItsIdOffTheIsland() {
        submit(TestActivity("home", timeToLive: nil))
        submit(TestActivity("camera", timeToLive: nil, endsWhenClosed: true))
        send(.clicked)

        send(.collapseRequested)

        XCTAssertNotEqual(state.presentation.activityID, "camera")
    }

    func test_TC_ISL_018_aModuleOwnedActivityStillFolds() {
        submit(TestActivity("timer", timeToLive: nil))
        send(.clicked)
        send(.clicked)

        XCTAssertEqual(state.presentation, .peek("timer"))
        XCTAssertEqual(queue.ordered.map(\.id), ["timer"])
    }

    // MARK: - TC-ISL-017

    func test_TC_ISL_017_hoverToExpandOffMeansHoverDoesNotOpen() {
        send(.gesturesChanged(IslandGestures(hoverExpands: false)))
        submit(TestActivity("home", timeToLive: nil))

        send(.hoverBegan)
        XCTAssertEqual(state.presentation, .peek("home"))

        send(.clicked)
        XCTAssertEqual(state.presentation, .expanded("home"), "a click still opens it")
    }

    func test_TC_ISL_017_hoverToExpandOffStillHoldsAPeekBeingRead() {
        send(.gesturesChanged(IslandGestures(hoverExpands: false)))
        submit(TestActivity("banner", timeToLive: .seconds(3)))

        XCTAssertEqual(send(.hoverBegan), [.cancelScheduledCollapse])
        XCTAssertEqual(state.presentation, .peek("banner"))
    }

    func test_TC_ISL_017_anArrivalWhileHoveredOnlyPeeksWhenHoverIsOff() {
        send(.gesturesChanged(IslandGestures(hoverExpands: false)))
        send(.hoverBegan)

        submit(TestActivity("banner", timeToLive: .seconds(3)))
        XCTAssertEqual(state.presentation, .peek("banner"))
    }

    func test_TC_ISL_017_clickToKeepOpenOffMakesAClickOpenAndCloseWithoutPinning() {
        send(.gesturesChanged(IslandGestures(clickPins: false)))
        submit(TestActivity("home", timeToLive: nil))

        send(.clicked)
        XCTAssertEqual(state.presentation, .expanded("home"))
        XCTAssertFalse(state.isUserPinned)

        send(.clicked)
        XCTAssertEqual(state.presentation, .peek("home"))
        XCTAssertEqual(queue.ordered.map(\.id), ["home"])
    }

    func test_TC_ISL_017_withClickToKeepOpenOffLeavingClosesIt() {
        send(.gesturesChanged(IslandGestures(clickPins: false)))
        submit(TestActivity("home", timeToLive: nil))
        send(.clicked)

        XCTAssertEqual(
            send(.hoverEnded),
            [.scheduleCollapse("home", after: IslandReducer<TestActivity>.hoverGracePeriod)]
        )
    }
}
