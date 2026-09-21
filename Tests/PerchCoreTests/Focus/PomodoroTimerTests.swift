import XCTest

@testable import PerchCore

/// Covers `TEST-PLAN.md` § FOC at unit level.
///
/// Every test drives the clock by hand. Nothing here waits, nothing sleeps,
/// and the whole of a four-session cycle runs in microseconds — which is the
/// point of the timer being wall-clock rather than a countdown.
final class PomodoroTimerTests: XCTestCase {

    /// A fixed moment, so every assertion is about arithmetic rather than
    /// about when the suite happened to run.
    private let epoch = Date(timeIntervalSinceReferenceDate: 0)

    private func at(_ minutes: Double) -> Date {
        epoch.addingTimeInterval(minutes * 60)
    }

    // MARK: - TC-FOC-001

    func test_TC_FOC_001_startingAWorkSessionPutsTwentyFiveMinutesOnTheClock() {
        var timer = PomodoroTimer()
        timer.start(now: epoch)

        XCTAssertTrue(timer.isRunning)
        XCTAssertEqual(timer.phase, .work)
        XCTAssertEqual(timer.remaining(at: epoch), .seconds(25 * 60))
        XCTAssertEqual(timer.endsAt, at(25))
    }

    func test_TC_FOC_001_theCountdownIsComputedNotTicked() {
        var timer = PomodoroTimer()
        timer.start(now: epoch)

        XCTAssertEqual(timer.remaining(at: at(1)), .seconds(24 * 60))
        XCTAssertEqual(timer.remaining(at: at(24)), .seconds(60))

        // And never goes negative: a phase that is over has nothing left,
        // not a debt.
        XCTAssertEqual(timer.remaining(at: at(30)), .zero)
    }

    func test_TC_FOC_001_progressRunsFromZeroToOne() {
        var timer = PomodoroTimer()
        timer.start(now: epoch)

        XCTAssertEqual(timer.progress(at: epoch) ?? -1, 0, accuracy: 0.0001)
        XCTAssertEqual(timer.progress(at: at(12.5)) ?? -1, 0.5, accuracy: 0.0001)
        XCTAssertEqual(timer.progress(at: at(25)) ?? -1, 1, accuracy: 0.0001)
        XCTAssertEqual(timer.progress(at: at(99)) ?? -1, 1, accuracy: 0.0001)
    }

    func test_TC_FOC_001_durationsAreConfigurable() {
        var timer = PomodoroTimer(
            configuration: .init(work: .seconds(50 * 60), shortBreak: .seconds(10 * 60))
        )
        timer.start(now: epoch)

        XCTAssertEqual(timer.remaining(at: epoch), .seconds(50 * 60))
    }

    // MARK: - TC-FOC-002

    func test_TC_FOC_002_aSessionThatReachesItsEndReportsThePhaseThatFinished() {
        var timer = PomodoroTimer()
        timer.start(now: epoch)

        XCTAssertNil(timer.advance(to: at(24)), "it is not over yet")
        XCTAssertEqual(timer.advance(to: at(25)), .work)
    }

    /// Advancing twice must not fire twice — the scheduled wake-up and the
    /// wake-from-sleep handler both call it, and they can both be right.
    func test_TC_FOC_009_advancingPastTheEndOnlyFiresOnce() {
        var timer = PomodoroTimer()
        timer.start(now: epoch)

        XCTAssertEqual(timer.advance(to: at(25)), .work)
        XCTAssertNil(timer.advance(to: at(26)))
        XCTAssertNil(timer.advance(to: at(90)))
    }

    /// The next phase is queued but not started. A break that begins by
    /// itself while you are still typing is a break you do not take.
    func test_TC_FOC_002_theNextPhaseIsQueuedRatherThanStarted() {
        var timer = PomodoroTimer()
        timer.start(now: epoch)
        timer.advance(to: at(25))

        XCTAssertTrue(timer.isPaused)
        XCTAssertEqual(timer.phase, .shortBreak)
        XCTAssertEqual(timer.remaining(at: at(25)), .seconds(5 * 60))
    }

    // MARK: - TC-FOC-003

    func test_TC_FOC_003_pauseAndResumePreserveTheRemainingTimeExactly() {
        var timer = PomodoroTimer()
        timer.start(now: epoch)

        timer.pause(now: at(10))
        XCTAssertTrue(timer.isPaused)
        XCTAssertEqual(timer.remaining(at: at(10)), .seconds(15 * 60))

        // Paused time does not count. An hour later it is still fifteen
        // minutes.
        XCTAssertEqual(timer.remaining(at: at(70)), .seconds(15 * 60))

        timer.resume(now: at(70))
        XCTAssertTrue(timer.isRunning)
        XCTAssertEqual(timer.remaining(at: at(70)), .seconds(15 * 60))
        XCTAssertEqual(timer.endsAt, at(85))
    }

    func test_TC_FOC_003_aPausedTimerNeverFinishesOnItsOwn() {
        var timer = PomodoroTimer()
        timer.start(now: epoch)
        timer.pause(now: at(10))

        XCTAssertNil(timer.advance(to: at(1000)))
    }

    func test_TC_FOC_003_toggleWalksIdleRunningPaused() {
        var timer = PomodoroTimer()

        timer.toggle(now: epoch)
        XCTAssertTrue(timer.isRunning)

        timer.toggle(now: at(5))
        XCTAssertTrue(timer.isPaused)

        timer.toggle(now: at(6))
        XCTAssertTrue(timer.isRunning)
    }

    // MARK: - TC-FOC-004

    /// The sleep case, and the reason nothing counts down: a Mac asleep for
    /// forty minutes wakes to a session that is simply over. No accounting
    /// happens because nothing was ever counting.
    func test_TC_FOC_004_aSessionSurvivesSleepByBeingWallClock() {
        var timer = PomodoroTimer()
        timer.start(now: epoch)

        // Asleep from 00:05 to 00:45.
        XCTAssertEqual(timer.advance(to: at(45)), .work)
    }

    func test_TC_FOC_004_sleepingThroughPartOfASessionLeavesTheRestOfIt() {
        var timer = PomodoroTimer()
        timer.start(now: epoch)

        XCTAssertNil(timer.advance(to: at(20)))
        XCTAssertEqual(timer.remaining(at: at(20)), .seconds(5 * 60))
    }

    /// A clock that jumps backwards — a manual change, an NTP step — must not
    /// finish a phase early, and must not claim a 25-minute session has 85
    /// minutes left, which is what the raw arithmetic says.
    func test_TC_FOC_008_aClockThatGoesBackwardsDoesNotBreakTheTimer() {
        var timer = PomodoroTimer()
        timer.start(now: epoch)

        XCTAssertNil(timer.advance(to: at(-60)))
        XCTAssertEqual(timer.remaining(at: at(-60)), .seconds(25 * 60))
        XCTAssertEqual(timer.progress(at: at(-60)) ?? -1, 0, accuracy: 0.0001)

        // And the real end is still the real end: the clamp is on the display,
        // not on the deadline.
        XCTAssertEqual(timer.endsAt, at(25))
        XCTAssertEqual(timer.advance(to: at(25)), .work)
    }

    // MARK: - Cycles

    func test_theLongBreakArrivesAfterFourWorkSessions() {
        var timer = PomodoroTimer()
        var now = epoch

        for session in 1...4 {
            timer.start(.work, now: now)
            now = now.addingTimeInterval(25 * 60)
            XCTAssertEqual(timer.advance(to: now), .work)

            let expected: PomodoroTimer.Phase = session == 4 ? .longBreak : .shortBreak
            XCTAssertEqual(timer.phase, expected, "after session \(session)")

            timer.start(expected, now: now)
            now = now.addingTimeInterval(timer.configuration.duration(of: expected).seconds)
            XCTAssertEqual(timer.advance(to: now), expected)
        }
    }

    func test_aBreakIsAlwaysFollowedByWork() {
        let timer = PomodoroTimer()

        XCTAssertEqual(timer.next(after: .shortBreak), .work)
        XCTAssertEqual(timer.next(after: .longBreak), .work)
    }

    /// Stopping is "I am done", not "hold on": it clears the cycle so the
    /// next session starts a fresh set of four.
    func test_stoppingForgetsTheCycle() {
        var timer = PomodoroTimer()
        timer.start(now: epoch)
        timer.advance(to: at(25))
        XCTAssertEqual(timer.completedInCycle, 1)

        timer.stop()
        XCTAssertTrue(timer.isIdle)
        XCTAssertEqual(timer.completedInCycle, 0)
        XCTAssertNil(timer.remaining(at: epoch))
    }

    /// A configuration with a nonsense cycle length must not divide by zero.
    func test_aZeroLengthCycleDoesNotTrap() {
        var timer = PomodoroTimer(configuration: .init(sessionsBeforeLongBreak: 0))
        timer.start(now: epoch)
        timer.advance(to: at(25))

        XCTAssertEqual(timer.phase, .longBreak)
    }
}
