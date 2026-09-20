import XCTest

@testable import PerchCore

/// Covers `TEST-PLAN.md` § MED at unit level — the rule that decides whether
/// a change in what is playing is worth interrupting someone for.
///
/// This is the whole difference between an island that tells you something
/// and an island that flashes at you every second (TC-MED-003).
final class NowPlayingTransitionTests: XCTestCase {

    private let epoch = Date(timeIntervalSinceReferenceDate: 1_000_000)

    private func snapshot(
        title: String = "Blue in Green",
        artist: String = "Miles Davis",
        album: String = "Kind of Blue",
        elapsed: Duration = .seconds(10),
        rate: Double = 1,
        artwork: Data? = nil,
        source: String? = "com.apple.Music"
    ) -> NowPlayingSnapshot {
        NowPlayingSnapshot(
            title: title,
            artist: artist,
            album: album,
            progress: PlaybackProgress(
                elapsed: elapsed,
                rate: rate,
                asOf: epoch,
                duration: .seconds(327)
            ),
            artwork: artwork,
            sourceBundleID: source
        )
    }

    // MARK: - TC-MED-001

    func test_TC_MED_001_playbackStartingPeeks() {
        XCTAssertEqual(NowPlayingTransition.between(nil, snapshot()), .peek)
    }

    func test_TC_MED_001_snapshotCarriesWhatTheIslandNeedsToDraw() {
        let artwork = Data([0xFF, 0xD8, 0xFF, 0xE0])
        let playing = snapshot(artwork: artwork)

        XCTAssertEqual(playing.title, "Blue in Green")
        XCTAssertEqual(playing.artist, "Miles Davis")
        XCTAssertEqual(playing.artwork, artwork)
        XCTAssertTrue(playing.isPlaying)
    }

    func test_TC_MED_001_somethingAlreadyPausedDoesNotAnnounceItself() {
        // Switching the module on, or launching Perch, while a paused track
        // sits in a background app. The user did not just do anything, so the
        // island must not act as though they had.
        XCTAssertEqual(
            NowPlayingTransition.between(nil, snapshot(rate: 0)),
            .updateInPlace
        )
    }

    // MARK: - TC-MED-003

    func test_TC_MED_003_aPositionUpdateDoesNotRePresent() {
        let before = snapshot(elapsed: .seconds(10))
        let after = snapshot(elapsed: .seconds(11))

        XCTAssertEqual(NowPlayingTransition.between(before, after), .updateInPlace)
    }

    func test_TC_MED_003_artworkArrivingLateDoesNotRePresent() {
        // Sources routinely report the title first and the artwork a moment
        // later. That second report must not read as a new track.
        let withoutArt = snapshot()
        let withArt = snapshot(artwork: Data([0x01, 0x02]))

        XCTAssertEqual(NowPlayingTransition.between(withoutArt, withArt), .updateInPlace)
    }

    func test_TC_MED_003_aGenuineTrackChangePeeks() {
        let before = snapshot(title: "Blue in Green")
        let after = snapshot(title: "So What")

        XCTAssertEqual(NowPlayingTransition.between(before, after), .peek)
    }

    func test_TC_MED_003_anIdenticalReportIsNotAChangeAtAll() {
        let same = snapshot()
        XCTAssertEqual(NowPlayingTransition.between(same, same), .unchanged)
    }

    func test_TC_MED_003_pausingIsShownButIsNotWorthAPeek() {
        // The user pressed the key. They know.
        let playing = snapshot(rate: 1)
        let paused = snapshot(rate: 0)

        XCTAssertEqual(NowPlayingTransition.between(playing, paused), .updateInPlace)
    }

    func test_TC_MED_003_switchingToAnotherAppsTrackPeeks() {
        let music = snapshot(source: "com.apple.Music")
        let browser = snapshot(source: "com.google.Chrome")

        XCTAssertEqual(NowPlayingTransition.between(music, browser), .peek)
    }

    // MARK: - TC-MED-004

    func test_TC_MED_004_aSourceWithNoArtworkIsStillAValidSnapshot() {
        let noArt = snapshot(artwork: nil)

        XCTAssertNil(noArt.artwork)
        XCTAssertEqual(noArt.artworkFingerprint, 0)
        XCTAssertEqual(NowPlayingTransition.between(nil, noArt), .peek)
    }

    func test_TC_MED_004_artworkIsComparedByFingerprintNotByteByByte() {
        let small = snapshot(artwork: Data([0x01]))
        let large = snapshot(artwork: Data(repeating: 0x7F, count: 2_000_000))

        XCTAssertNotEqual(small, large)
        XCTAssertNotEqual(small.artworkFingerprint, large.artworkFingerprint)
        // Same track, different artwork: content update, not a peek.
        XCTAssertEqual(NowPlayingTransition.between(small, large), .updateInPlace)
    }

    // MARK: - Stopping

    func test_playbackStoppingTakesTheIslandBack() {
        XCTAssertEqual(NowPlayingTransition.between(snapshot(), nil), .withdraw)
    }

    func test_stoppingWhenNothingWasPlayingIsStillAWithdrawal() {
        // Idempotent on purpose: the module may be told twice, and withdrawing
        // an activity that is not there is free.
        XCTAssertEqual(NowPlayingTransition.between(nil, nil), .withdraw)
    }
}
