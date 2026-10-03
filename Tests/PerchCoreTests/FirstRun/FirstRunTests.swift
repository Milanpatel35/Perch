import XCTest

@testable import PerchCore

/// Covers `TEST-PLAN.md` § ONB.
final class FirstRunTests: XCTestCase {

    private let built: Set<ModuleID> = [
        .nowPlaying, .shelf, .clipboard, .focus, .calendar, .hud, .battery,
        .notifications, .camera, .systemStats, .shortcuts, .hideNotch
    ]

    // MARK: - TC-ONB-001

    func test_TC_ONB_001_noPresetNamesAModuleThatIsNotBuilt() {
        for preset in ModulePreset.allCases {
            XCTAssertTrue(
                preset.modules(built: built).isSubset(of: built),
                "\(preset) switches on something this build does not have"
            )
            XCTAssertFalse(preset.modules(built: built).isEmpty, "\(preset) switches on nothing")
        }
        XCTAssertFalse(ModulePreset.everything.modules(built: built).contains(.weather))
    }

    // MARK: - TC-ONB-002

    func test_TC_ONB_002_onlyJustHideTheNotchHidesTheNotch() {
        XCTAssertEqual(ModulePreset.justHideTheNotch.modules(built: built), [.hideNotch])
        for preset in ModulePreset.allCases where preset != .justHideTheNotch {
            XCTAssertFalse(preset.modules(built: built).contains(.hideNotch), "\(preset)")
        }
    }

    // MARK: - TC-ONB-003

    func test_TC_ONB_003_eachPresetSaysWhatItMayAskFor() {
        XCTAssertEqual(ModulePreset.music.permissions(built: built), [])
        XCTAssertEqual(ModulePreset.justHideTheNotch.permissions(built: built), [])
        XCTAssertEqual(
            ModulePreset.work.permissions(built: built),
            [.calendar, .accessibility]
        )
        XCTAssertEqual(
            ModulePreset.everything.permissions(built: built),
            [.calendar, .accessibility, .camera]
        )
    }

    func test_TC_ONB_003_theDefaultModulesAskForNothing() {
        let defaults: [ModuleID] = [.nowPlaying, .shelf, .clipboard, .focus, .hud, .battery]
        XCTAssertTrue(defaults.allSatisfy(\.permissions.isEmpty), "TC-PRV-002")
    }

    // MARK: - TC-ONB-004

    func test_TC_ONB_004_aCopyRunFromDownloadsCannotOpenAtLogin() {
        let translocated = InstallLocation(
            bundlePath: "/private/var/folders/j6/T/AppTranslocation/2D59/d/Perch.app"
        )
        XCTAssertEqual(translocated, .translocated)
        XCTAssertFalse(translocated.supportsLaunchAtLogin)
    }

    func test_TC_ONB_004_applicationsFoldersAreRecognised() {
        XCTAssertEqual(InstallLocation(bundlePath: "/Applications/Perch.app"), .applications)
        let userApplications = InstallLocation(
            bundlePath: "/Users/a/Applications/Perch.app",
            homeDirectory: "/Users/a"
        )
        XCTAssertEqual(userApplications, .applications)
        let built = InstallLocation(bundlePath: "/Users/a/Library/Developer/Debug/Perch.app")
        XCTAssertEqual(built, .elsewhere)
        XCTAssertTrue(built.supportsLaunchAtLogin)
    }
}
