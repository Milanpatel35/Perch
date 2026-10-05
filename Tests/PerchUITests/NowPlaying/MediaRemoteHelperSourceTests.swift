import Foundation
import PerchCore
import XCTest

@testable import PerchUI

/// Covers `TEST-PLAN.md` TC-MED-013 … 015 — running the Now Playing helper,
/// and falling back to Music and Spotify when it fails.
///
/// The helper here is a stand-in perl script, so nothing depends on what
/// this Mac happens to be playing — or on MediaRemote at all. The real
/// helper is TC-MED-011, by hand.
@MainActor
final class MediaRemoteHelperSourceTests: XCTestCase {

    nonisolated(unsafe) private var directory = URL(fileURLWithPath: NSTemporaryDirectory())

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("perch-helper-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        try super.tearDownWithError()
    }

    /// A helper that prints `lines`, then waits for stdin to close — or, if
    /// `exits`, quits straight away as a broken helper would.
    private typealias Helper = MediaRemoteHelperSource.Helper

    private func helper(printing lines: [String], exits: Bool = false) throws -> Helper {
        let script = directory.appendingPathComponent("helper.pl")
        let printed = lines.map { "print q(\($0)), \"\\n\";" }.joined(separator: "\n")
        let wait = exits ? "exit 1;" : "while (<STDIN>) {}"
        try "$| = 1;\n\(printed)\n\(wait)\n".write(to: script, atomically: true, encoding: .utf8)
        return .init(
            perl: URL(fileURLWithPath: "/usr/bin/perl"),
            script: script,
            library: directory.appendingPathComponent("unused.dylib")
        )
    }

    /// For the async tests: sleeping yields the main actor, so the
    /// helper's lines — delivered on it — can land. A run loop spun inside
    /// an async test holds the actor and they never do.
    private func settle(_ condition: () -> Bool, _ message: String) async {
        let deadline = Date().addingTimeInterval(5)
        while !condition(), Date() < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(condition(), message)
    }

    private func waitUntil(_ condition: @autoclosure () -> Bool, _ message: String) {
        let deadline = Date().addingTimeInterval(5)
        while !condition(), Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        XCTAssertTrue(condition(), message)
    }

    // MARK: - TC-MED-013

    func test_TC_MED_013_aLineFromTheHelperBecomesTheTrack() async throws {
        let source = MediaRemoteHelperSource(
            helper: try helper(printing: [
                #"{"title":"Prime Video: Karuppu","playing":true,"bundle":"com.google.Chrome"}"#
            ]))
        var changes = 0
        source.start { changes += 1 }
        defer { source.stop() }

        await settle({ changes > 0 }, "the helper's line never arrived")
        let snapshot = await source.readSnapshot()
        XCTAssertEqual(snapshot?.title, "Prime Video: Karuppu")
        XCTAssertEqual(snapshot?.sourceBundleID, "com.google.Chrome")
        XCTAssertFalse(source.hasFailed)
    }

    func test_TC_MED_013_nothingPlayingClearsTheTrack() async throws {
        let source = MediaRemoteHelperSource(
            helper: try helper(printing: [
                #"{"title":"So What","playing":true}"#,
                #"{"empty":true}"#
            ]))
        var changes = 0
        source.start { changes += 1 }
        defer { source.stop() }

        await settle({ changes >= 2 }, "both lines never arrived")
        let snapshot = await source.readSnapshot()
        XCTAssertNil(snapshot)
    }

    // MARK: - TC-MED-014

    func test_TC_MED_014_stoppingEndsTheHelper() throws {
        let source = MediaRemoteHelperSource(helper: try helper(printing: []))
        source.start {}
        source.stop()

        // Stopping is not failing: the owner must not fall back.
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        XCTAssertFalse(source.hasFailed)
    }

    // MARK: - TC-MED-015

    func test_TC_MED_015_aHelperThatDiesHandsOverToMusicAndSpotify() throws {
        let fallback = FakeNowPlayingSource()
        let source = AnyAppNowPlayingSource(
            helper: MediaRemoteHelperSource(helper: try helper(printing: [], exits: true)),
            fallback: fallback,
            usesHelper: { true }
        )
        source.start {}
        defer { source.stop() }

        waitUntil(fallback.isRunning, "the fallback never started")
        XCTAssertFalse(source.isUsingHelper)
    }

    func test_TC_MED_015_aRefusalFromMediaRemoteHandsOverToo() throws {
        let fallback = FakeNowPlayingSource()
        let source = AnyAppNowPlayingSource(
            helper: MediaRemoteHelperSource(
                helper: try helper(printing: [#"{"error":"MediaRemote is not available"}"#])),
            fallback: fallback,
            usesHelper: { true }
        )
        source.start {}
        defer { source.stop() }

        waitUntil(fallback.isRunning, "the fallback never started")
    }

    func test_TC_MED_015_noHelperOrSettingOffMeansMusicAndSpotify() throws {
        let missing = FakeNowPlayingSource()
        let withoutHelper = AnyAppNowPlayingSource(
            helper: MediaRemoteHelperSource(helper: nil), fallback: missing, usesHelper: { true })
        withoutHelper.start {}
        XCTAssertTrue(missing.isRunning)
        withoutHelper.stop()
        XCTAssertFalse(missing.isRunning)

        let off = FakeNowPlayingSource()
        let switchedOff = AnyAppNowPlayingSource(
            helper: MediaRemoteHelperSource(helper: try helper(printing: [])),
            fallback: off,
            usesHelper: { false }
        )
        switchedOff.start {}
        XCTAssertTrue(off.isRunning)
        XCTAssertFalse(switchedOff.isUsingHelper)
        switchedOff.stop()
    }
}
