import XCTest

@testable import PerchCore

/// Covers `TEST-PLAN.md` TC-HOM-006 — one key per home-surface action.
final class HomeKeymapTests: XCTestCase {

    // MARK: - TC-HOM-006

    func test_TC_HOM_006_everyActionHasItsOwnKey() {
        let keys = HomeAction.allCases.map(HomeKeymap.key(for:))

        XCTAssertEqual(Set(keys).count, keys.count, "two actions share a key")
    }

    func test_TC_HOM_006_aKeyFindsItsActionInEitherCase() {
        for action in HomeAction.allCases {
            let key = String(HomeKeymap.key(for: action))
            XCTAssertEqual(HomeKeymap.action(for: key), action)
            XCTAssertEqual(HomeKeymap.action(for: key.lowercased()), action)
        }
    }

    func test_TC_HOM_006_aKeyOffTheMapDoesNothing() {
        XCTAssertNil(HomeKeymap.action(for: "Z"))
        XCTAssertNil(HomeKeymap.action(for: "1"))
        XCTAssertNil(HomeKeymap.action(for: ""))
        XCTAssertNil(HomeKeymap.action(for: "CA"))
    }
}
