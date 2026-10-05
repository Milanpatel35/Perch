import AppKit
import KeyboardShortcuts
import XCTest

@testable import PerchCore
@testable import PerchUI

/// Covers `TEST-PLAN.md` TC-HOM-007 … 009: the island opened and driven
/// from the keyboard, and the suggested shortcuts.
///
/// Keys go straight to `handle(key:keyCode:modifiers:)` — the monitor in
/// front of it only filters out events meant for other windows.
@MainActor
final class HomeKeyboardTests: XCTestCase {

    nonisolated(unsafe) private var directory = URL(fileURLWithPath: NSTemporaryDirectory())

    private struct Harness {
        let island: IslandController
        let modules: ModuleHost
        let keyboard: HomeKeyboard
        let focus: FocusService
    }

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("perch-keyboard-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        try super.tearDownWithError()
    }

    private func makeHarness() -> Harness {
        let island = IslandController(sleep: { _ in try await Task.sleep(for: .seconds(86_400)) })
        let modules = ModuleHost(switchboard: ModuleSwitchboard(), island: island)
        let focus = FocusService(island: island, directory: directory)
        modules.register(focus)
        focus.activate()
        island.submit(HomeActivity(collapsedSize: CGSize(width: 186, height: 32)))
        return Harness(
            island: island,
            modules: modules,
            keyboard: HomeKeyboard(modules: modules, island: island),
            focus: focus
        )
    }

    // MARK: - TC-HOM-007

    func test_TC_HOM_007_openingTakesTheKeyboardAndEscapeGivesItBack() {
        let harness = makeHarness()
        defer { harness.focus.deactivate() }

        harness.keyboard.open()
        XCTAssertEqual(harness.island.state.presentation, .expanded(HomeActivity.identifier))
        XCTAssertTrue(harness.island.requiresKeyFocus)

        XCTAssertTrue(harness.keyboard.handle(key: "\u{1b}", keyCode: 53, modifiers: []))
        XCTAssertFalse(harness.island.requiresKeyFocus)
        XCTAssertNotEqual(harness.island.state.presentation, .expanded(HomeActivity.identifier))
    }

    func test_TC_HOM_007_theKeyboardGoesBackHoweverTheHomeSurfaceCloses() {
        let harness = makeHarness()
        defer { harness.focus.deactivate() }

        harness.keyboard.open()
        harness.island.send(.collapseRequested)

        XCTAssertFalse(harness.keyboard.isListening)
        XCTAssertFalse(harness.island.requiresKeyFocus)
    }

    func test_TC_HOM_007_itOpensWhileMusicIsPlayingToo() {
        let harness = makeHarness()
        defer { harness.focus.deactivate() }
        harness.island.submit(NowPlayingActivity(snapshot: .demo))
        XCTAssertEqual(harness.island.presented?.id, NowPlayingActivity.identifier)

        harness.keyboard.open()

        XCTAssertEqual(harness.island.state.presentation, .expanded(NowPlayingActivity.identifier))
        XCTAssertTrue(harness.keyboard.isListening)
        XCTAssertTrue(harness.keyboard.handle(key: "3", keyCode: 20, modifiers: []))
        XCTAssertEqual(harness.modules.homeTab, .calendar)
        XCTAssertTrue(harness.keyboard.isListening, "a tab key closed the island")

        harness.keyboard.close()
    }

    // MARK: - TC-HOM-008

    func test_TC_HOM_008_aLetterRunsItsActionAndHandsTheKeyboardBack() {
        let harness = makeHarness()
        defer { harness.focus.deactivate() }

        harness.keyboard.open()
        XCTAssertTrue(harness.keyboard.handle(key: "f", keyCode: 3, modifiers: []))

        XCTAssertTrue(harness.focus.timer.isRunning)
        XCTAssertFalse(harness.keyboard.isListening)
        XCTAssertFalse(harness.island.requiresKeyFocus)
    }

    func test_TC_HOM_008_lettersForModulesThatAreOffAndModifiedKeysAreLeftAlone() {
        let harness = makeHarness()
        defer { harness.focus.deactivate() }

        harness.keyboard.open()
        // The clipboard is not registered here, so C has nothing to do.
        XCTAssertFalse(harness.keyboard.handle(key: "c", keyCode: 8, modifiers: []))
        // ⌘F belongs to whoever defined it.
        XCTAssertFalse(harness.keyboard.handle(key: "f", keyCode: 3, modifiers: .command))
        XCTAssertFalse(harness.focus.timer.isRunning)
        XCTAssertTrue(harness.keyboard.isListening)

        harness.keyboard.close()
    }

    func test_TC_HOM_008_twoOwnersOfTheKeyboardDoNotDropEachOther() {
        let island = IslandController(sleep: { _ in try await Task.sleep(for: .seconds(86_400)) })

        island.setRequiresKeyFocus(true, owner: "clipboard")
        island.setRequiresKeyFocus(true, owner: "home.keyboard")
        island.setRequiresKeyFocus(false, owner: "home.keyboard")
        XCTAssertTrue(island.requiresKeyFocus, "the clipboard lost its search field")

        island.setRequiresKeyFocus(false, owner: "clipboard")
        XCTAssertFalse(island.requiresKeyFocus)
    }

    // MARK: - TC-HOM-009

    func test_TC_HOM_009_suggestedShortcutsFillTheGapsAndKeepYours() {
        let names = SuggestedShortcuts.all.map(\.name)
        let saved = names.map { KeyboardShortcuts.getShortcut(for: $0) }
        defer {
            for (name, shortcut) in zip(names, saved) {
                KeyboardShortcuts.setShortcut(shortcut, for: name)
            }
        }

        for name in names { KeyboardShortcuts.setShortcut(nil, for: name) }
        let mine = KeyboardShortcuts.Shortcut(.k, modifiers: [.command, .shift])
        KeyboardShortcuts.setShortcut(mine, for: .clipboardPicker)

        XCTAssertEqual(SuggestedShortcuts.apply(), names.count - 1)
        XCTAssertEqual(KeyboardShortcuts.getShortcut(for: .clipboardPicker), mine)
        XCTAssertEqual(
            KeyboardShortcuts.getShortcut(for: .openPerch),
            KeyboardShortcuts.Shortcut(.p, modifiers: [.control, .option])
        )

        XCTAssertEqual(SuggestedShortcuts.apply(), 0, "a second press changed something")
    }
}
