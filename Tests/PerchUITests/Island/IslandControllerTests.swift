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

    func test_TC_ISL_014_islandIsIdleAndInertBeforeTheHomeSurfaceArrives() {
        let controller = IslandController(sleep: { _ in try await Task.never() })

        XCTAssertTrue(controller.state.presentation.isIdle)
        XCTAssertFalse(controller.acceptsMouseEvents)
    }

    // MARK: - TC-ISL-015

    func test_TC_ISL_015_onlyOneCollapseIsEverPending() async {
        let recorder = SleepRecorder()
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

    var onBegin: ((Int) -> Void)?
    var onCancel: ((Int) -> Void)?

    var begun: Int { lock.withLock { _begun } }
    var cancellations: Int { lock.withLock { _cancellations } }

    func sleep(_ duration: Duration) async throws {
        let count = lock.withLock {
            _begun += 1
            return _begun
        }
        onBegin?(count)

        do {
            try await Task.sleep(for: .seconds(86_400))
        } catch {
            let cancelled = lock.withLock {
                _cancellations += 1
                return _cancellations
            }
            onCancel?(cancelled)
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
