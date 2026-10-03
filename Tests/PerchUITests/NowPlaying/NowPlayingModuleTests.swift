import Defaults
import PerchCore
import XCTest

@testable import PerchUI

/// Covers `TEST-PLAN.md` § MED for the parts that need the module rather than
/// just the maths: the activity's own shape, and the promise that switching
/// the module off leaves nothing behind.
@MainActor
final class NowPlayingModuleTests: XCTestCase {

    private let epoch = Date(timeIntervalSinceReferenceDate: 1_000_000)

    private var savedSneakPeek = true

    /// Sneak peek off for every test here, and that is the fix for #57.
    ///
    /// With it on, the first track gives its activity a two-second time to
    /// live, and the island schedules a collapse as a `Task`. A test that
    /// then withdrew the track — `test_playbackStoppingTakesTheIslandBack`,
    /// and only that one — cancelled that task *inside* the test method,
    /// and about one CI run in four the Swift runtime aborted in
    /// `swift_task_dealloc_specific` beneath XCTest's harness. Never
    /// reproduced locally. With no time to live, no collapse task exists,
    /// so there is nothing to cancel; the peek behaviour itself is covered
    /// by `test_TC_MED_003_onlyASneakPeekExpires` without a service.
    override func setUp() async throws {
        savedSneakPeek = Defaults[.nowPlayingSneakPeek]
        Defaults[.nowPlayingSneakPeek] = false
    }

    override func tearDown() async throws {
        Defaults[.nowPlayingSneakPeek] = savedSneakPeek
    }

    private func snapshot(
        title: String = "So What",
        rate: Double = 1
    ) -> NowPlayingSnapshot {
        NowPlayingSnapshot(
            title: title,
            artist: "Miles Davis",
            album: "Kind of Blue",
            progress: PlaybackProgress(
                elapsed: .seconds(10),
                rate: rate,
                asOf: epoch,
                duration: .seconds(545)
            ),
            sourceBundleID: "com.apple.Music"
        )
    }

    /// Waits for the service's coalesced read to land. The main run loop
    /// keeps turning while `wait` blocks, so the main-actor read completes.
    private func waitForRefresh(_ service: NowPlayingService) {
        let done = expectation(description: "the read landed")
        Task {
            await service.awaitPendingRefresh()
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
    }

    // MARK: - TC-MED-003

    func test_TC_MED_003_everyTrackSharesOneActivityIdentity() {
        // Not per-track, deliberately: a track change must replace what is on
        // the island rather than queue a second activity behind it.
        let first = NowPlayingActivity(snapshot: snapshot(title: "So What"))
        let second = NowPlayingActivity(snapshot: snapshot(title: "Freddie Freeloader"))

        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(first.id, NowPlayingActivity.identifier)
    }

    func test_TC_MED_003_resubmittingUpdatesTheIslandWithoutRePresenting() {
        let island = IslandController(sleep: { _ in try await Task.sleep(for: .seconds(86_400)) })
        island.submit(NowPlayingActivity(snapshot: snapshot(title: "So What")))

        let presentation = island.state.presentation
        island.submit(NowPlayingActivity(snapshot: snapshot(title: "Blue in Green")))

        XCTAssertEqual(island.state.presentation, presentation)
        XCTAssertEqual(island.queued.count, 1)
    }

    func test_TC_MED_003_onlyASneakPeekExpires() {
        // Music is ambient. The island keeps the artwork up for as long as
        // something is playing, and only the two-second track-change peek has
        // a clock on it.
        XCTAssertNil(NowPlayingActivity(snapshot: snapshot()).timeToLive)
        XCTAssertEqual(
            NowPlayingActivity(snapshot: snapshot(), isSneakPeek: true).timeToLive,
            .seconds(2)
        )
    }

    func test_nowPlayingOutranksAmbientButNotAnAlert() {
        let media = NowPlayingActivity(snapshot: snapshot())

        XCTAssertGreaterThan(media.priority, .ambient)
        XCTAssertLessThan(media.priority, .systemAlert)
        XCTAssertLessThan(media.priority, .timerFinishing)
    }

    // MARK: - TC-MED-007

    func test_TC_MED_007_switchingTheModuleOffLeavesNothingBehind() {
        let island = IslandController(sleep: { _ in try await Task.sleep(for: .seconds(86_400)) })
        let source = FakeNowPlayingSource()
        let service = NowPlayingService(island: island, source: source)

        service.activate()
        // Whatever the source can report on this machine, switching
        // the module on must never leave `isActive` disagreeing with reality.
        XCTAssertTrue(service.isActive)

        island.submit(NowPlayingActivity(snapshot: snapshot()))
        XCTAssertNotNil(island.presented)

        service.deactivate()

        XCTAssertFalse(service.isActive)
        XCTAssertNil(service.snapshot)
        XCTAssertFalse(source.isRunning, "the source was left watching")
        XCTAssertTrue(island.queued.allSatisfy { $0.source != .nowPlaying })
        XCTAssertTrue(island.state.presentation.isIdle)
    }

    func test_TC_MED_007_theModuleSurvivesBeingSwitchedOnAndOffRepeatedly() {
        // Somebody flicking the switch in Preferences. Cheap to test, and the
        // kind of bug a user finds in about ten seconds.
        let island = IslandController(sleep: { _ in try await Task.sleep(for: .seconds(86_400)) })
        let source = FakeNowPlayingSource()
        let service = NowPlayingService(island: island, source: source)

        for _ in 0..<4 {
            service.activate()
            XCTAssertTrue(service.isActive)
            service.deactivate()
            XCTAssertFalse(service.isActive)
        }

        XCTAssertNil(service.snapshot)
        XCTAssertFalse(source.isRunning)
        XCTAssertEqual(source.startCount, 4)
        XCTAssertEqual(source.stopCount, 4)
        XCTAssertTrue(island.state.presentation.isIdle)
    }

    /// The module's whole job, end to end, with a source it can be given.
    func test_TC_MED_001_playbackStartingPutsTheTrackOnTheIsland() {
        let island = IslandController(sleep: { _ in try await Task.sleep(for: .seconds(86_400)) })
        let source = FakeNowPlayingSource()
        let service = NowPlayingService(island: island, source: source)

        source.snapshot = snapshot(title: "So What")
        service.activate()
        waitForRefresh(service)

        XCTAssertEqual(service.snapshot?.title, "So What")
        XCTAssertEqual(island.presented?.id, NowPlayingActivity.identifier)
        service.deactivate()
    }

    func test_TC_MED_003_aTrackChangeUpdatesInPlaceRatherThanQueueingASecond() {
        let island = IslandController(sleep: { _ in try await Task.sleep(for: .seconds(86_400)) })
        let source = FakeNowPlayingSource()
        let service = NowPlayingService(island: island, source: source)

        source.snapshot = snapshot(title: "So What")
        service.activate()
        waitForRefresh(service)

        source.emitChange(snapshot(title: "Blue in Green"))
        waitForRefresh(service)

        XCTAssertEqual(service.snapshot?.title, "Blue in Green")
        XCTAssertEqual(island.queued.filter { $0.source == .nowPlaying }.count, 1)
        service.deactivate()
    }

    func test_playbackStoppingTakesTheIslandBack() {
        let island = IslandController(sleep: { _ in try await Task.sleep(for: .seconds(86_400)) })
        let source = FakeNowPlayingSource()
        let service = NowPlayingService(island: island, source: source)

        source.snapshot = snapshot()
        service.activate()
        waitForRefresh(service)
        XCTAssertNotNil(island.presented)

        source.emitChange(nil)
        waitForRefresh(service)

        XCTAssertNil(service.snapshot)
        XCTAssertTrue(island.state.presentation.isIdle)
        service.deactivate()
    }

    func test_transportButtonsReachTheSource() {
        let island = IslandController(sleep: { _ in try await Task.sleep(for: .seconds(86_400)) })
        let source = FakeNowPlayingSource()
        let service = NowPlayingService(island: island, source: source)

        service.togglePlayPause()
        service.nextTrack()
        service.previousTrack()
        service.seek(to: .seconds(42))

        XCTAssertEqual(source.commands, [.togglePlayPause, .nextTrack, .previousTrack])
        XCTAssertEqual(source.seeks, [.seconds(42)])
    }

    func test_aSourceThatIsUnavailableSaysSoRatherThanShowingAnEmptyIsland() {
        let island = IslandController(sleep: { _ in try await Task.sleep(for: .seconds(86_400)) })
        let source = FakeNowPlayingSource()
        source.isAvailable = false
        let service = NowPlayingService(island: island, source: source)

        service.activate()

        XCTAssertTrue(service.isUnavailable)
        XCTAssertNil(island.presented)
    }

    func test_TC_MED_007_deactivatingTwiceIsSafe() {
        let island = IslandController(sleep: { _ in try await Task.sleep(for: .seconds(86_400)) })
        let source = FakeNowPlayingSource()
        let service = NowPlayingService(island: island, source: source)

        service.activate()
        service.deactivate()
        service.deactivate()

        XCTAssertFalse(service.isActive)
    }

    func test_TC_MED_007_theModuleHostIsWhatSwitchesAModuleOnAndOff() {
        let island = IslandController(sleep: { _ in try await Task.sleep(for: .seconds(86_400)) })
        let switchboard = ModuleSwitchboard()
        let host = ModuleHost(switchboard: switchboard, island: island)
        let source = FakeNowPlayingSource()
        let service = NowPlayingService(island: island, source: source)

        switchboard.setEnabled(.nowPlaying, false)
        host.register(service)
        XCTAssertFalse(service.isActive, "a module registered while off must not start")

        switchboard.setEnabled(.nowPlaying, true)
        XCTAssertTrue(service.isActive)

        switchboard.setEnabled(.nowPlaying, false)
        XCTAssertFalse(service.isActive)
    }
}
