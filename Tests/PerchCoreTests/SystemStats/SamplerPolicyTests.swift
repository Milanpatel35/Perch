import XCTest

@testable import PerchCore

/// Covers `TEST-PLAN.md` § SYS for the rule the module exists under —
/// TC-SYS-009, TC-SYS-010 and TC-SYS-014.
///
/// TC-SYS-009 is the one that matters: collapsed with no gauge showing means
/// **no timer exists**. Not a slower timer. The policy returns `nil` rather
/// than a long interval so that a caller cannot treat it as a default and
/// quietly break the promise.
final class SamplerPolicyTests: XCTestCase {

    // MARK: - TC-SYS-009

    func test_TC_SYS_009_nothingOnScreenMeansNoSamplerAtAll() {
        XCTAssertNil(SamplerPolicy.interval(for: .none))
        XCTAssertFalse(SamplerPolicy.samples(.none))
    }

    /// The optional is the design. A policy returning a very long interval
    /// would still be a timer, and a timer is exactly what §5.1 forbids.
    func test_TC_SYS_009_theAnswerIsAbsenceNotALongInterval() {
        let interval = SamplerPolicy.interval(for: .none)
        XCTAssertNil(interval, "a long interval is still a timer")
    }

    // MARK: - TC-SYS-010

    func test_TC_SYS_010_theMicroGaugeSamplesEveryFiveSecondsAndExpandedEveryTwo() {
        XCTAssertEqual(SamplerPolicy.interval(for: .microGauge), .seconds(5))
        XCTAssertEqual(SamplerPolicy.interval(for: .expanded), .seconds(2))
    }

    func test_TC_SYS_010_theGaugeSamplesMoreSlowlyThanTheGrid() {
        guard
            let gauge = SamplerPolicy.interval(for: .microGauge),
            let expanded = SamplerPolicy.interval(for: .expanded)
        else { return XCTFail("both visible states sample") }

        XCTAssertGreaterThan(gauge, expanded)
    }

    func test_everyVisibleDemandSamplesAndTheInvisibleOneDoesNot() {
        XCTAssertTrue(SamplerPolicy.samples(.microGauge))
        XCTAssertTrue(SamplerPolicy.samples(.expanded))
        XCTAssertFalse(SamplerPolicy.samples(.none))
    }

    // MARK: - TC-SYS-014

    func test_TC_SYS_014_historyKeepsExactlySixtyPointsByDefault() {
        var history = StatHistory()

        for index in 0..<500 {
            history.record(Double(index))
        }

        XCTAssertEqual(history.values.count, 60)
        XCTAssertEqual(history.values.first, 440)
        XCTAssertEqual(history.latest, 499)
    }

    /// A flat line at zero must draw as a flat line at the bottom, not as a
    /// blank box — which is what a ceiling of zero would produce.
    func test_TC_SYS_014_anIdleHistoryStillHasACeiling() {
        var history = StatHistory()
        for _ in 0..<10 { history.record(0) }

        XCTAssertEqual(history.ceiling(), 1)
        XCTAssertGreaterThan(history.ceiling(minimum: 0.001), 0)
    }

    /// A rate graph scales to what actually happened rather than to a guess.
    func test_TC_SYS_014_aRateHistoryScalesToItsTallestPoint() {
        var history = StatHistory()
        history.record(1_000)
        history.record(4_000)
        history.record(2_000)

        XCTAssertEqual(history.ceiling(minimum: 1), 4_000)
    }

    func test_anEmptyHistoryIsEmptyAndHasNoLatest() {
        let history = StatHistory()
        XCTAssertTrue(history.isEmpty)
        XCTAssertNil(history.latest)
    }

    func test_clearingKeepsTheCapacity() {
        var history = StatHistory(capacity: 10)
        for index in 0..<10 { history.record(Double(index)) }
        history.clear()

        XCTAssertTrue(history.isEmpty)
        XCTAssertEqual(history.capacity, 10)
    }
}
