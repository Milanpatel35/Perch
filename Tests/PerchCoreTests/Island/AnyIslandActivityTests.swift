import XCTest

@testable import PerchCore

/// TC-ISL-013 — the box every module's activity travels in.
///
/// Worth its own test because the failure mode is silent: a nested box still
/// compiles, still queues, still presents, and simply stops matching the
/// `as?` cast the view layer uses to find the module's own type. The island
/// would go blank and nothing would log.
final class AnyIslandActivityTests: XCTestCase {

    // MARK: - TC-ISL-013

    func test_TC_ISL_013_erasurePreservesEveryPropertyTheReducerReads() {
        let original = TestActivity(
            "media",
            source: .nowPlaying,
            priority: .incomingCall,
            timeToLive: .seconds(7),
            isExpandable: false
        )

        let erased = AnyIslandActivity(original)

        XCTAssertEqual(erased.id, original.id)
        XCTAssertEqual(erased.source, original.source)
        XCTAssertEqual(erased.priority, original.priority)
        XCTAssertEqual(erased.timeToLive, original.timeToLive)
        XCTAssertEqual(erased.isExpandable, original.isExpandable)
    }

    func test_TC_ISL_013_rewrappingDoesNotNestTheBox() {
        let original = TestActivity("media")

        let once = AnyIslandActivity(original)
        let twice = AnyIslandActivity(once)

        XCTAssertNotNil(twice.unwrap(as: TestActivity.self))
        XCTAssertNil(twice.base as? AnyIslandActivity)
        XCTAssertEqual(twice.unwrap(as: TestActivity.self)?.id, original.id)
    }

    func test_TC_ISL_013_unwrappingTheWrongTypeReturnsNilRatherThanTrapping() {
        let erased = AnyIslandActivity(TestActivity("media"))
        XCTAssertNil(erased.unwrap(as: OtherActivity.self))
    }

    func test_TC_ISL_013_erasedActivitiesQueueByTheSameRules() {
        var queue = ActivityQueue<AnyIslandActivity>()
        queue.submit(AnyIslandActivity(TestActivity("ambient", priority: .ambient)))
        queue.submit(AnyIslandActivity(TestActivity("alert", priority: .systemAlert)))

        XCTAssertEqual(queue.front?.id, "alert")
    }

    /// A second conformer, purely so the failed-cast case has something real
    /// to fail against.
    private struct OtherActivity: IslandActivity {
        let id: ActivityID = "other"
        let source: ModuleID = .battery
        let priority: ActivityPriority = .ambient
    }
}
