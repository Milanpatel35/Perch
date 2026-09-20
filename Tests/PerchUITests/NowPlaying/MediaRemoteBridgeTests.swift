import PerchCore
import XCTest

@testable import PerchUI

/// The bridge's one hard promise: it always answers.
///
/// Both reads are bridged to `async` with a checked continuation, and a
/// continuation that never resumes is not a tolerable outcome — the awaiting
/// task stays suspended forever holding everything it captured, and Swift
/// traps on the leak. MediaRemote makes no callback guarantee of its own, so
/// these are the tests that the guarantee is made on our side.
@MainActor
final class MediaRemoteBridgeTests: XCTestCase {

    /// Generous, because it is measuring "did this come back at all", not
    /// "how fast". A failure here is a hang, and a hang in CI is a twenty
    /// minute wait for no information.
    private let timeout: TimeInterval = 8

    // MARK: - TC-MED-007

    func test_TC_MED_007_aBridgeThatWasNeverOpenedStillAnswers() async {
        let bridge = MediaRemoteBridge()
        XCTAssertFalse(bridge.isAvailable)

        let snapshot = await withCheckedContinuation { continuation in
            bridge.readNowPlaying(sourceBundleID: nil) {
                continuation.resume(returning: $0)
            }
        }
        XCTAssertNil(snapshot)
    }

    func test_TC_MED_007_aBridgeThatWasNeverOpenedStillAnswersForTheOwner() async {
        let bridge = MediaRemoteBridge()

        let bundleID = await withCheckedContinuation { continuation in
            bridge.readOwningBundleID { continuation.resume(returning: $0) }
        }
        XCTAssertNil(bundleID)
    }

    func test_TC_MED_007_aClosedBridgeAnswersRatherThanHanging() async {
        let bridge = MediaRemoteBridge()
        bridge.open()
        bridge.close()

        XCTAssertFalse(bridge.isAvailable)

        // The interesting case: opened, so the framework is resident, then
        // closed. A read must still come back — the module withdraws its
        // activity on the strength of the answer.
        let snapshot = await withCheckedContinuation { continuation in
            bridge.readNowPlaying(sourceBundleID: nil) {
                continuation.resume(returning: $0)
            }
        }
        XCTAssertNil(snapshot)
    }

    func test_TC_MED_007_anOpenBridgeAnswersWithinTheTimeout() async throws {
        let bridge = MediaRemoteBridge()
        bridge.open()
        defer { bridge.close() }

        // On a machine with a media session this returns a snapshot; on a
        // headless runner with none, MediaRemote may never call back at all
        // and the watchdog answers instead. Either is a pass. Never
        // answering is not.
        let answered = expectation(description: "the bridge answered")
        bridge.readNowPlaying(sourceBundleID: nil) { _ in answered.fulfill() }

        await fulfillment(of: [answered], timeout: timeout)
    }

    func test_TC_MED_007_readingRepeatedlyAcrossOpenAndCloseNeverWedges() async {
        let bridge = MediaRemoteBridge()

        for _ in 0..<3 {
            bridge.open()
            let answered = expectation(description: "answered")
            bridge.readOwningBundleID { _ in answered.fulfill() }
            await fulfillment(of: [answered], timeout: timeout)
            bridge.close()
        }
    }
}
