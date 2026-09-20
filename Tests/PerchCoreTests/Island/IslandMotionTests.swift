import XCTest

@testable import PerchCore

/// Covers the Reduce Motion path — `TEST-PLAN.md` TC-ISL-012 and TC-A11Y-004.
///
/// `CLAUDE.md` §5.5 makes Reduce Motion a hard requirement. Making it a real
/// path rather than a disabled one is the difference between "no animation"
/// and "the app feels broken for people who need this on".
final class IslandMotionTests: XCTestCase {

    // MARK: - TC-ISL-012 / TC-A11Y-004

    func test_TC_ISL_012_reduceMotionUsesCrossFadeNotSpring() {
        for token in IslandMotion.Token.allCases {
            let resolved = IslandMotion.resolve(token, reduceMotion: true)

            guard case .fade = resolved else {
                return XCTFail("\(token) sprang with Reduce Motion on")
            }
        }
    }

    func test_TC_A11Y_004_noSpringAnimationAnywhereWithReduceMotionOn() {
        let sprang = IslandMotion.Token.allCases.contains { token in
            if case .spring = IslandMotion.resolve(token, reduceMotion: true) {
                return true
            }
            return false
        }

        XCTAssertFalse(sprang, "Reduce Motion must leave no spring anywhere")
    }

    func test_TC_ISL_012_springTokensAreUsedWhenMotionIsAllowed() {
        for token in IslandMotion.Token.allCases {
            let resolved = IslandMotion.resolve(token, reduceMotion: false)

            guard case .spring = resolved else {
                return XCTFail("\(token) faded with Reduce Motion off")
            }
        }
    }

    // MARK: - Token selection

    func test_transitionFromIdlePeeks() {
        XCTAssertEqual(
            IslandMotion.token(from: .idle, to: .peek("a")),
            .peek
        )
    }

    func test_transitionToIdleCollapses() {
        XCTAssertEqual(
            IslandMotion.token(from: .expanded("a"), to: .idle),
            .collapse
        )
    }

    func test_peekToExpandedUsesTheExpandToken() {
        XCTAssertEqual(
            IslandMotion.token(from: .peek("a"), to: .expanded("a")),
            .expand
        )
    }

    func test_sameShapeDifferentContentUsesTheContentToken() {
        XCTAssertEqual(
            IslandMotion.token(from: .peek("a"), to: .peek("b")),
            .content
        )
    }

    // MARK: - Consistency

    func test_everyFadeIsShorterThanTheSpringItReplaces() {
        // A fade that lasts as long as the spring reads as lag rather than as
        // motion the user asked to remove.
        for token in IslandMotion.Token.allCases {
            let fade = IslandMotion.fade(for: token)
            let spring = IslandMotion.spring(for: token)

            let fadeSeconds =
                Double(fade.duration.components.seconds)
                + Double(fade.duration.components.attoseconds) / 1e18

            XCTAssertLessThan(
                fadeSeconds, spring.response,
                "\(token): fade should be shorter than the spring's response"
            )
        }
    }

    func test_allSpringsAreCriticallyDampedOrBetter() {
        // Under ~0.7 the island visibly overshoots, which on a shape hanging
        // off the top edge of the screen looks like a bug rather than polish.
        for token in IslandMotion.Token.allCases {
            XCTAssertGreaterThanOrEqual(
                IslandMotion.spring(for: token).dampingFraction, 0.7,
                "\(token) would overshoot"
            )
        }
    }
}
