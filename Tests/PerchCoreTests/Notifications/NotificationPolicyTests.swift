import XCTest

@testable import PerchCore

/// Covers `TEST-PLAN.md` § NTF for everything that is a rule rather than a
/// banner — which is all of it except the Accessibility plumbing.
///
/// `NotificationPolicy` has no clock and no AX, so a burst of nine messages
/// and an hour-long focus session both run in microseconds.
final class NotificationPolicyTests: XCTestCase {

    private let noon = Date(timeIntervalSinceReferenceDate: 12 * 3_600)

    private func notification(
        _ body: String,
        app: String = "Messages",
        bundle: String? = "com.apple.MobileSMS",
        title: String = "Priya",
        at offset: Double = 0
    ) -> MirroredNotification {
        MirroredNotification(
            id: UUID().uuidString,
            appName: app,
            bundleID: bundle,
            title: title,
            body: body,
            receivedAt: noon.addingTimeInterval(offset)
        )
    }

    // MARK: - TC-NTF-001

    func test_TC_NTF_001_anAppOnTheDenyListNeverReachesTheIsland() {
        var configuration = NotificationPolicy.Configuration()
        configuration.apps = ["com.apple.MobileSMS"]

        var policy = NotificationPolicy(configuration: configuration)

        XCTAssertEqual(policy.receive(notification("hello")), .drop)
        XCTAssertNil(policy.current)
    }

    func test_TC_NTF_001_everythingElseStillMirrorsInDenyMode() {
        var configuration = NotificationPolicy.Configuration()
        configuration.apps = ["com.apple.MobileSMS"]

        var policy = NotificationPolicy(configuration: configuration)
        let outcome = policy.receive(notification("build finished", bundle: "com.apple.dt.Xcode"))

        guard case .present(let burst) = outcome else { return XCTFail("expected a burst") }
        XCTAssertEqual(burst.count, 1)
    }

    // MARK: - TC-NTF-002

    func test_TC_NTF_002_allowModeMirrorsOnlyWhatIsListed() {
        var configuration = NotificationPolicy.Configuration()
        configuration.mode = .allowListedOnly
        configuration.apps = ["com.apple.MobileSMS"]

        var policy = NotificationPolicy(configuration: configuration)

        guard case .present = policy.receive(notification("hello")) else {
            return XCTFail("the listed app must mirror")
        }
        XCTAssertEqual(
            policy.receive(notification("build finished", bundle: "com.apple.dt.Xcode")),
            .drop
        )
    }

    /// A banner that names no app cannot be on a list. Deny mode shows it;
    /// allow mode must not, or "only these apps" is not true.
    func test_TC_NTF_002_anUnattributedNotificationFollowsTheModesPromise() {
        var policy = NotificationPolicy()
        guard case .present = policy.receive(notification("disk almost full", bundle: nil)) else {
            return XCTFail("deny mode shows what it cannot filter")
        }

        var configuration = NotificationPolicy.Configuration()
        configuration.mode = .allowListedOnly
        configuration.apps = ["com.apple.MobileSMS"]

        var strict = NotificationPolicy(configuration: configuration)
        XCTAssertEqual(strict.receive(notification("disk almost full", bundle: nil)), .drop)
    }

    // MARK: - TC-NTF-003

    /// macOS redraws a banner when it slides, when another arrives behind
    /// it, and when it is re-posted after a Focus ends. All three are the
    /// same message and must reach the island once.
    func test_TC_NTF_003_theSameNotificationTwiceIsShownOnce() {
        var policy = NotificationPolicy()

        guard case .present = policy.receive(notification("on my way")) else {
            return XCTFail("first one shows")
        }
        XCTAssertEqual(policy.receive(notification("on my way")), .drop)
        XCTAssertEqual(policy.current?.count, 1)
    }

    func test_TC_NTF_003_theSeenListIsBounded() {
        var policy = NotificationPolicy()

        for index in 0..<200 {
            _ = policy.receive(notification("message \(index)", at: Double(index) * 60))
        }

        // The oldest is forgotten, so it mirrors again rather than being
        // suppressed for ever by a list that only grows.
        guard case .present = policy.receive(notification("message 0", at: 20_000)) else {
            return XCTFail("a long-forgotten notification is new again")
        }
    }

    // MARK: - TC-NTF-004

    func test_TC_NTF_004_aBurstFromOneAppIsOneActivityWithACount() {
        var policy = NotificationPolicy()

        for index in 0..<9 {
            _ = policy.receive(notification("message \(index)", at: Double(index)))
        }

        XCTAssertEqual(policy.current?.count, 9)
        XCTAssertEqual(policy.current?.latest.body, "message 8")
        XCTAssertEqual(policy.current?.firstAt, noon)
    }

    func test_TC_NTF_004_aReplyAfterTheWindowIsItsOwnArrival() {
        var policy = NotificationPolicy()

        _ = policy.receive(notification("first", at: 0))
        _ = policy.receive(notification("much later", at: 60))

        XCTAssertEqual(policy.current?.count, 1)
        XCTAssertEqual(policy.current?.latest.body, "much later")
    }

    func test_TC_NTF_004_adifferentAppStartsItsOwnBurst() {
        var policy = NotificationPolicy()

        _ = policy.receive(notification("hello", at: 0))
        _ = policy.receive(notification("build finished", bundle: "com.apple.dt.Xcode", at: 1))

        XCTAssertEqual(policy.current?.count, 1)
        XCTAssertEqual(policy.current?.appName, "Messages")
    }

    func test_TC_NTF_004_clearingTheIslandStartsTheNextCountFromOne() {
        var policy = NotificationPolicy()

        _ = policy.receive(notification("one", at: 0))
        policy.clearCurrent()
        _ = policy.receive(notification("two", at: 1))

        XCTAssertEqual(policy.current?.count, 1)
    }

    // MARK: - TC-NTF-005 and TC-NTF-006

    func test_TC_NTF_005_aFocusSessionHoldsRatherThanDrops() {
        var policy = NotificationPolicy()

        XCTAssertEqual(
            policy.receive(notification("hello"), isFocusSessionRunning: true),
            .hold
        )
        XCTAssertNil(policy.current)
        XCTAssertEqual(policy.held.count, 1)
    }

    func test_TC_NTF_005_silentDuringFocusOffMirrorsAnyway() {
        var configuration = NotificationPolicy.Configuration()
        configuration.silentDuringFocus = false

        var policy = NotificationPolicy(configuration: configuration)

        guard case .present = policy.receive(notification("hello"), isFocusSessionRunning: true)
        else { return XCTFail("the switch is off, so nothing is held") }
        XCTAssertTrue(policy.held.isEmpty)
    }

    func test_TC_NTF_006_heldNotificationsAreReleasedCoalescedPerApp() {
        var policy = NotificationPolicy()

        for index in 0..<4 {
            _ = policy.receive(
                notification("message \(index)", at: Double(index) * 120),
                isFocusSessionRunning: true
            )
        }
        _ = policy.receive(
            notification("build finished", bundle: "com.apple.dt.Xcode", at: 30),
            isFocusSessionRunning: true
        )

        let released = policy.releaseHeld()

        XCTAssertEqual(released.count, 2, "one burst per app, not one per notification")
        XCTAssertEqual(released.first?.count, 4)
        XCTAssertEqual(released.first?.appName, "Messages")
        XCTAssertEqual(released.last?.count, 1)
        XCTAssertTrue(policy.held.isEmpty)
    }

    func test_TC_NTF_006_releasingNothingReturnsNothing() {
        var policy = NotificationPolicy()
        XCTAssertTrue(policy.releaseHeld().isEmpty)
    }

    // MARK: - TC-NTF-007

    func test_TC_NTF_007_doNotDisturbWins() {
        var policy = NotificationPolicy()

        XCTAssertEqual(policy.receive(notification("hello"), isDoNotDisturbOn: true), .drop)
        XCTAssertNil(policy.current)
        XCTAssertTrue(policy.held.isEmpty, "dropped, not held — the system already decided")
    }

    // MARK: - TC-NTF-012

    func test_TC_NTF_012_perchDoesNotMirrorPerch() {
        var policy = NotificationPolicy()

        XCTAssertEqual(
            policy.receive(notification("shelf full", app: "Perch", bundle: "app.perch.Perch")),
            .drop
        )
    }

    // MARK: - Identity

    func test_theFingerprintIsTheContentNotTheWindow() {
        let first = notification("on my way")
        let second = notification("on my way")

        XCTAssertNotEqual(first.id, second.id, "two banners, two window ids")
        XCTAssertEqual(first.fingerprint, second.fingerprint)
    }

    func test_resetClearsEverything() {
        var policy = NotificationPolicy()
        _ = policy.receive(notification("hello"), isFocusSessionRunning: true)
        _ = policy.receive(notification("hello again", at: 1))

        policy.reset()

        XCTAssertNil(policy.current)
        XCTAssertTrue(policy.held.isEmpty)
    }
}
