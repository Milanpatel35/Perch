import XCTest

@testable import PerchCore

/// Covers `TEST-PLAN.md` § HUD at unit level.
///
/// Every rule about what reaches the island lives in `HUDPolicy` precisely so
/// it can be tested here — without a volume key, a display, a Bluetooth radio
/// or a Focus mode, none of which a CI runner has.
final class HUDPolicyTests: XCTestCase {

    private func volume(_ level: Double, muted: Bool = false) -> HUDReading {
        HUDReading(kind: .volume, level: level, isMuted: muted, title: "Volume")
    }

    private func brightness(_ level: Double) -> HUDReading {
        HUDReading(kind: .brightness, level: level, title: "Brightness")
    }

    // MARK: - TC-HUD-002

    /// Holding the brightness key sends one notification per step. Each step
    /// is a new value and each one should update the HUD.
    func test_TC_HUD_002_everyStepOfAHeldKeyIsAnUpdate() {
        var policy = HUDPolicy()

        for step in stride(from: 0.1, through: 0.9, by: 0.1) {
            XCTAssertTrue(policy.admit(brightness(step)), "step \(step) was dropped")
        }
    }

    /// At the top of the range the key keeps sending and the value stops
    /// moving. Re-admitting would restart the island's time to live and leave
    /// the HUD hanging on screen after the finger came off.
    func test_TC_HUD_002_aRepeatedValueIsDroppedSoTheHUDDoesNotHang() {
        var policy = HUDPolicy()

        XCTAssertTrue(policy.admit(brightness(1.0)))
        XCTAssertFalse(policy.admit(brightness(1.0)))
        XCTAssertFalse(policy.admit(brightness(1.0)))

        // Coming back down is a change again.
        XCTAssertTrue(policy.admit(brightness(0.9)))
    }

    /// Muted at 40% is not the same as 0%: the Mac goes back to 40%. Two
    /// readings that differ only by the mute flag are two different states.
    func test_muteIsAChangeEvenWhenTheLevelDoesNot() {
        var policy = HUDPolicy()

        XCTAssertTrue(policy.admit(volume(0.4)))
        XCTAssertTrue(policy.admit(volume(0.4, muted: true)))
        XCTAssertFalse(policy.admit(volume(0.4, muted: true)))
        XCTAssertTrue(policy.admit(volume(0.4)))
    }

    // MARK: - TC-HUD-007

    /// Perch turning a Focus on must not then be told by macOS that a Focus
    /// turned on, and announce it back.
    func test_TC_HUD_007_aChangePerchMadeItselfIsNotAnnounced() {
        var policy = HUDPolicy()
        let focus = HUDReading(kind: .focus, title: "Do Not Disturb")

        policy.suppressNext(.focus)
        XCTAssertFalse(policy.admit(focus))
    }

    /// It swallows one reading, not a window of time — and the swallowed one
    /// is still recorded, or the next genuine change would compare against a
    /// stale value.
    func test_TC_HUD_007_suppressionAppliesToExactlyOneReading() {
        var policy = HUDPolicy()

        policy.suppressNext(.focus)
        XCTAssertFalse(policy.admit(HUDReading(kind: .focus, title: "Do Not Disturb")))

        // Somebody else's change, straight after. Not ours, so it shows.
        XCTAssertTrue(policy.admit(HUDReading(kind: .focus, title: "Work")))
    }

    /// The swallowed reading is still the current state. If it were
    /// forgotten, macOS re-reporting it would look like news.
    func test_TC_HUD_007_aSwallowedReadingIsStillRecorded() {
        var policy = HUDPolicy()
        let focus = HUDReading(kind: .focus, title: "Do Not Disturb")

        policy.suppressNext(.focus)
        XCTAssertFalse(policy.admit(focus))
        XCTAssertEqual(policy.current(.focus), focus)
        XCTAssertFalse(policy.admit(focus))
    }

    func test_TC_HUD_007_suppressingOneKindDoesNotAffectAnother() {
        var policy = HUDPolicy()

        policy.suppressNext(.focus)

        XCTAssertTrue(policy.admit(volume(0.5)))
        XCTAssertFalse(policy.admit(HUDReading(kind: .focus, title: "Work")))
    }

    // MARK: - TC-HUD-008

    func test_TC_HUD_008_oneHUDOffLeavesTheOthersAlone() {
        var policy = HUDPolicy()
        policy.setEnabled(.volume, false)

        XCTAssertFalse(policy.admit(volume(0.5)))
        XCTAssertTrue(policy.admit(brightness(0.5)))
        XCTAssertTrue(policy.admit(HUDReading(kind: .focus, title: "Work")))
    }

    func test_TC_HUD_008_everyHUDCanBeSwitchedOffIndividually() {
        for kind in HUDKind.allCases {
            var policy = HUDPolicy()
            policy.setEnabled(kind, false)

            XCTAssertFalse(policy.isEnabled(kind))
            XCTAssertEqual(policy.enabled.count, HUDKind.allCases.count - 1)
        }
    }

    /// Switching a HUD off drops what was known about it, so switching it
    /// back on does not compare the next reading against a value from before.
    func test_TC_HUD_008_switchingAHUDBackOnStartsFresh() {
        var policy = HUDPolicy()

        XCTAssertTrue(policy.admit(volume(0.5)))
        policy.setEnabled(.volume, false)
        policy.setEnabled(.volume, true)

        XCTAssertNil(policy.current(.volume))
        XCTAssertTrue(policy.admit(volume(0.5)))
    }

    /// Suppression asked for on a HUD that is off must not lie in wait and
    /// swallow the first reading after it is switched back on.
    func test_TC_HUD_008_suppressingADisabledHUDDoesNothing() {
        var policy = HUDPolicy()
        policy.setEnabled(.focus, false)

        policy.suppressNext(.focus)
        policy.setEnabled(.focus, true)

        XCTAssertTrue(policy.admit(HUDReading(kind: .focus, title: "Work")))
    }

    // MARK: - Lifecycle

    func test_resetForgetsEverything() {
        var policy = HUDPolicy()

        XCTAssertTrue(policy.admit(volume(0.5)))
        policy.suppressNext(.focus)
        policy.reset()

        XCTAssertNil(policy.current(.volume))
        XCTAssertTrue(policy.admit(volume(0.5)))
        XCTAssertTrue(policy.admit(HUDReading(kind: .focus, title: "Work")))
    }

    // MARK: - Readings

    func test_levelsAreClampedRatherThanTrusted() {
        XCTAssertEqual(HUDReading(kind: .volume, level: 1.4, title: "Volume").level, 1)
        XCTAssertEqual(HUDReading(kind: .volume, level: -0.2, title: "Volume").level, 0)
        XCTAssertNil(HUDReading(kind: .focus, title: "Work").level)
    }

    func test_thePercentageIsRoundedForTheLabelAndForVoiceOver() {
        XCTAssertEqual(volume(0.436).percentage, 44)
        XCTAssertEqual(volume(0).percentage, 0)
        XCTAssertNil(HUDReading(kind: .focus, title: "Work").percentage)
    }

    /// Only the two HUDs with a level draw a bar. A bar stuck at 100% next to
    /// "AirPods connected" is furniture.
    func test_onlyVolumeAndBrightnessDrawALevelBar() {
        XCTAssertEqual(
            Set(HUDKind.allCases.filter(\.showsLevel)),
            [.volume, .brightness]
        )
    }
}
