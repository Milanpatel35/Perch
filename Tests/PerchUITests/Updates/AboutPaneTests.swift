import AppKit
import SwiftUI
import XCTest

@testable import PerchUI

/// Covers `TEST-PLAN.md` TC-UPD-008 and TC-HOM-010: the About and Keyboard
/// Shortcuts panes actually draw.
///
/// Rendered in a real on-screen window, with the About row selected in the
/// sidebar the way a click selects it. Nothing short of that showed the bug:
/// `AboutSettingsView` drew perfectly on its own, and only inside the split
/// view did a `.fixedSize` in the Updates box blank the whole window.
@MainActor
final class AboutPaneTests: XCTestCase {

    private var window: NSWindow?

    override func tearDown() async throws {
        window?.close()
        window = nil
    }

    private func sidebar(in view: NSView) -> NSTableView? {
        if let table = view as? NSTableView { return table }
        return view.subviews.lazy.compactMap { self.sidebar(in: $0) }.first
    }

    /// How many sampled points are bright — text, in dark mode. A window
    /// that drew nothing has next to none.
    private func brightPoints(in window: NSWindow, name: String) throws -> Int {
        let view = try XCTUnwrap(window.contentView)
        let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        if let directory = ProcessInfo.processInfo.environment["PERCH_CAPTURE_DIR"] {
            try rep.representation(using: .png, properties: [:])?
                .write(to: URL(fileURLWithPath: directory).appendingPathComponent("\(name).png"))
        }

        var bright = 0
        for x in stride(from: 0, to: rep.pixelsWide, by: 3) {
            for y in stride(from: 0, to: rep.pixelsHigh, by: 3) {
                let colour = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB)
                if (colour?.brightnessComponent ?? 0) > 0.6 { bright += 1 }
            }
        }
        return bright
    }

    func test_TC_UPD_008_theAboutPaneDrawsWithItsUpdatesBox() throws {
        // About is the sidebar's last row.
        try assertPaneDraws(
            row: { $0.numberOfRows - 1 }, name: "settings-about", "the About pane drew nothing")
    }

    /// TC-HOM-010. Its explanation is a wrapping text in a split view —
    /// the shape that blanked About.
    func test_TC_HOM_010_theKeyboardShortcutsPaneDraws() throws {
        // General, then Keyboard Shortcuts.
        try assertPaneDraws(
            row: { _ in 1 }, name: "settings-keyboard", "the Keyboard Shortcuts pane drew nothing")
    }

    private func assertPaneDraws(
        row: (NSTableView) -> Int, name: String, _ message: String
    ) throws {
        let updates = SoftwareUpdates(
            checksAutomatically: true,
            lastChecked: Date().addingTimeInterval(-3_600),
            check: {},
            setChecksAutomatically: { _ in }
        )
        let preferences = PreferencesView(
            switchboard: ModuleSwitchboard(),
            launchAtLogin: LaunchAtLogin(),
            updates: updates,
            paneProvider: { _ in nil }
        )

        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 760, height: 520),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        self.window = window
        window.appearance = NSAppearance(named: .darkAqua)
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: preferences)
        window.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(1))

        let table = try XCTUnwrap(sidebar(in: try XCTUnwrap(window.contentView)))
        table.selectRowIndexes([row(table)], byExtendingSelection: false)
        RunLoop.main.run(until: Date().addingTimeInterval(1.5))

        // Blank measured 58. Drawn, About measured over 2,000 here and the
        // sparser Keyboard Shortcuts pane about 900 on CI's runners.
        XCTAssertGreaterThan(try brightPoints(in: window, name: name), 300, message)
    }
}
