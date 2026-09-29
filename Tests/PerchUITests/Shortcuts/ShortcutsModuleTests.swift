import Defaults
import PerchCore
import XCTest

@testable import PerchUI

/// Covers `TEST-PLAN.md` § SHC for the parts that need the real module: the
/// front door every `perch://` URL comes through, what a run looks like on
/// the island, the `perch` CLI end to end, and that "off" means off.
///
/// Nothing here runs a real Shortcut. The runner is a fake that records what
/// it was asked, which is also how the tests prove what was *not* run.
@MainActor
final class ShortcutsModuleTests: XCTestCase {

    private final class FakeRunner: ShortcutsRunning, @unchecked Sendable {
        var names = ["Morning", "Lights off"]
        var outcome = ShortcutOutcome.succeeded(output: "Lights are off")
        private(set) var ran: [String] = []
        private(set) var cancelled = 0
        private(set) var libraryReads = 0

        /// Holds a run open until the test lets it finish.
        var gate: CheckedContinuation<Void, Never>?
        var holdRuns = false

        func library() async -> [String] {
            libraryReads += 1
            return names
        }

        func run(_ name: String) async -> ShortcutOutcome {
            ran.append(name)
            if holdRuns {
                await withCheckedContinuation { gate = $0 }
            }
            return outcome
        }

        func cancelAll() {
            cancelled += 1
            gate?.resume()
            gate = nil
        }
    }

    private struct Harness {
        let shortcuts: ShortcutsService
        let island: IslandController
        let runner: FakeRunner
    }

    private var saved = ShortcutFavourites()

    override func setUp() async throws {
        saved = Defaults[.shortcutFavourites]
        Defaults[.shortcutFavourites] = ShortcutFavourites()
    }

    override func tearDown() async throws {
        Defaults[.shortcutFavourites] = saved
    }

    private func makeService() -> Harness {
        let island = IslandController(sleep: { _ in try await Task.sleep(for: .seconds(86_400)) })
        let runner = FakeRunner()
        return Harness(
            shortcuts: ShortcutsService(island: island, runner: runner),
            island: island,
            runner: runner
        )
    }

    private func url(_ string: String) throws -> URL {
        try XCTUnwrap(URL(string: string))
    }

    private func kind(on island: IslandController) -> ShortcutsActivity.Kind? {
        (island.presented?.base as? ShortcutsActivity)?.kind
    }

    private func priority(on island: IslandController) -> ActivityPriority? {
        island.presented?.priority
    }

    /// Lets queued main-actor work — a run finishing — land.
    private func settle() async {
        for _ in 0..<5 {
            await Task.yield()
        }
    }

    // MARK: - TC-SHC-002

    func test_TC_SHC_002_aMessageURLPresentsAtTheRightPriority() throws {
        let harness = makeService()
        harness.shortcuts.activate()

        XCTAssertTrue(
            harness.shortcuts.handle(try url("perch://notify?title=Build%20ok&urgency=high")))

        XCTAssertEqual(
            kind(on: harness.island),
            .message(.init(title: "Build ok", urgency: .high))
        )
        XCTAssertEqual(priority(on: harness.island), .incomingCall)

        harness.shortcuts.deactivate()
    }

    /// Ten messages in a row are one activity, updated — not ten queued.
    func test_TC_SHC_002_aBurstOfMessagesIsOneActivity() throws {
        let harness = makeService()
        harness.shortcuts.activate()

        for index in 1...10 {
            harness.shortcuts.handle(try url("perch://notify?title=\(index)"))
        }

        XCTAssertEqual(harness.island.queued.count, 1)
        XCTAssertEqual(kind(on: harness.island), .message(.init(title: "10")))

        harness.shortcuts.deactivate()
    }

    // MARK: - TC-SHC-003

    func test_TC_SHC_003_aMalformedURLChangesNothingAndSaysWhy() throws {
        let harness = makeService()
        harness.shortcuts.activate()

        XCTAssertFalse(harness.shortcuts.handle(try url("perch://run?name=Morning")))

        XCTAssertNil(harness.island.presented)
        XCTAssertEqual(harness.shortcuts.lastRejection, .unknownAction("run"))
        XCTAssertTrue(harness.runner.ran.isEmpty, "a URL never runs a Shortcut")

        harness.shortcuts.deactivate()
    }

    func test_TC_SHC_003_theShelfAndFocusGoThroughTheirOwnModules() throws {
        let harness = makeService()
        harness.shortcuts.activate()

        var shelved: URL?
        var focused = false
        harness.shortcuts.onAddToShelf = {
            shelved = $0
            return true
        }
        harness.shortcuts.onStartFocus = {
            focused = true
            return true
        }

        harness.shortcuts.handle(try url("perch://shelf?path=/tmp/report.pdf"))
        harness.shortcuts.handle(try url("perch://focus"))

        XCTAssertEqual(shelved, URL(fileURLWithPath: "/tmp/report.pdf"))
        XCTAssertTrue(focused)
        XCTAssertNil(harness.island.presented, "success is the other module's to announce")

        harness.shortcuts.deactivate()
    }

    /// The other module being off is said out loud, not swallowed.
    func test_TC_SHC_003_anActionWhoseModuleIsOffSaysSo() throws {
        let harness = makeService()
        harness.shortcuts.activate()
        harness.shortcuts.onStartFocus = { false }

        harness.shortcuts.handle(try url("perch://focus"))

        guard case .message(let message) = kind(on: harness.island) else {
            return XCTFail("expected an explanation on the island")
        }
        XCTAssertNotNil(message.body)

        harness.shortcuts.deactivate()
    }

    // MARK: - TC-SHC-001

    func test_TC_SHC_001_runningAFavouriteShowsItRunningThenItsResult() async {
        let harness = makeService()
        harness.shortcuts.activate()
        harness.runner.holdRuns = true

        harness.shortcuts.run("Lights off")
        await settle()

        XCTAssertEqual(kind(on: harness.island), .running(name: "Lights off"))
        XCTAssertEqual(harness.shortcuts.runningName, "Lights off")

        harness.runner.gate?.resume()
        harness.runner.gate = nil
        await settle()

        XCTAssertEqual(
            kind(on: harness.island),
            .finished(name: "Lights off", outcome: .succeeded(output: "Lights are off"))
        )
        XCTAssertNil(harness.shortcuts.runningName)
        XCTAssertEqual(harness.runner.ran, ["Lights off"])

        harness.shortcuts.deactivate()
    }

    func test_TC_SHC_001_aSecondPressWhileRunningIsIgnored() async {
        let harness = makeService()
        harness.shortcuts.activate()
        harness.runner.holdRuns = true

        harness.shortcuts.run("Morning")
        await settle()
        harness.shortcuts.run("Lights off")
        await settle()

        XCTAssertEqual(harness.runner.ran, ["Morning"])

        harness.shortcuts.deactivate()
    }

    func test_TC_SHC_001_aFailedRunIsReported() async {
        let harness = makeService()
        harness.shortcuts.activate()
        harness.runner.outcome = .failed(reason: "Couldn’t find shortcut")

        harness.shortcuts.run("Gone")
        for _ in 0..<20 where harness.shortcuts.runningName != nil {
            await settle()
        }

        XCTAssertEqual(
            kind(on: harness.island),
            .finished(name: "Gone", outcome: .failed(reason: "Couldn’t find shortcut"))
        )

        harness.shortcuts.deactivate()
    }

    // MARK: - TC-SHC-005

    func test_TC_SHC_005_favouritesPersistAndTheLibraryIsReadOnlyWhenAsked() async {
        let harness = makeService()
        harness.shortcuts.activate()
        XCTAssertEqual(harness.runner.libraryReads, 0, "switching on reads nothing")

        harness.shortcuts.refreshLibrary()
        for _ in 0..<20 where harness.shortcuts.isReadingLibrary {
            await settle()
        }
        XCTAssertEqual(harness.shortcuts.library, ["Lights off", "Morning"])

        harness.shortcuts.setFavourite("Morning", true)
        XCTAssertEqual(Defaults[.shortcutFavourites].names, ["Morning"])

        harness.shortcuts.deactivate()
    }

    // MARK: - TC-SHC-006

    /// **Off means nothing.** A URL arriving while the module is off is
    /// ignored entirely, and switching off stops a run in progress.
    func test_TC_SHC_006_whileOffAURLDoesNothing() throws {
        let harness = makeService()

        XCTAssertFalse(harness.shortcuts.handle(try url("perch://notify?title=hello")))
        harness.shortcuts.run("Morning")

        XCTAssertNil(harness.island.presented)
        XCTAssertTrue(harness.runner.ran.isEmpty)
    }

    func test_TC_SHC_006_switchingOffStopsARunAndLeavesNothing() async {
        let harness = makeService()
        harness.shortcuts.activate()
        harness.runner.holdRuns = true

        harness.shortcuts.run("Morning")
        await settle()
        harness.shortcuts.deactivate()
        await settle()

        XCTAssertFalse(harness.shortcuts.isActive)
        XCTAssertEqual(harness.runner.cancelled, 1)
        XCTAssertNil(harness.shortcuts.runningName)
        XCTAssertNil(harness.island.presented)
        XCTAssertTrue(harness.shortcuts.library.isEmpty)
    }

    func test_deactivatingTwiceIsSafe() {
        let harness = makeService()
        harness.shortcuts.activate()
        harness.shortcuts.deactivate()
        harness.shortcuts.deactivate()

        XCTAssertEqual(harness.runner.cancelled, 1)
    }
}
