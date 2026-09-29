import XCTest

@testable import PerchCore

/// Covers TC-MED-010: reading what Music and Spotify announce. The payloads
/// are shaped like the real ones — each app's own undocumented keys — so a
/// change in either app shows up here as a fixture to update.
final class PlayerNotificationTests: XCTestCase {

    private let now = Date(timeIntervalSinceReferenceDate: 1_000)

    private let musicPlaying: [AnyHashable: Any] = [
        "Name": "So What",
        "Artist": "Miles Davis",
        "Album": "Kind of Blue",
        "Player State": "Playing",
        "Total Time": NSNumber(value: 545_000),
        "PersistentID": NSNumber(value: 12_345)
    ]

    private let spotifyPaused: [AnyHashable: Any] = [
        "Name": "Blue in Green",
        "Artist": "Miles Davis",
        "Album": "Kind of Blue",
        "Player State": "Paused",
        "Duration": NSNumber(value: 337_000),
        "Playback Position": NSNumber(value: 61.5),
        "Track ID": "spotify:track:0aWMVrwxPNYkKmFthzmpRi"
    ]

    func test_TC_MED_010_aMusicNotificationIsRead() throws {
        let note = try XCTUnwrap(PlayerNotification.parse(player: .music, userInfo: musicPlaying))

        XCTAssertEqual(note.state, .playing)
        XCTAssertEqual(note.title, "So What")
        XCTAssertEqual(note.artist, "Miles Davis")
        XCTAssertEqual(note.album, "Kind of Blue")
        XCTAssertEqual(note.duration, .milliseconds(545_000))
        XCTAssertNil(note.position, "Music does not say where it is")
    }

    func test_TC_MED_010_aSpotifyNotificationIsReadWithItsPosition() throws {
        let note = try XCTUnwrap(
            PlayerNotification.parse(player: .spotify, userInfo: spotifyPaused))

        XCTAssertEqual(note.state, .paused)
        XCTAssertEqual(note.duration, .milliseconds(337_000))
        XCTAssertEqual(note.position, .seconds(61.5))
    }

    func test_TC_MED_010_stoppingMeansNothingIsPlaying() {
        var stopped = musicPlaying
        stopped["Player State"] = "Stopped"
        XCTAssertNil(PlayerNotification.parse(player: .music, userInfo: stopped))

        XCTAssertNil(
            PlayerNotification.parse(player: .music, userInfo: ["Player State": "Stopped"]))
    }

    func test_TC_MED_010_noTitleMeansNothingToShow() {
        var untitled = musicPlaying
        untitled["Name"] = "   "
        XCTAssertNil(PlayerNotification.parse(player: .music, userInfo: untitled))
    }

    func test_TC_MED_010_missingOptionalFieldsAreEmptyNotFatal() throws {
        let note = try XCTUnwrap(
            PlayerNotification.parse(
                player: .music, userInfo: ["Name": "Radio", "Player State": "Playing"])
        )
        XCTAssertEqual(note.artist, "")
        XCTAssertNil(note.duration)
    }

    func test_TC_MED_010_aSnapshotAdvancesOnlyWhilePlaying() throws {
        let playing = try XCTUnwrap(
            PlayerNotification.parse(player: .music, userInfo: musicPlaying))
        let paused = try XCTUnwrap(
            PlayerNotification.parse(player: .spotify, userInfo: spotifyPaused))

        let fromMusic = playing.snapshot(position: .seconds(10), at: now)
        XCTAssertTrue(fromMusic.isPlaying)
        XCTAssertEqual(fromMusic.sourceBundleID, "com.apple.Music")
        XCTAssertEqual(fromMusic.progress.elapsed, .seconds(10))

        let fromSpotify = paused.snapshot(position: nil, at: now)
        XCTAssertFalse(fromSpotify.isPlaying)
        XCTAssertEqual(
            fromSpotify.progress.elapsed, .seconds(61.5), "falls back to the notification's own")
    }

    func test_TC_MED_010_theNotificationNameIdentifiesThePlayer() {
        XCTAssertEqual(MusicPlayer(notificationName: "com.apple.Music.playerInfo"), .music)
        XCTAssertEqual(
            MusicPlayer(notificationName: "com.spotify.client.PlaybackStateChanged"), .spotify)
        XCTAssertNil(MusicPlayer(notificationName: "com.apple.iTunes.playerInfo"))
    }
}
