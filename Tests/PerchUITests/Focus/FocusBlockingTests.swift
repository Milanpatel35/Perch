import Defaults
import PerchCore
import XCTest

@testable import PerchUI

/// Covers `TEST-PLAN.md` § FOC for distraction blocking inside the real
/// module: when it runs, what it hides, which tabs it reads, and that it
/// leaves nothing behind.
///
/// Nothing here hides a real app or scripts a real browser. The workspace
/// is a fake that can put any app in front, and the browser is a fake that
/// answers with whatever address the test gives it — which is also how the
/// tests prove what was *not* hidden or read.
@MainActor
final class FocusBlockingTests: XCTestCase {

    @MainActor
    private final class FakeWorkspace {
        var front: FocusBlocker.FrontApp?
        var handler: (@MainActor (FocusBlocker.FrontApp) -> Void)?
        private(set) var observers = 0
        private(set) var hidden: [String] = []

        /// What the browser's front tab shows. `nil` means Automation was
        /// refused.
        var address: String? = "https://example.com"
        private(set) var reads = 0
        private(set) var blanks = 0

        func bringToFront(_ app: FocusBlocker.FrontApp) {
            front = app
            handler?(app)
        }

        func system() -> FocusBlocker.System {
            FocusBlocker.System(
                observeActivations: { [unowned self] handler in
                    observers += 1
                    self.handler = handler
                    return { [unowned self] in
                        observers -= 1
                        self.handler = nil
                    }
                },
                frontmost: { [unowned self] in front },
                hide: { [unowned self] app in
                    // As in macOS: a hidden app is no longer in front.
                    hidden.append(app.bundleID)
                    if front == app { front = nil }
                    return true
                },
                run: { [unowned self] script in await answer(script) },
                sleep: { _ in await Task.yield() },
                ownBundleID: "app.perch.Perch"
            )
        }

        private func answer(_ script: String) -> FocusBlocker.ScriptOutcome {
            if script.contains("about:blank") {
                blanks += 1
                address = "about:blank"
                return .value("")
            }
            reads += 1
            guard let address else { return .notPermitted }
            return .value(address)
        }
    }

    private let discord = FocusBlocker.FrontApp(
        bundleID: "com.hnc.Discord", name: "Discord", processID: 1)
    private let notes = FocusBlocker.FrontApp(
        bundleID: "com.apple.Notes", name: "Notes", processID: 2)
    private let safari = FocusBlocker.FrontApp(
        bundleID: "com.apple.Safari", name: "Safari", processID: 3)
    private let firefox = FocusBlocker.FrontApp(
        bundleID: "org.mozilla.firefox", name: "Firefox", processID: 4)

    private let everything = DistractionBlocklist(
        blocksApps: true,
        blocksSites: true,
        apps: ["com.hnc.Discord"],
        sites: [BlockedSite(host: "reddit.com")]
    )

    nonisolated(unsafe) private var directory = URL(fileURLWithPath: NSTemporaryDirectory())
    private var saved = DistractionBlocklist()

    override func setUp() async throws {
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("perch-focus-block-\(UUID().uuidString)")
        saved = Defaults[.distractionBlocklist]
        Defaults[.distractionBlocklist] = DistractionBlocklist()
    }

    override func tearDown() async throws {
        Defaults[.distractionBlocklist] = saved
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeService(_ workspace: FakeWorkspace) -> (FocusService, IslandController) {
        let island = IslandController(sleep: { _ in try await Task.sleep(for: .seconds(86_400)) })
        let focus = FocusService(island: island, directory: directory, blocking: workspace.system())
        return (focus, island)
    }

    /// Lets the tab check's task take a few turns.
    private func settle() async {
        for _ in 0..<20 {
            await Task.yield()
        }
    }

    // MARK: - TC-FOC-014

    func test_TC_FOC_014_aFullBlocklistCostsNothingUntilASessionStarts() async {
        let workspace = FakeWorkspace()
        workspace.front = safari
        workspace.address = "https://reddit.com"
        let (focus, _) = makeService(workspace)

        focus.activate()
        focus.setBlocklist(everything)
        await settle()

        XCTAssertEqual(workspace.observers, 0, "no observer before a session")
        XCTAssertEqual(workspace.reads, 0, "no tab read — so no Automation prompt either")
        XCTAssertTrue(workspace.hidden.isEmpty)
        focus.deactivate()
    }

    // MARK: - TC-FOC-013

    func test_TC_FOC_013_blockingFollowsTheWorkPhaseAndNothingElse() {
        let workspace = FakeWorkspace()
        let (focus, _) = makeService(workspace)
        focus.activate()
        focus.setBlocklist(everything)

        focus.start()
        XCTAssertEqual(workspace.observers, 1, "working")

        focus.toggle()
        XCTAssertEqual(workspace.observers, 0, "paused")

        focus.toggle()
        XCTAssertEqual(workspace.observers, 1, "resumed")

        focus.start(.shortBreak)
        XCTAssertEqual(workspace.observers, 0, "on a break")

        focus.start(.work)
        focus.stop()
        XCTAssertEqual(workspace.observers, 0, "stopped")
        focus.deactivate()
    }

    func test_TC_FOC_013_switchingTheModuleOffStopsBlockingMidSession() {
        let workspace = FakeWorkspace()
        let (focus, _) = makeService(workspace)
        focus.activate()
        focus.setBlocklist(everything)
        focus.start()

        focus.deactivate()

        XCTAssertEqual(workspace.observers, 0)
        XCTAssertFalse(focus.blocker.isRunning)
    }

    func test_TC_FOC_013_emptyingTheListMidSessionStopsIt() {
        let workspace = FakeWorkspace()
        let (focus, _) = makeService(workspace)
        focus.activate()
        focus.setBlocklist(everything)
        focus.start()

        focus.setBlocklist(DistractionBlocklist())

        XCTAssertEqual(workspace.observers, 0)
        focus.deactivate()
    }

    // MARK: - TC-FOC-015

    func test_TC_FOC_015_aListedAppIsHiddenCountedAndNamed() {
        let workspace = FakeWorkspace()
        let (focus, island) = makeService(workspace)
        focus.activate()
        focus.setBlocklist(everything)
        focus.start()

        workspace.bringToFront(notes)
        workspace.bringToFront(discord)

        XCTAssertEqual(workspace.hidden, ["com.hnc.Discord"])
        XCTAssertEqual(focus.blockedThisSession, 1)
        let note = island.presented?.base as? FocusBlockedActivity
        XCTAssertEqual(note?.name, "Discord")
        focus.deactivate()
    }

    func test_TC_FOC_015_anAppAlreadyInFrontWhenTheSessionStartsIsHidden() {
        let workspace = FakeWorkspace()
        workspace.front = discord
        let (focus, _) = makeService(workspace)
        focus.activate()
        focus.setBlocklist(everything)

        focus.start()

        XCTAssertEqual(workspace.hidden, ["com.hnc.Discord"])
        focus.deactivate()
    }

    func test_TC_FOC_015_aNewSessionStartsTheCountAgain() {
        let workspace = FakeWorkspace()
        let (focus, _) = makeService(workspace)
        focus.activate()
        focus.setBlocklist(everything)
        focus.start()
        workspace.bringToFront(discord)
        XCTAssertEqual(focus.blockedThisSession, 1)

        focus.stop()
        focus.start(.work)

        XCTAssertEqual(focus.blockedThisSession, 0)
        focus.deactivate()
    }

    // MARK: - TC-FOC-016

    func test_TC_FOC_016_aListedTabInTheFrontBrowserGoesBlank() async {
        let workspace = FakeWorkspace()
        workspace.address = "https://old.reddit.com/r/swift"
        let (focus, _) = makeService(workspace)
        focus.activate()
        focus.setBlocklist(everything)
        focus.start()

        workspace.bringToFront(safari)
        await settle()

        XCTAssertEqual(workspace.blanks, 1)
        XCTAssertEqual(focus.blockedThisSession, 1)
        XCTAssertTrue(workspace.hidden.isEmpty, "the browser itself is never hidden")
        focus.deactivate()
    }

    func test_TC_FOC_016_tabsAreReadOnlyWhileABrowserIsInFront() async {
        let workspace = FakeWorkspace()
        let (focus, _) = makeService(workspace)
        focus.activate()
        focus.setBlocklist(everything)
        focus.start()

        workspace.bringToFront(notes)
        await settle()
        XCTAssertEqual(workspace.reads, 0, "Notes in front: nothing read")

        workspace.bringToFront(safari)
        await settle()
        XCTAssertTrue(focus.blocker.isCheckingTabs)
        XCTAssertGreaterThan(workspace.reads, 0)

        // A read already on its way may land, and is thrown away by the
        // cancellation check; after that, none at all.
        workspace.bringToFront(notes)
        XCTAssertFalse(focus.blocker.isCheckingTabs)
        await settle()
        let readsAfterLeaving = workspace.reads
        await settle()
        XCTAssertEqual(workspace.reads, readsAfterLeaving, "no reads once Safari has gone")
        focus.deactivate()
    }

    func test_TC_FOC_016_firefoxIsNeverScripted() async {
        let workspace = FakeWorkspace()
        workspace.address = "https://reddit.com"
        let (focus, _) = makeService(workspace)
        focus.activate()
        focus.setBlocklist(everything)
        focus.start()

        workspace.bringToFront(firefox)
        await settle()

        XCTAssertEqual(workspace.reads, 0)
        XCTAssertTrue(workspace.hidden.isEmpty)
        focus.deactivate()
    }

    func test_TC_FOC_016_appsOnlyMeansNoTabIsEverRead() async {
        let workspace = FakeWorkspace()
        let (focus, _) = makeService(workspace)
        focus.activate()
        focus.setBlocklist(DistractionBlocklist(blocksApps: true, apps: ["com.hnc.Discord"]))
        focus.start()

        workspace.bringToFront(safari)
        await settle()

        XCTAssertEqual(workspace.reads, 0)
        focus.deactivate()
    }

    // MARK: - TC-FOC-018

    func test_TC_FOC_018_aRefusedBrowserIsNamedAndNotAskedAgain() async {
        let workspace = FakeWorkspace()
        workspace.address = nil
        let (focus, _) = makeService(workspace)
        focus.activate()
        focus.setBlocklist(everything)
        focus.start()

        workspace.bringToFront(safari)
        await settle()

        XCTAssertEqual(focus.blocker.refusedBrowsers, ["Safari"])
        XCTAssertEqual(workspace.reads, 1, "one refusal stops the checks")
        XCTAssertFalse(focus.blocker.isCheckingTabs)

        workspace.bringToFront(discord)
        XCTAssertEqual(workspace.hidden, ["com.hnc.Discord"], "apps still blocked")
        focus.deactivate()
    }
}
