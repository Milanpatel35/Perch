import XCTest

@testable import PerchCore

/// Covers the arithmetic the scrubber and the visualiser both hang off.
///
/// Worth testing hard, because the alternative implementation — a 30Hz timer
/// advancing a number — is the single easiest way to break `CLAUDE.md` §5.1,
/// and the reason it is easy is that it *works*. This one only works if the
/// maths is right.
final class PlaybackProgressTests: XCTestCase {

    private let epoch = Date(timeIntervalSinceReferenceDate: 1_000_000)

    // MARK: - TC-MED-002

    func test_TC_MED_002_pausedPlaybackIsNotAdvancing() {
        let paused = PlaybackProgress(
            elapsed: .seconds(30),
            rate: 0,
            asOf: epoch,
            duration: .seconds(200)
        )

        XCTAssertFalse(paused.isAdvancing)
    }

    func test_TC_MED_002_pausedPositionIsConstantHoweverLongYouWait() {
        let paused = PlaybackProgress(
            elapsed: .seconds(30),
            rate: 0,
            asOf: epoch,
            duration: .seconds(200)
        )

        // An hour later it is still at thirty seconds. Nothing had to tick to
        // keep it there, which is the point.
        XCTAssertEqual(paused.elapsed(at: epoch), .seconds(30))
        XCTAssertEqual(paused.elapsed(at: epoch.addingTimeInterval(3600)), .seconds(30))
    }

    func test_TC_MED_002_playingPositionAdvancesWithTheClock() {
        let playing = PlaybackProgress(
            elapsed: .seconds(30),
            rate: 1,
            asOf: epoch,
            duration: .seconds(200)
        )

        XCTAssertEqual(playing.elapsed(at: epoch.addingTimeInterval(10)), .seconds(40))
    }

    func test_playbackRateIsRespectedRatherThanAssumedToBeOne() {
        let doubleSpeed = PlaybackProgress(
            elapsed: .seconds(10),
            rate: 2,
            asOf: epoch,
            duration: .seconds(200)
        )

        XCTAssertEqual(doubleSpeed.elapsed(at: epoch.addingTimeInterval(10)), .seconds(30))
    }

    func test_positionNeverRunsPastTheEndOfTheTrack() {
        let nearlyOver = PlaybackProgress(
            elapsed: .seconds(195),
            rate: 1,
            asOf: epoch,
            duration: .seconds(200)
        )

        // The source stops telling us at some point; the scrubber must not
        // keep going and draw past the end of its own track.
        XCTAssertEqual(nearlyOver.elapsed(at: epoch.addingTimeInterval(60)), .seconds(200))
        XCTAssertEqual(nearlyOver.fraction(at: epoch.addingTimeInterval(60)), 1)
    }

    func test_positionNeverGoesNegativeWhenScrubbingBackwards() {
        let rewinding = PlaybackProgress(
            elapsed: .seconds(5),
            rate: -8,
            asOf: epoch,
            duration: .seconds(200)
        )

        XCTAssertEqual(rewinding.elapsed(at: epoch.addingTimeInterval(10)), .zero)
    }

    func test_aStreamWithNoLengthHasNoFractionRatherThanAFullBar() {
        let stream = PlaybackProgress(
            elapsed: .seconds(90),
            rate: 1,
            asOf: epoch,
            duration: nil
        )

        // A live radio stream reports no duration. Treating that as zero
        // gives a full bar, which says "this is about to end" — the opposite
        // of the truth.
        XCTAssertNil(stream.fraction(at: epoch))
        XCTAssertEqual(stream.elapsed(at: epoch.addingTimeInterval(30)), .seconds(120))
    }

    func test_aZeroLengthTrackHasNoFractionRatherThanDividingByZero() {
        let degenerate = PlaybackProgress(
            elapsed: .zero,
            rate: 1,
            asOf: epoch,
            duration: .zero
        )

        XCTAssertNil(degenerate.fraction(at: epoch))
    }
}
