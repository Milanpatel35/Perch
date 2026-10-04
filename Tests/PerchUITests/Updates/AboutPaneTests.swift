import AppKit
import SwiftUI
import XCTest

@testable import PerchUI

/// Covers `TEST-PLAN.md` TC-UPD-008: the About pane, with its Updates box,
/// actually draws.
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
    private func brightPoints(in window: NSWindow) throws -> Int {
        let view = try XCTUnwrap(window.contentView)
        let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)

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
        // About is the sidebar's last row.
        table.selectRowIndexes([table.numberOfRows - 1], byExtendingSelection: false)
        RunLoop.main.run(until: Date().addingTimeInterval(1.5))

        // Blank measured 58; the pane drawn measured over 2,000.
        XCTAssertGreaterThan(try brightPoints(in: window), 1_000, "the About pane drew nothing")
    }
}
