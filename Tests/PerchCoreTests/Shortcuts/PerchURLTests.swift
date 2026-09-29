import XCTest

@testable import PerchCore

/// Covers `TEST-PLAN.md` § SHC for the parts that are input handling — the
/// `perch://` scheme above all, because any web page can open one.
final class PerchURLTests: XCTestCase {

    private func parse(_ string: String) -> Result<PerchCommand, PerchURL.Rejection> {
        guard let url = URL(string: string) else {
            XCTFail("not a URL: \(string)")
            return .failure(.notPerch)
        }
        return PerchURL.parse(url)
    }

    // MARK: - TC-SHC-002

    func test_TC_SHC_002_aMessageParsesWithTitleBodyAndUrgency() {
        XCTAssertEqual(
            parse("perch://notify?title=Build%20ok&body=12s&urgency=high"),
            .success(.notify(.init(title: "Build ok", body: "12s", urgency: .high)))
        )
    }

    func test_TC_SHC_002_aMessageWithNoUrgencyIsNormal() {
        XCTAssertEqual(
            parse("perch://notify?title=hello"),
            .success(.notify(.init(title: "hello")))
        )
    }

    /// The rule the test case is named for. A script can beat the music; it
    /// can never pose as a system alert or a timer finishing.
    func test_TC_SHC_002_noUrgencyReachesTheTopTwoPriorities() {
        for urgency in PerchCommand.Urgency.allCases {
            XCTAssertLessThan(urgency.priority, .timerFinishing, "\(urgency)")
        }
        XCTAssertGreaterThan(PerchCommand.Urgency.normal.priority, .nowPlaying)
        XCTAssertEqual(PerchCommand.Urgency.low.priority, .ambient)
    }

    func test_TC_SHC_002_everyCommandRoundTripsThroughItsURL() {
        let commands: [PerchCommand] = [
            .notify(.init(title: "Tests: 480 passed", body: "a & b = c?", urgency: .low)),
            .notify(.init(title: "ünïcødé ✓ 🚀")),
            .addToShelf(URL(fileURLWithPath: "/Users/me/My Files/report #2.pdf")),
            .startFocus
        ]

        for command in commands {
            XCTAssertEqual(PerchURL.parse(PerchURL.url(for: command)), .success(command))
        }
    }

    // MARK: - TC-SHC-003

    func test_TC_SHC_003_anotherSchemeIsRejected() {
        XCTAssertEqual(parse("https://notify?title=x"), .failure(.notPerch))
        XCTAssertEqual(parse("file:///notify?title=x"), .failure(.notPerch))
    }

    /// There is no "run a Shortcut" action, because any web page can open a
    /// `perch://` link. Every spelling of one is simply unknown.
    func test_TC_SHC_003_thereIsNoWayToRunAShortcutByURL() {
        for action in ["run", "shortcut", "runShortcut", "exec", "open", "shell"] {
            XCTAssertEqual(
                parse("perch://\(action)?name=Delete%20Everything"),
                .failure(.unknownAction(action.lowercased()))
            )
        }
    }

    func test_TC_SHC_003_aMessageWithoutATitleIsRejected() {
        XCTAssertEqual(parse("perch://notify"), .failure(.missingTitle))
        XCTAssertEqual(parse("perch://notify?title="), .failure(.missingTitle))
        XCTAssertEqual(parse("perch://notify?title=%20%20%0A"), .failure(.missingTitle))
    }

    func test_TC_SHC_003_overlongTextIsRejectedRatherThanTruncated() {
        let long = String(repeating: "a", count: PerchURL.maximumTextLength + 1)
        XCTAssertEqual(parse("perch://notify?title=\(long)"), .failure(.textTooLong))
        XCTAssertEqual(parse("perch://notify?title=x&body=\(long)"), .failure(.textTooLong))
    }

    func test_TC_SHC_003_anUnknownUrgencyIsRejected() {
        XCTAssertEqual(
            parse("perch://notify?title=x&urgency=systemAlert"),
            .failure(.badUrgency("systemAlert"))
        )
    }

    func test_TC_SHC_003_controlCharactersCannotBreakTheLine() {
        XCTAssertEqual(
            parse("perch://notify?title=one%0Atwo%09three"),
            .success(.notify(.init(title: "one two three")))
        )
    }

    func test_TC_SHC_003_theShelfTakesOnlyAnAbsolutePath() {
        XCTAssertEqual(parse("perch://shelf"), .failure(.missingPath))
        XCTAssertEqual(parse("perch://shelf?path=Desktop/x.pdf"), .failure(.notAnAbsoluteFilePath))
        XCTAssertEqual(
            parse("perch://shelf?path=https://example.com/x"),
            .failure(.notAnAbsoluteFilePath)
        )
        XCTAssertEqual(
            parse("perch://shelf?path=/tmp/../tmp/x.pdf"),
            .success(.addToShelf(URL(fileURLWithPath: "/tmp/x.pdf")))
        )
    }

    func test_TC_SHC_003_theFirstOfARepeatedParameterWins() {
        XCTAssertEqual(
            parse("perch://notify?title=first&title=second"),
            .success(.notify(.init(title: "first")))
        )
    }

    func test_bothSpellingsOfTheActionAreRead() {
        XCTAssertEqual(parse("perch://focus"), .success(.startFocus))
        XCTAssertEqual(parse("perch:focus"), .success(.startFocus))
        XCTAssertEqual(parse("PERCH://FOCUS"), .success(.startFocus))
    }
}
