import XCTest

@testable import PerchCore

/// Covers `TEST-PLAN.md` TC-ISL-021: hover must not outlive the island it
/// was on. Its own class because `IslandReducerTests` is at swiftlint's
/// length limit.
final class IslandHoverTests: XCTestCase {

    private var state = IslandState()
    private var queue = ActivityQueue<TestActivity>()
    private let reducer = IslandReducer<TestActivity>()

    @discardableResult
    private func submit(_ activity: TestActivity) -> [IslandEffect] {
        queue.submit(activity)
        return reducer.reduce(state: &state, queue: &queue, event: .activitySubmitted(activity.id))
    }

    @discardableResult
    private func send(_ event: IslandEvent) -> [IslandEffect] {
        reducer.reduce(state: &state, queue: &queue, event: event)
    }

    // MARK: - TC-ISL-021

    /// **The stuck note.** The island went idle under the pointer, macOS
    /// sent no "left" event, and every activity after that opened fully and
    /// never expired — a black box over the browser's tabs.
    func test_TC_ISL_021_goingIdleForgetsTheHover() {
        submit(TestActivity("a", timeToLive: .seconds(3)))
        send(.hoverBegan)
        send(.timeToLiveExpired("a"))
        send(.hoverEnded)  // grace period ends while still hovered...
        XCTAssertEqual(state.presentation, .expanded("a"))

        // ...then the module withdraws it with the pointer still "on" it.
        send(.activityWithdrawn("a"))
        XCTAssertEqual(state.presentation, .idle)
        XCTAssertFalse(state.isHovered, "nothing to hover once idle")

        let effects = submit(TestActivity("note", timeToLive: .seconds(4)))

        XCTAssertEqual(state.presentation, .peek("note"), "a peek, not an open island")
        XCTAssertTrue(effects.contains(.scheduleCollapse("note", after: .seconds(4))))
    }

    func test_TC_ISL_021_hoverStillOpensWhatArrivesWhileThePointerIsOnIt() {
        submit(TestActivity("home", timeToLive: nil))
        send(.hoverBegan)

        submit(TestActivity("note", priority: .incomingCall))

        XCTAssertEqual(state.presentation, .expanded("note"), "the rule itself is unchanged")
    }
}
