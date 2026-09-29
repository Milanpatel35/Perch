import PerchCore
import XCTest

@testable import PerchUI

/// TC-ISL-014 and TC-ISL-015 — the runtime around the reducer.
///
/// The reducer's own behaviour is covered in `PerchCoreTests`. What is tested
/// here is the part that cannot be pure: that exactly one collapse is ever
/// pending, and that the home surface behaves like the floor it is meant to
/// be rather than like a module.
///
/// No test here waits on a real duration. The controller takes its sleep as a
/// parameter precisely so a test can watch the timer without living through
/// it (`TEST-PLAN.md`, level U: "no sleeping").
@MainActor
final class IslandControllerTests: XCTestCase {

    // MARK: - TC-ISL-014

    func test_TC_ISL_014_homeSurfaceIsPreemptedByAnythingAboveAmbient() {
        let controller = IslandController(sleep: { _ in try await Task.never() })
        controller.submit(HomeActivity(collapsedSize: CGSize(width: 186, height: 32)))

        XCTAssertEqual(controller.presented?.id, HomeActivity.identifier)

        controller.submit(StubActivity("alert", priority: .systemAlert))

        XCTAssertEqual(controller.presented?.id, "alert")
    }

    func test_TC_ISL_014_homeSurfaceReturnsWhenTheActivityIsWithdrawn() {
        let controller = IslandController(sleep: { _ in try await Task.never() })
        controller.submit(HomeActivity(collapsedSize: CGSize(width: 186, height: 32)))
        controller.submit(StubActivity("alert", priority: .systemAlert))

        controller.withdraw("alert")

        XCTAssertEqual(controller.presented?.id, HomeActivity.identifier)
        XCTAssertFalse(controller.state.presentation.isIdle)
    }

    func test_TC_ISL_014_homeSurfaceNeverExpires() {
        let controller = IslandController(sleep: { _ in try await Task.never() })
        let home = HomeActivity(collapsedSize: CGSize(width: 186, height: 32))

        XCTAssertNil(home.timeToLive)

        controller.submit(home)
        controller.send(.timeToLiveExpired(HomeActivity.identifier))

        XCTAssertEqual(controller.presented?.id, HomeActivity.identifier)
    }

    /// The whole path from launch to an open island, in one test.
    ///
    /// Worth having as a chain rather than as three separate assertions,
    /// because each link is fine on its own and the *order* is what breaks:
    /// the panel ignores mouse events while the island is idle, so a home
    /// surface that never arrived would leave it permanently unhoverable —
    /// and nothing else in the suite would notice.
    func test_TC_ISL_014_theHomeSurfaceIsWhatMakesTheIslandHoverable() {
        let controller = IslandController(sleep: { _ in try await Task.never() })

        // Before it lands: inert, by design.
        XCTAssertFalse(controller.acceptsMouseEvents)

        controller.submit(HomeActivity(collapsedSize: CGSize(width: 186, height: 32)))

        // The moment it lands the panel starts taking the pointer.
        XCTAssertTrue(controller.acceptsMouseEvents)

        controller.send(.hoverBegan)
        XCTAssertEqual(controller.state.presentation, .expanded(HomeActivity.identifier))

        // Leaving schedules the grace period rather than collapsing at once
        // (TC-ISL-005). The runtime delivers it as an expiry.
        controller.send(.hoverEnded)
        XCTAssertEqual(controller.state.presentation, .expanded(HomeActivity.identifier))

        controller.send(.timeToLiveExpired(HomeActivity.identifier))

        XCTAssertEqual(
            controller.state.presentation,
            .peek(HomeActivity.identifier),
            "the island has to come back down to the notch"
        )
        XCTAssertEqual(
            controller.presented?.id,
            HomeActivity.identifier,
            "coming down must not withdraw the floor"
        )
        XCTAssertTrue(
            controller.acceptsMouseEvents,
            "collapsing back to the home surface must not make the island inert again"
        )

        // And it can be opened again, which is the whole point.
        controller.send(.hoverBegan)
        XCTAssertEqual(controller.state.presentation, .expanded(HomeActivity.identifier))
    }

    func test_TC_ISL_014_islandIsIdleAndInertBeforeTheHomeSurfaceArrives() {
        let controller = IslandController(sleep: { _ in try await Task.never() })

        XCTAssertTrue(controller.state.presentation.isIdle)
        XCTAssertFalse(controller.acceptsMouseEvents)
    }

    // MARK: - TC-ISL-015

    func test_TC_ISL_015_onlyOneCollapseIsEverPending() async {
        let recorder = SleepRecorder()

        // The callbacks are detached before this test returns, and that is
        // not tidiness. The controller's pending sleep is cancelled when the
        // controller deallocates, which happens at some point *after* the
        // test has finished — and a callback still holding an expectation
        // then calls `fulfill()` on a finished test. XCTest raises
        // NSInternalInconsistencyException from whatever thread that lands
        // on, which kills the test process and takes an unrelated test's
        // suite down with it. That is the whole explanation for a string of
        // "crashes" in NowPlayingModuleTests and NowPlayingViewTests that
        // had nothing to do with either.
        defer {
            recorder.onBegin = nil
            recorder.onCancel = nil
        }

        let first = expectation(description: "first collapse scheduled")
        let second = expectation(description: "second collapse scheduled")
        let cancelled = expectation(description: "first collapse cancelled")

        recorder.onBegin = { count in
            if count == 1 { first.fulfill() }
            if count == 2 { second.fulfill() }
        }
        recorder.onCancel = { _ in cancelled.fulfill() }

        let controller = IslandController(sleep: { duration in
            try await recorder.sleep(duration)
        })

        controller.submit(StubActivity("one", timeToLive: .seconds(3)))
        await fulfillment(of: [first], timeout: 2)

        controller.submit(StubActivity("two", priority: .systemAlert, timeToLive: .seconds(3)))
        await fulfillment(of: [second, cancelled], timeout: 2)

        XCTAssertEqual(recorder.begun, 2)
        XCTAssertEqual(recorder.cancellations, 1)

        // Collapse the island so the last pending sleep is cancelled here,
        // while the callbacks above are still the ones listening, rather
        // than at some unpredictable moment after the test has gone.
        controller.send(.collapseRequested)
    }

    func test_TC_ISL_015_anActivityWithNoTimeToLiveSchedulesNothing() {
        let recorder = SleepRecorder()
        let controller = IslandController(sleep: { try await recorder.sleep($0) })

        controller.submit(StubActivity("held", timeToLive: nil))

        XCTAssertEqual(recorder.begun, 0)
    }

    func test_TC_ISL_015_disablingAModuleTakesItsActivitiesWithIt() {
        let controller = IslandController(sleep: { _ in try await Task.never() })
        controller.submit(HomeActivity(collapsedSize: CGSize(width: 186, height: 32)))
        controller.submit(StubActivity("track", source: .nowPlaying, priority: .nowPlaying))

        controller.withdrawAll(from: .nowPlaying)

        XCTAssertEqual(controller.presented?.id, HomeActivity.identifier)
        XCTAssertTrue(controller.queued.allSatisfy { $0.source != .nowPlaying })
    }
}

// MARK: - Fixtures

private struct StubActivity: IslandActivity {
    let id: ActivityID
    let source: ModuleID
    let priority: ActivityPriority
    let timeToLive: Duration?

    init(
        _ id: ActivityID,
        source: ModuleID = .hud,
        priority: ActivityPriority = .ambient,
        timeToLive: Duration? = .seconds(3)
    ) {
        self.id = id
        self.source = source
        self.priority = priority
        self.timeToLive = timeToLive
    }
}

/// Stands in for the clock. Counts what was started and what was cancelled,
/// and never actually waits.
private final class SleepRecorder: @unchecked Sendable {

    private let lock = NSLock()
    private var _begun = 0
    private var _cancellations = 0

    /// Cleared by the test before it returns. A recorder that keeps calling
    /// back after its test has finished is how one test crashes another.
    ///
    /// **`@MainActor` in the type, deliberately.** These are assigned closure
    /// literals written inside a `@MainActor` test case, so they *are*
    /// main-actor isolated whether or not the property says so — and when the
    /// property did not say so, `sleep` below called them from whatever
    /// thread its continuation resumed on. Swift 6 catches that at runtime
    /// and kills the process:
    ///
    ///     data race detected: @MainActor function at
    ///     IslandControllerTests.swift:86 was not called on the main thread
    ///
    /// Intermittently, because it depends on which executor the continuation
    /// lands on — it passed locally and on macOS 15 and failed on macOS 14,
    /// after every assertion in the suite had already passed. Saying the
    /// isolation out loud makes the compiler insert the hop.
    var onBegin: (@MainActor @Sendable (Int) -> Void)? {
        get { lock.withLock { _onBegin } }
        set { lock.withLock { _onBegin = newValue } }
    }

    var onCancel: (@MainActor @Sendable (Int) -> Void)? {
        get { lock.withLock { _onCancel } }
        set { lock.withLock { _onCancel = newValue } }
    }

    private var _onBegin: (@MainActor @Sendable (Int) -> Void)?
    private var _onCancel: (@MainActor @Sendable (Int) -> Void)?

    var begun: Int { lock.withLock { _begun } }
    var cancellations: Int { lock.withLock { _cancellations } }

    func sleep(_ duration: Duration) async throws {
        let count = lock.withLock {
            _begun += 1
            return _begun
        }
        await onBegin?(count)

        do {
            try await Task.sleep(for: .seconds(86_400))
        } catch {
            let cancelled = lock.withLock {
                _cancellations += 1
                return _cancellations
            }
            // `await`, because the handler is main-actor isolated and this
            // continuation is not guaranteed to be.
            await onCancel?(cancelled)
            throw error
        }
    }
}

private extension Task where Success == Never, Failure == Never {
    /// Suspends until cancelled.
    ///
    /// `Task.sleep` throws the moment its task is cancelled, so a duration
    /// nobody will ever wait out is exactly the right stand-in for "armed,
    /// still pending". No test here elapses a single millisecond of it.
    static func never() async throws {
        try await Self.sleep(for: .seconds(86_400))
    }
}
