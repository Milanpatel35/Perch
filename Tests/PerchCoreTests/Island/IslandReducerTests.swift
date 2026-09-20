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
}
