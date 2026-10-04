import XCTest

@testable import PerchUI

/// Covers `TEST-PLAN.md` § UPD for what Settings shows and asks for.
@MainActor
final class SoftwareUpdatesTests: XCTestCase {

    private final class Recorder {
        var checks = 0
        var automatic: [Bool] = []
    }

    private func make(_ recorder: Recorder, automatic: Bool = true) -> SoftwareUpdates {
        SoftwareUpdates(
            checksAutomatically: automatic,
            lastChecked: nil,
            check: { recorder.checks += 1 },
            setChecksAutomatically: { recorder.automatic.append($0) }
        )
    }

    // MARK: - TC-UPD-005

    func test_TC_UPD_005_theButtonChecksOnceWhileACheckRuns() {
        let recorder = Recorder()
        let updates = make(recorder)

        updates.checkNow()
        updates.began()
        updates.checkNow()

        XCTAssertEqual(recorder.checks, 1)
        XCTAssertEqual(updates.status, .checking)
        XCTAssertFalse(updates.canCheck)
    }

    func test_TC_UPD_005_theOutcomeIsShownAndStamped() {
        let updates = make(Recorder())
        let when = Date(timeIntervalSince1970: 1_791_000_000)

        updates.began()
        updates.finished(.available(version: "0.13.0"), at: when)

        XCTAssertEqual(updates.status, .available(version: "0.13.0"))
        XCTAssertEqual(updates.lastChecked, when)
        XCTAssertTrue(updates.canCheck)
    }

    func test_TC_UPD_005_turningAutomaticChecksOffReachesTheUpdater() {
        let recorder = Recorder()
        let updates = make(recorder, automatic: true)

        updates.checksAutomatically = false
        updates.checksAutomatically = false

        XCTAssertEqual(recorder.automatic, [false], "written once, not on every set")
    }

    // MARK: - TC-UPD-002

    func test_TC_UPD_002_aCheckThatEndsUnsaidLeavesTheButtonUsable() {
        let updates = make(Recorder())

        updates.began()
        updates.settle()

        XCTAssertEqual(updates.status, .unknown)
        XCTAssertTrue(updates.canCheck)
    }
}
