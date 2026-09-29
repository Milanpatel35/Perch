import XCTest

@testable import PerchCore

/// Covers `TEST-PLAN.md` § CAL for link detection — TC-CAL-004 and
/// TC-CAL-005, the two that decide whether the join button is trustworthy.
///
/// The invitation bodies below are shortened, but every one of them is the
/// shape the service's own calendar plug-in writes.
final class MeetingLinkTests: XCTestCase {

    // MARK: - TC-CAL-004

    func test_TC_CAL_004_detectsGoogleMeet() {
        let link = MeetingLink.detect(in: "Join: https://meet.google.com/abc-defg-hij")

        XCTAssertEqual(link?.service, .meet)
        XCTAssertEqual(link?.url.absoluteString, "https://meet.google.com/abc-defg-hij")
        XCTAssertNil(link?.appURL, "Meet has no native client to hand off to")
    }

    func test_TC_CAL_004_detectsZoomAndPrefersTheNativeClient() {
        let link = MeetingLink.detect(in: "https://us02web.zoom.us/j/89123456789?pwd=Zm9vYmFy")

        XCTAssertEqual(link?.service, .zoom)
        XCTAssertEqual(
            link?.launchURL.absoluteString,
            "zoommtg://zoom.us/join?confno=89123456789&pwd=Zm9vYmFy"
        )
    }

    func test_TC_CAL_004_detectsZoomGovernmentAndWebClientForms() {
        XCTAssertEqual(MeetingLink.detect(in: "https://zoomgov.com/j/1612345678")?.service, .zoom)
        XCTAssertEqual(
            MeetingLink.detect(in: "https://zoom.us/wc/join/1612345678")?.service,
            .zoom
        )
    }

    func test_TC_CAL_004_detectsTeams() {
        let invitation = """
            ________________________________________
            Microsoft Teams meeting
            Join on your computer, mobile app or room device
            Click here to join the meeting <https://teams.microsoft.com/l/meetup-join/19%3ameeting_ZmFrZQ%40thread.v2/0>
            """

        XCTAssertEqual(MeetingLink.detect(in: invitation)?.service, .teams)
    }

    func test_TC_CAL_004_detectsWebexInBothItsForms() {
        XCTAssertEqual(
            MeetingLink.detect(in: "https://acme.webex.com/meet/priya")?.service,
            .webex
        )
        XCTAssertEqual(
            MeetingLink.detect(in: "https://acme.webex.com/acme/j.php?MTID=m123abc")?.service,
            .webex
        )
    }

    func test_TC_CAL_004_detectsAroundAndWhereby() {
        XCTAssertEqual(MeetingLink.detect(in: "https://meet.around.co/r/standup")?.service, .around)
        XCTAssertEqual(MeetingLink.detect(in: "https://whereby.com/perch")?.service, .whereby)
        XCTAssertEqual(
            MeetingLink.detect(in: "https://acme.whereby.com/design")?.service,
            .whereby
        )
    }

    /// The `url` field wins over `notes`, because that is the field the
    /// calendar plug-ins fill with the real link — `notes` usually holds the
    /// boilerplate, and the boilerplate links to a help page.
    func test_TC_CAL_004_prefersTheEventURLOverTheNotes() {
        let link = MeetingLink.detect(
            location: nil,
            notes: "Recording from last week: https://us02web.zoom.us/j/99999999999",
            url: URL(string: "https://meet.google.com/xyz-abcd-efg")
        )

        XCTAssertEqual(link?.service, .meet)
    }

    /// Outlook puts the join link in the location field, so it has to beat
    /// the notes as well.
    func test_TC_CAL_004_findsALinkInTheLocationField() {
        let link = MeetingLink.detect(
            location: "Microsoft Teams Meeting https://teams.microsoft.com/l/meetup-join/19%3afake",
            notes: "Bring the roadmap.",
            url: nil
        )

        XCTAssertEqual(link?.service, .teams)
    }

    /// A URL detector that stops at the wrong character produces a link that
    /// 404s, which is worse than no link. Trailing punctuation is the case
    /// that bites.
    func test_TC_CAL_004_stopsTheURLAtTheEndOfTheSentence() {
        let link = MeetingLink.detect(in: "We are on https://meet.google.com/abc-defg-hij.")

        XCTAssertEqual(link?.url.absoluteString, "https://meet.google.com/abc-defg-hij")
    }

    // MARK: - TC-CAL-005

    func test_TC_CAL_005_anEventWithNoLinkHasNoJoinButton() {
        XCTAssertNil(
            MeetingLink.detect(
                location: "Room 4, second floor",
                notes: "Quarterly planning. Bring the roadmap.",
                url: nil
            )
        )
    }

    func test_TC_CAL_005_anEmptyEventHasNoLink() {
        XCTAssertNil(MeetingLink.detect(location: nil, notes: nil, url: nil))
    }

    /// Matching on the host alone put a dead join button on every invitation
    /// that linked to a vendor's home page. Host *and* path have to agree.
    func test_TC_CAL_005_refusesAVendorLinkThatIsNotAMeeting() {
        let notMeetings = [
            "https://zoom.us/download",
            "https://zoom.us/signin",
            "https://teams.microsoft.com/",
            "https://www.webex.com/pricing",
            "https://meet.google.com/",
            "https://whereby.com/"
        ]

        for candidate in notMeetings {
            XCTAssertNil(
                MeetingLink.detect(in: candidate),
                "\(candidate) is not a meeting and must not produce a join button"
            )
        }
    }

    func test_TC_CAL_005_refusesAnUnrelatedLink() {
        XCTAssertNil(MeetingLink.detect(in: "Agenda: https://example.com/docs/roadmap"))
    }

    /// Two unrelated links and one meeting: the meeting is found wherever it
    /// sits in the text, not only when it comes first.
    func test_TC_CAL_004_findsTheMeetingAmongOtherLinks() {
        let notes = """
            Agenda: https://example.com/docs/roadmap
            Dial in: https://example.com/phone
            Video: https://meet.google.com/abc-defg-hij
            """

        XCTAssertEqual(MeetingLink.detect(in: notes)?.service, .meet)
    }
}
