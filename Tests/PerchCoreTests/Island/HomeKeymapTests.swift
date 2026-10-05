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

/// Covers `TEST-PLAN.md` TC-HOM-011 — the tabs and their number keys.
final class HomeTabTests: XCTestCase {

    func test_TC_HOM_011_homeIsFirstAndEveryTabHasItsOwnNumber() {
        XCTAssertEqual(HomeTab.allCases.first, .home)
        let keys = HomeTab.allCases.map(\.key)
        XCTAssertEqual(Set(keys).count, keys.count)
        for tab in HomeTab.allCases {
            XCTAssertEqual(HomeTab.tab(for: String(tab.key)), tab)
            XCTAssertNil(HomeKeymap.action(for: String(tab.key)), "a tab key is also an action")
        }
        XCTAssertNil(HomeTab.tab(for: "9"))
    }
}
