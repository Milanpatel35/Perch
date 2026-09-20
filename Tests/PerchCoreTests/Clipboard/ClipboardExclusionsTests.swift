import XCTest

@testable import PerchCore

/// TC-CLP-006 and TC-CLP-007 — what the clipboard refuses to remember.
///
/// These two are the module's licence to exist. A clipboard manager that
/// records your password manager is not a feature with a bug in it; it is a
/// liability, and nobody finds out until it matters.
final class ClipboardExclusionsTests: XCTestCase {

    // MARK: - TC-CLP-007

    func test_TC_CLP_007_aConcealedTypeIsNeverCaptured() {
        let exclusions = ClipboardExclusions()

        XCTAssertFalse(
            exclusions.allowsCapture(from: "com.apple.Safari", isConcealed: true)
        )
    }

    func test_TC_CLP_007_concealedBeatsEverythingIncludingAnEmptyExclusionList() {
        // Unconditional: there is no setting for this, and an empty list is
        // not permission to record something an app asked us not to.
        let exclusions = ClipboardExclusions(bundleIDs: [])

        XCTAssertFalse(exclusions.allowsCapture(from: nil, isConcealed: true))
        XCTAssertFalse(
            exclusions.allowsCapture(from: "com.example.anything", isConcealed: true)
        )
    }

    // MARK: - TC-CLP-006

    func test_TC_CLP_006_passwordManagersAreExcludedOutOfTheBox() {
        let exclusions = ClipboardExclusions()

        for bundleID in [
            "com.1password.1password",
            "com.bitwarden.desktop",
            "com.apple.keychainaccess",
            "org.keepassxc.keepassxc"
        ] {
            XCTAssertFalse(
                exclusions.allowsCapture(from: bundleID, isConcealed: false),
                "\(bundleID) should be excluded by default"
            )
            XCTAssertTrue(exclusions.isDefault(bundleID))
        }
    }

    func test_TC_CLP_006_anOrdinaryAppIsCaptured() {
        let exclusions = ClipboardExclusions()

        XCTAssertTrue(
            exclusions.allowsCapture(from: "com.apple.Safari", isConcealed: false)
        )
        XCTAssertTrue(exclusions.allowsCapture(from: "com.microsoft.VSCode", isConcealed: false))
    }

    func test_TC_CLP_006_anUnknownSourceIsNotByItselfAReasonToRefuse() {
        // Plenty of ordinary copies come from a process Perch cannot name.
        // Refusing all of them would quietly break the module.
        XCTAssertTrue(ClipboardExclusions().allowsCapture(from: nil, isConcealed: false))
    }

    func test_TC_CLP_006_anAppCanBeExcludedAndIncludedAgain() {
        var exclusions = ClipboardExclusions()
        let bundleID = "com.example.banking"

        XCTAssertTrue(exclusions.allowsCapture(from: bundleID, isConcealed: false))

        exclusions.exclude(bundleID)
        XCTAssertFalse(exclusions.allowsCapture(from: bundleID, isConcealed: false))
        XCTAssertFalse(exclusions.isDefault(bundleID))

        exclusions.include(bundleID)
        XCTAssertTrue(exclusions.allowsCapture(from: bundleID, isConcealed: false))
    }

    func test_TC_CLP_006_exclusionsAreIdentifiersNotNames() {
        // A renamed or localised app must stay excluded, and an app merely
        // *called* "1Password" must not be included by accident.
        let exclusions = ClipboardExclusions()

        XCTAssertTrue(
            exclusions.allowsCapture(from: "com.evil.1Password", isConcealed: false)
        )
        XCTAssertFalse(
            exclusions.allowsCapture(from: "com.1password.1password", isConcealed: false)
        )
    }

    func test_TC_CLP_006_theDefaultListSurvivesBeingEncodedAndRead() throws {
        let original = ClipboardExclusions()
        let data = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(ClipboardExclusions.self, from: data)

        XCTAssertEqual(restored, original)
        XCTAssertFalse(
            restored.allowsCapture(from: "com.1password.1password", isConcealed: false)
        )
    }
}
