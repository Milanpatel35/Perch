import XCTest

@testable import PerchCore

/// Covers `TEST-PLAN.md` § FOC for distraction blocking's rules: what a typed
/// site becomes, what it matches, which apps are hidden, when any of it runs,
/// and what the browser scripts are allowed to contain.
final class DistractionBlocklistTests: XCTestCase {

    // MARK: - TC-FOC-010

    func test_TC_FOC_010_aSiteTypedAnyWayIsTheSameHost() {
        let typed = [
            "reddit.com", "Reddit.com/", "  www.reddit.com  ", "https://www.reddit.com/r/all",
            "http://user@reddit.com:443/path?q=1#top", "reddit.com."
        ]
        for input in typed {
            XCTAssertEqual(BlockedSite(typed: input)?.host, "reddit.com", input)
        }
    }

    func test_TC_FOC_010_somethingThatIsNotAHostIsRefused() {
        for input in ["", "   ", "reddit", "red dit.com", "a..b", "https://", "<script>.com"] {
            XCTAssertNil(BlockedSite(typed: input), input)
        }
    }

    func test_TC_FOC_010_subdomainsOtherThanWwwAreKept() {
        XCTAssertEqual(BlockedSite(typed: "news.ycombinator.com")?.host, "news.ycombinator.com")
    }

    // MARK: - TC-FOC-011

    private let reddit = BlockedSite(host: "reddit.com")

    func test_TC_FOC_011_aSiteMatchesItselfAndItsSubdomains() {
        XCTAssertTrue(reddit.matches(host: "reddit.com"))
        XCTAssertTrue(reddit.matches(host: "old.reddit.com"))
        XCTAssertTrue(reddit.matches(host: "WWW.Reddit.COM"))
    }

    func test_TC_FOC_011_aSiteNeverMatchesALookalike() {
        XCTAssertFalse(reddit.matches(host: "notreddit.com"))
        XCTAssertFalse(reddit.matches(host: "reddit.com.example.org"))
        XCTAssertFalse(reddit.matches(host: "reddit.co"))
    }

    func test_TC_FOC_011_onlyWebPagesAreTakenAway() {
        let list = DistractionBlocklist(blocksSites: true, sites: [reddit])

        XCTAssertTrue(list.blocksPage("https://old.reddit.com/r/swift"))
        XCTAssertTrue(list.blocksPage("http://reddit.com"))
        XCTAssertFalse(list.blocksPage("file:///Users/someone/reddit.com.html"))
        XCTAssertFalse(list.blocksPage("about:blank"))
        XCTAssertFalse(list.blocksPage("https://example.com/?next=reddit.com"))
        XCTAssertFalse(list.blocksPage(""))
    }

    func test_TC_FOC_011_sitesSwitchedOffBlockNothing() {
        let list = DistractionBlocklist(blocksSites: false, sites: [reddit])
        XCTAssertFalse(list.blocksPage("https://reddit.com"))
    }

    // MARK: - TC-FOC-012

    private let own = "app.perch.Perch"

    func test_TC_FOC_012_aListedAppIsBlocked() {
        let list = DistractionBlocklist(blocksApps: true, apps: ["com.hnc.Discord"])

        XCTAssertTrue(list.blocksApp("com.hnc.Discord", ownBundleID: own))
        XCTAssertTrue(list.blocksApp("COM.HNC.DISCORD", ownBundleID: own))
        XCTAssertFalse(list.blocksApp("com.apple.Notes", ownBundleID: own))
    }

    func test_TC_FOC_012_aBrowserIsNeverHiddenEvenWhenListed() {
        let list = DistractionBlocklist(
            blocksApps: true,
            apps: ["com.apple.Safari", "org.mozilla.firefox", "com.google.Chrome"]
        )
        for browser in ["com.apple.Safari", "org.mozilla.firefox", "com.google.Chrome"] {
            XCTAssertFalse(list.blocksApp(browser, ownBundleID: own), browser)
        }
    }

    func test_TC_FOC_012_perchNeverHidesItself() {
        let list = DistractionBlocklist(blocksApps: true, apps: [own])
        XCTAssertFalse(list.blocksApp(own, ownBundleID: own))
    }

    func test_TC_FOC_012_appsSwitchedOffBlockNothing() {
        let list = DistractionBlocklist(blocksApps: false, apps: ["com.hnc.Discord"])
        XCTAssertFalse(list.blocksApp("com.hnc.Discord", ownBundleID: own))
    }

    // MARK: - TC-FOC-013

    private let listed = DistractionBlocklist(blocksApps: true, apps: ["com.hnc.Discord"])
    private let start = Date(timeIntervalSince1970: 1_000_000)

    func test_TC_FOC_013_onlyARunningWorkPhaseIsEnforced() {
        var timer = PomodoroTimer()
        XCTAssertFalse(listed.isEnforced(during: timer), "idle")

        timer.start(.work, now: start)
        XCTAssertTrue(listed.isEnforced(during: timer), "working")

        timer.pause(now: start.addingTimeInterval(60))
        XCTAssertFalse(listed.isEnforced(during: timer), "paused")

        timer.start(.shortBreak, now: start.addingTimeInterval(120))
        XCTAssertFalse(listed.isEnforced(during: timer), "on a break")

        timer.stop()
        XCTAssertFalse(listed.isEnforced(during: timer), "stopped")
    }

    func test_TC_FOC_013_nothingListedIsNeverEnforced() {
        var timer = PomodoroTimer()
        timer.start(.work, now: start)

        XCTAssertFalse(DistractionBlocklist().isEnforced(during: timer))
        XCTAssertFalse(
            DistractionBlocklist(blocksApps: true, blocksSites: true).isEnforced(during: timer),
            "switched on with nothing listed"
        )
        XCTAssertFalse(
            DistractionBlocklist(blocksApps: false, apps: ["com.hnc.Discord"])
                .isEnforced(during: timer),
            "listed but switched off"
        )
    }

    // MARK: - TC-FOC-017

    func test_TC_FOC_017_onlyKnownBrowsersAreScripted() {
        XCTAssertEqual(Browser.scriptable("com.apple.Safari"), .safari(name: "Safari"))
        XCTAssertEqual(Browser.scriptable("com.google.Chrome"), .chromium(name: "Google Chrome"))
        XCTAssertNil(Browser.scriptable("org.mozilla.firefox"), "no AppleScript tab access")
        XCTAssertNil(Browser.scriptable("com.example.evil\" & do shell script \"x"))
    }

    func test_TC_FOC_017_theScriptsHoldOnlyConstants() throws {
        let chrome = try XCTUnwrap(Browser.scriptable("com.google.Chrome"))

        XCTAssertTrue(chrome.readFrontTab.contains("tell application \"Google Chrome\""))
        XCTAssertTrue(chrome.readFrontTab.contains("URL of active tab of front window"))
        XCTAssertTrue(chrome.blankFrontTab.contains("to \"about:blank\""))
        XCTAssertFalse(chrome.blankFrontTab.contains("do shell script"))

        let safari = Browser.safari(name: "Safari")
        XCTAssertTrue(safari.blankFrontTab.contains("set URL of front document to \"about:blank\""))
    }
}
