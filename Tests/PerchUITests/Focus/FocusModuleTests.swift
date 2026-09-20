import AppKit
import PerchCore
import SwiftUI
import XCTest

@testable import PerchUI

/// Covers `TEST-PLAN.md` § FOC for the parts that need the real module.
///
/// The clock is injected, so nothing here waits. A test that slept for
/// twenty-five minutes would not be a test.
@MainActor
final class FocusModuleTests: XCTestCase {

    nonisolated(unsafe) private var directory = URL(fileURLWithPath: NSTemporaryDirectory())

    /// Moved by the tests; the service reads it through the injected closure.
    nonisolated(unsafe) private var clock = Date(timeIntervalSinceReferenceDate: 0)

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("perch-focus-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        clock = Date(timeIntervalSinceReferenceDate: 0)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        try super.tearDownWithError()
    }

    private struct Harness {
        let focus: FocusService
        let island: IslandController
    }

    private func makeService() -> Harness {
        let island = IslandController(sleep: { _ in try await Task.sleep(for: .seconds(86_400)) })
        let service = FocusService(
            island: island,
            directory: directory,
            now: { [self] in clock }
        )
        return Harness(focus: service, island: island)
    }

    private func advanceClock(byMinutes minutes: Double) {
        clock = clock.addingTimeInterval(minutes * 60)
    }

    // MARK: - TC-FOC-001

    func test_TC_FOC_001_startingPutsTheCountdownOnTheIsland() {
        let harness = makeService()
        harness.focus.activate()

        harness.focus.start()

        XCTAssertEqual(harness.island.presented?.id, FocusActivity.identifier)
        XCTAssertEqual(harness.island.presented?.source, .focus)
        XCTAssertTrue(harness.focus.timer.isRunning)
    }

    /// The countdown is not an event that expires — the session decides when
    /// it is over, not the island's clock.
    func test_TC_FOC_001_theCountdownNeverExpiresOnItsOwn() {
        let activity = FocusActivity(
            timer: PomodoroTimer(),
            sessionsToday: 0,
            streakDays: 0
        )

        XCTAssertNil(activity.timeToLive)
        XCTAssertEqual(activity.priority, .ambient)
    }

    // MARK: - TC-FOC-002

    /// The priority rule this module exists to exercise: a finished session
    /// takes the island from whatever is playing (`CLAUDE.md` §3).
    func test_TC_FOC_002_aFinishedSessionOutranksNowPlaying() {
        let finished = FocusFinishedActivity(
            finished: .work,
            next: .shortBreak,
            sessionsToday: 1,
            streakDays: 1
        )

        XCTAssertEqual(finished.priority, .timerFinishing)
        XCTAssertGreaterThan(finished.priority, ActivityPriority.nowPlaying)
        XCTAssertGreaterThan(finished.priority, ActivityPriority.ambient)
    }

    /// Long enough to notice from across a desk. A finished Pomodoro that
    /// vanishes in two seconds is one you miss.
    func test_TC_FOC_002_theFinishedAlertStaysLongEnoughToBeSeen() {
        let finished = FocusFinishedActivity(
            finished: .work,
            next: .shortBreak,
            sessionsToday: 1,
            streakDays: 1
        )

        XCTAssertGreaterThan(finished.timeToLive?.seconds ?? 0, 8)
    }

    // MARK: - TC-FOC-003

    func test_TC_FOC_003_pausingAndResumingKeepsTheRemainingTime() {
        let harness = makeService()
        harness.focus.activate()
        harness.focus.start()

        advanceClock(byMinutes: 10)
        harness.focus.toggle()
        XCTAssertTrue(harness.focus.timer.isPaused)
        XCTAssertEqual(harness.focus.timer.remaining(at: clock), .seconds(15 * 60))

        advanceClock(byMinutes: 60)
        XCTAssertEqual(harness.focus.timer.remaining(at: clock), .seconds(15 * 60))

        harness.focus.toggle()
        XCTAssertTrue(harness.focus.timer.isRunning)
        XCTAssertEqual(harness.focus.timer.remaining(at: clock), .seconds(15 * 60))
    }

    func test_TC_FOC_003_stoppingClearsTheIsland() {
        let harness = makeService()
        harness.focus.activate()
        harness.focus.start()

        harness.focus.stop()

        XCTAssertTrue(harness.focus.timer.isIdle)
        XCTAssertNil(harness.island.presented)
    }

    // MARK: - TC-FOC-005

    func test_TC_FOC_005_theStreakIsPersistedAcrossARelaunch() {
        let first = makeService()
        first.focus.activate()
        first.focus.start()

        advanceClock(byMinutes: 25)
        // The scheduled wake-up fires in real time. `handleWake()` is the
        // same call it makes, and is what the sleep path uses too.
        first.focus.handleWake()

        XCTAssertEqual(first.focus.streak.totalSessions, 1)
        first.focus.deactivate()

        let second = makeService()
        second.focus.activate()
        XCTAssertEqual(second.focus.streak.totalSessions, 1)
        XCTAssertEqual(second.focus.streak.streak(on: clock), 1)
    }

    // MARK: - Lifecycle

    func test_activatingTwiceIsNotTwiceTheWork() {
        let harness = makeService()

        harness.focus.activate()
        harness.focus.activate()
        XCTAssertTrue(harness.focus.isActive)

        harness.focus.deactivate()
        XCTAssertFalse(harness.focus.isActive)
    }

    func test_deactivatingWhenAlreadyOffIsSafe() {
        let harness = makeService()

        harness.focus.deactivate()
        harness.focus.deactivate()
        XCTAssertFalse(harness.focus.isActive)
    }

    /// The §5.1 contract: nothing running, nothing scheduled, nothing on the
    /// island.
    func test_TC_FOC_006_theModuleHoldsNothingWhileItIsOff() {
        let harness = makeService()

        harness.focus.activate()
        harness.focus.start()
        harness.focus.deactivate()

        XCTAssertFalse(harness.focus.isActive)
        XCTAssertNil(harness.island.presented)

        // And an off module refuses to be driven.
        harness.focus.start()
        harness.focus.toggle()
        XCTAssertNil(harness.island.presented)
    }

    /// A session that was running when Perch quit is not resumed by itself.
    /// The timer is a thing you start on purpose.
    func test_TC_FOC_007_aSessionIsNotSilentlyResumedOnLaunch() {
        let harness = makeService()
        harness.focus.activate()
        harness.focus.start()
        harness.focus.deactivate()

        let relaunched = makeService()
        relaunched.focus.activate()

        XCTAssertFalse(relaunched.focus.timer.isRunning)
    }

    // MARK: - Presentation

    private func drawnPixels(_ view: AnyView, size: CGSize) -> Int {
        let island = IslandController(sleep: { _ in try await Task.sleep(for: .seconds(86_400)) })
        let modules = ModuleHost(switchboard: ModuleSwitchboard(), island: island)
        let host = NSHostingView(rootView: AnyView(view.environmentObject(modules)))
        host.frame = CGRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()

        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return 0 }
        host.cacheDisplay(in: host.bounds, to: rep)

        guard let data = rep.bitmapData else { return 0 }
        let samples = rep.samplesPerPixel
        var drawn = 0
        for pixel in 0..<(rep.pixelsWide * rep.pixelsHigh)
        where data[(pixel * samples) + (samples - 1)] > 0 {
            drawn += 1
        }
        return drawn
    }

    func test_everyPhaseDrawsRunningAndPaused() {
        for phase in PomodoroTimer.Phase.allCases {
            var timer = PomodoroTimer()
            timer.start(phase, now: Date())

            let running = FocusActivity(timer: timer, sessionsToday: 2, streakDays: 3)
            XCTAssertGreaterThan(
                drawnPixels(running.peekView(), size: running.peekSize),
                50,
                "\(phase) running drew nothing"
            )
            XCTAssertGreaterThan(
                drawnPixels(running.expandedView(), size: running.expandedSize),
                300,
                "\(phase) expanded drew nothing"
            )

            timer.pause(now: Date())
            let paused = FocusActivity(timer: timer, sessionsToday: 2, streakDays: 3)
            XCTAssertGreaterThan(
                drawnPixels(paused.peekView(), size: paused.peekSize),
                50,
                "\(phase) paused drew nothing"
            )
        }
    }

    func test_theFinishedPanelDraws() {
        let finished = FocusFinishedActivity(
            finished: .work,
            next: .shortBreak,
            sessionsToday: 3,
            streakDays: 5
        )

        XCTAssertGreaterThan(drawnPixels(finished.peekView(), size: finished.peekSize), 50)
        XCTAssertGreaterThan(
            drawnPixels(finished.expandedView(), size: finished.expandedSize),
            300
        )
    }

    /// "24:58", and never a negative or a NaN.
    func test_theClockLabelIsAlwaysReadable() {
        var timer = PomodoroTimer()
        XCTAssertEqual(timer.remainingClock, "0:00")

        timer.start(now: Date())
        XCTAssertEqual(timer.remainingClock, "25:00")

        timer.pause(now: Date().addingTimeInterval(24 * 60 + 2))
        XCTAssertEqual(timer.remainingClock, "0:58")
    }
}
