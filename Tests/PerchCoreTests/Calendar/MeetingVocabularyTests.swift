import XCTest

@testable import PerchCore

/// Covers the readable half of `TEST-PLAN.md` § CAL's control block —
/// TC-CAL-008, TC-CAL-009 and TC-CAL-011.
///
/// The cases themselves are end-to-end and need a real call, which no CI
/// machine has. What *is* testable is the part that decides what a menu
/// title means, and that is where the bugs live: a title that resolves to
/// the wrong action mutes when you asked it to leave.
final class MeetingVocabularyTests: XCTestCase {

    // MARK: - TC-CAL-008

    func test_TC_CAL_008_zoomTitlesResolveToTheirActions() {
        let zoom = MeetingVocabulary.zoom

        XCTAssertEqual(zoom.action(for: "Mute Audio"), .mute)
        XCTAssertEqual(zoom.action(for: "Unmute Audio"), .unmute)
        XCTAssertEqual(zoom.action(for: "Start Video"), .startVideo)
        XCTAssertEqual(zoom.action(for: "Stop Video"), .stopVideo)
        XCTAssertEqual(zoom.action(for: "End Meeting"), .leave)
    }

    /// Vendors decorate menu titles with an ellipsis or a shortcut hint and
    /// change their minds between releases. Matching has to survive both.
    func test_TC_CAL_008_decorationOnATitleDoesNotBreakTheMatch() {
        let zoom = MeetingVocabulary.zoom

        XCTAssertEqual(zoom.action(for: "Mute Audio (⇧⌘A)"), .mute)
        XCTAssertEqual(zoom.action(for: "End Meeting…"), .leave)
        XCTAssertEqual(zoom.action(for: "  unmute audio  "), .unmute)
    }

    /// Longest match wins. "Stop Video" and "Stop Video Preview" must not
    /// resolve to each other.
    func test_TC_CAL_008_theMoreSpecificTitleWins() {
        let vocabulary = MeetingVocabulary(
            callMenuTitles: ["Meeting"],
            items: ["Mute": .mute, "Mute Everyone Else": .leave]
        )

        XCTAssertEqual(vocabulary.action(for: "Mute Everyone Else"), .leave)
        XCTAssertEqual(vocabulary.action(for: "Mute"), .mute)
    }

    // MARK: - TC-CAL-009

    /// The whole reason the island and the app never disagree: the state is
    /// read out of which titles the client is offering, every time, and is
    /// never remembered.
    func test_TC_CAL_009_theOfferedTitleIsTheState() {
        XCTAssertEqual(MeetingVocabulary.isMuted(given: [.unmute, .stopVideo]), true)
        XCTAssertEqual(MeetingVocabulary.isMuted(given: [.mute, .stopVideo]), false)

        XCTAssertEqual(MeetingVocabulary.isCameraOn(given: [.mute, .stopVideo]), true)
        XCTAssertEqual(MeetingVocabulary.isCameraOn(given: [.mute, .startVideo]), false)
    }

    /// Unknown is not "not muted". Drawing an unmuted microphone for a call
    /// Perch cannot read is exactly the disagreement TC-CAL-009 forbids.
    func test_TC_CAL_009_anUnreadableMenuIsUnknownRatherThanUnmuted() {
        XCTAssertNil(MeetingVocabulary.isMuted(given: [.leave]))
        XCTAssertNil(MeetingVocabulary.isCameraOn(given: [.leave]))
        XCTAssertNil(MeetingVocabulary.isMuted(given: []))
    }

    // MARK: - TC-CAL-011

    func test_TC_CAL_011_anUnknownTitleResolvesToNothing() {
        let zoom = MeetingVocabulary.zoom

        XCTAssertNil(zoom.action(for: "Invite…"))
        XCTAssertNil(zoom.action(for: "Record to this Computer"))
        XCTAssertNil(zoom.action(for: ""))
    }

    func test_TC_CAL_011_onlyTheInCallMenuIsRecognised() {
        let zoom = MeetingVocabulary.zoom

        XCTAssertTrue(zoom.isCallMenu("Meeting"))
        XCTAssertTrue(zoom.isCallMenu("meeting"))
        XCTAssertFalse(zoom.isCallMenu("Window"))
        XCTAssertFalse(zoom.isCallMenu("Edit"))
    }

    /// Browser meetings have no menu bar of their own, so there is nothing
    /// to drive and Perch says so rather than offering a dead button.
    func test_TC_CAL_011_browserServicesHaveNoVocabulary() {
        XCTAssertNil(MeetingVocabulary.vocabulary(for: .meet))
        XCTAssertNil(MeetingVocabulary.vocabulary(for: .around))
        XCTAssertNil(MeetingVocabulary.vocabulary(for: .whereby))

        XCTAssertNotNil(MeetingVocabulary.vocabulary(for: .zoom))
        XCTAssertNotNil(MeetingVocabulary.vocabulary(for: .teams))
        XCTAssertNotNil(MeetingVocabulary.vocabulary(for: .webex))
    }

    /// Every client Perch claims to drive must offer both halves of each
    /// pair. One without the other means the state can be read but never
    /// changed back.
    func test_everyDrivableClientOffersBothHalvesOfEachToggle() {
        for service in MeetingLink.Service.allCases {
            guard let vocabulary = MeetingVocabulary.vocabulary(for: service) else { continue }
            let actions = Set(vocabulary.items.values)

            XCTAssertTrue(
                actions.isSuperset(of: [.mute, .unmute, .startVideo, .stopVideo, .leave]),
                "\(service) is missing one of the five actions"
            )
        }
    }
}
