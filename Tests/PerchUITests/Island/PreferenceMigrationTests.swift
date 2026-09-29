import Defaults
import XCTest

@testable import PerchUI

/// Covers TC-SET-002: settings saved by 0.8.0 and earlier under dotted names
/// survive the rename, and nothing that is not Perch's is touched.
final class PreferenceMigrationTests: XCTestCase {

    private let suiteName = "app.perch.tests.migration"
    // A suite of its own, so the test never touches the app's real settings.
    // `UserDefaults(suiteName:)` only fails for the app's own identifier.
    private lazy var defaults = UserDefaults(suiteName: suiteName) ?? .standard

    override func setUp() {
        super.setUp()
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func test_TC_SET_002_oldDottedKeysMoveToTheirNewNames() {
        defaults.set(["shelf", "battery"], forKey: "modules.enabled")
        defaults.set(false, forKey: "gesture.hoverToExpand")
        defaults.set("active", forKey: "island.screenPolicy")

        let moved = PreferenceMigration.migrateDottedKeys(in: defaults, domain: suiteName)

        XCTAssertEqual(moved, ["gesture.hoverToExpand", "island.screenPolicy", "modules.enabled"])
        XCTAssertEqual(defaults.stringArray(forKey: "modules_enabled"), ["shelf", "battery"])
        XCTAssertEqual(defaults.object(forKey: "gesture_hoverToExpand") as? Bool, false)
        XCTAssertEqual(defaults.string(forKey: "island_screenPolicy"), "active")
        XCTAssertNil(defaults.object(forKey: "modules.enabled"))
    }

    func test_TC_SET_002_aValueAlreadyUnderTheNewNameWins() {
        defaults.set(["shelf"], forKey: "modules.enabled")
        defaults.set(["battery"], forKey: "modules_enabled")

        PreferenceMigration.migrateDottedKeys(in: defaults, domain: suiteName)

        XCTAssertEqual(defaults.stringArray(forKey: "modules_enabled"), ["battery"])
        XCTAssertNil(defaults.object(forKey: "modules.enabled"))
    }

    func test_TC_SET_002_runningTwiceChangesNothing() {
        defaults.set(true, forKey: "shelf.clearOnQuit")
        PreferenceMigration.migrateDottedKeys(in: defaults, domain: suiteName)

        XCTAssertEqual(PreferenceMigration.migrateDottedKeys(in: defaults, domain: suiteName), [])
        XCTAssertEqual(defaults.object(forKey: "shelf_clearOnQuit") as? Bool, true)
    }

    func test_TC_SET_002_keysThatAreNotPerchsAreLeftAlone() {
        defaults.set("x", forKey: "NSWindow Frame PerchSettings")
        defaults.set("y", forKey: "com.example.other")

        PreferenceMigration.migrateDottedKeys(in: defaults, domain: suiteName)

        XCTAssertEqual(defaults.string(forKey: "NSWindow Frame PerchSettings"), "x")
        XCTAssertEqual(defaults.string(forKey: "com.example.other"), "y")
    }

    /// The reason for the rename. The library rejects a dotted name when it
    /// is asked to observe it; every key it is given must pass its own check.
    func test_TC_SET_002_noPerchKeyHasADotInItsName() {
        let names = [
            Defaults.Keys.enabledModules.name, Defaults.Keys.islandScreenPolicy.name,
            Defaults.Keys.hoverToExpand.name, Defaults.Keys.clickToPin.name,
            Defaults.Keys.dragToOpenShelf.name, Defaults.Keys.swipeToSkip.name
        ]
        for name in names {
            XCTAssertFalse(name.contains("."), name)
        }
    }

    /// Every key in every module, read from the source, so the next module
    /// cannot bring a dotted name back without this failing.
    func test_TC_SET_002_noKeyAnywhereInTheSourceHasADot() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../../../Sources")
            .standardizedFileURL
        let pattern = try NSRegularExpression(pattern: #"Key<[^>]+>\(\s*"([^"]+)""#)

        let files = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)
        var checked = 0
        while let file = files?.nextObject() as? URL {
            guard file.pathExtension == "swift" else { continue }
            let text = try String(contentsOf: file, encoding: .utf8)
            let range = NSRange(text.startIndex..., in: text)
            for match in pattern.matches(in: text, range: range) {
                guard let nameRange = Range(match.range(at: 1), in: text) else { continue }
                let name = String(text[nameRange])
                XCTAssertFalse(name.contains("."), "\(file.lastPathComponent): \(name)")
                checked += 1
            }
        }
        XCTAssertGreaterThan(checked, 25, "the scan found the keys")
    }
}
