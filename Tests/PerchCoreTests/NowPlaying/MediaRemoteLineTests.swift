import XCTest

@testable import PerchCore

/// Covers `TEST-PLAN.md` TC-MED-012 — reading the Now Playing helper's lines.
final class MediaRemoteLineTests: XCTestCase {

    private let received = Date(timeIntervalSince1970: 1_000)

    private func read(_ json: String) -> MediaRemoteLine? {
        MediaRemoteLine(Data(json.utf8), receivedAt: received)
    }

    private func playing(_ line: MediaRemoteLine?) throws -> NowPlayingSnapshot {
        guard case .playing(let snapshot) = try XCTUnwrap(line) else {
            throw XCTSkip("not a track")
        }
        return snapshot
    }

    // MARK: - TC-MED-012

    func test_TC_MED_012_aBrowserTabIsReadWithItsBrowserAsTheSource() throws {
        let snapshot = try playing(
            read(
                #"{"title":"Prime Video: Karuppu","artist":"","album":"","elapsed":2459.0,"#
                    + #""duration":9168,"rate":1,"playing":true,"timestamp":900,"#
                    + #""bundle":"com.google.Chrome"}"#
            ))
        XCTAssertEqual(snapshot.title, "Prime Video: Karuppu")
        XCTAssertEqual(snapshot.sourceBundleID, "com.google.Chrome")
        XCTAssertEqual(snapshot.progress.elapsed, .seconds(2459))
        XCTAssertEqual(snapshot.progress.duration, .seconds(9168))
        XCTAssertEqual(snapshot.progress.asOf, Date(timeIntervalSince1970: 900))
        XCTAssertTrue(snapshot.isPlaying)
    }

    func test_TC_MED_012_aPausedPlayerDoesNotAdvanceWhateverRateItClaims() throws {
        let line = read(#"{"title":"So What","elapsed":10,"rate":1,"playing":false}"#)

        let snapshot = try playing(line)
        XCTAssertFalse(snapshot.isPlaying)
        XCTAssertEqual(snapshot.progress.rate, 0)
    }

    func test_TC_MED_012_missingFieldsAreEmptyNotFatal() throws {
        let line = read(#"{"title":"Live stream","playing":true,"duration":null,"bundle":""}"#)

        let snapshot = try playing(line)
        XCTAssertNil(snapshot.progress.duration)
        XCTAssertNil(snapshot.sourceBundleID)
        XCTAssertEqual(snapshot.artist, "")
        XCTAssertEqual(snapshot.progress.asOf, received)
        XCTAssertNil(snapshot.artwork)
    }

    func test_TC_MED_012_artworkIsDecoded() throws {
        let bytes = Data([0x89, 0x50, 0x4E, 0x47])
        let artwork = bytes.base64EncodedString()
        let line = read(#"{"title":"T","playing":true,"artwork":"\#(artwork)"}"#)

        let snapshot = try playing(line)
        XCTAssertEqual(snapshot.artwork, bytes)
    }

    func test_TC_MED_012_nothingPlayingErrorsAndRubbish() {
        XCTAssertEqual(read(#"{"empty":true}"#), .nothing)
        XCTAssertEqual(read(#"{"title":""}"#), .nothing)
        XCTAssertEqual(
            read(#"{"error":"MediaRemote is not available"}"#),
            .failed("MediaRemote is not available"))
        XCTAssertNil(read("not json"))
        XCTAssertNil(read("[1,2]"))
    }
}
