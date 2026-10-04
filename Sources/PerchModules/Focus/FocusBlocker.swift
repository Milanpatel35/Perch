import AppKit
import Foundation
import PerchCore

/// Keeps listed apps and sites out of the way during a focus session.
///
/// **It exists only while a work phase is counting down** (TC-FOC-013).
/// Outside one there is no observer, no task and no Apple Event — the
/// module being on, and the blocklist being full, cost nothing until a
/// session starts (TC-FOC-014).
///
/// Apps are event-driven: the workspace says which app came to the front,
/// and a listed one is hidden. Tabs cannot be: no browser says that its
/// front tab changed. So while — and only while — a scriptable browser is
/// frontmost during a session, its front tab is read every two seconds.
/// [ADR 0009](../../../docs/adr/0009-checking-the-front-tab-during-focus.md)
/// records why that is the one acceptable poll here, and its limits.
@MainActor
final class FocusBlocker {

    /// Everything the blocker touches outside itself. Tests replace it.
    struct System {
        /// Calls back with each app that comes to the front; returns the
        /// way to stop.
        var observeActivations: (@escaping @MainActor (FrontApp) -> Void) -> () -> Void
        var frontmost: () -> FrontApp?
        var hide: (FrontApp) -> Bool
        var run: @Sendable (String) async -> ScriptOutcome
        var sleep: @Sendable (Duration) async -> Void
        var ownBundleID: String?
    }

    struct FrontApp: Equatable {
        let bundleID: String
        let name: String
        let processID: pid_t
    }

    enum ScriptOutcome: Equatable, Sendable {
        case value(String)
        /// Automation for that browser was refused.
        case notPermitted
        case failed
    }

    /// How often the front tab is read, while a browser is in front.
    static let tabInterval: Duration = .seconds(2)

    /// Something just hidden or blanked, by name.
    var onBlocked: ((String) -> Void)?

    /// The refused browsers changed, so the pane can say so.
    var onRefusalsChanged: (() -> Void)?

    private(set) var isRunning = false
    private(set) var isCheckingTabs = false

    /// Browsers whose Automation consent was refused — named in the pane.
    private(set) var refusedBrowsers: Set<String> = [] {
        didSet {
            if refusedBrowsers != oldValue { onRefusalsChanged?() }
        }
    }

    private let system: System
    private var blocklist = DistractionBlocklist()
    private var stopObserving: (() -> Void)?
    private var tabTask: Task<Void, Never>?

    init(system: System) {
        self.system = system
    }

    /// Brings the blocker in line with the session. Called after anything
    /// that could change the answer: the timer, the list, the module.
    func update(_ blocklist: DistractionBlocklist, enforced: Bool) {
        self.blocklist = blocklist
        guard enforced else { return stop() }

        if !isRunning {
            isRunning = true
            stopObserving = system.observeActivations { [weak self] app in
                self?.cameToFront(app)
            }
        }
        // Whatever is in front now gets the same treatment as an app that
        // just arrived: a session started over reddit should not wait for
        // somebody to switch away and back.
        if let front = system.frontmost() { cameToFront(front) }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        stopObserving?()
        stopObserving = nil
        stopCheckingTabs()
    }

    // MARK: - Apps

    private func cameToFront(_ app: FrontApp) {
        guard isRunning else { return }

        if blocklist.blocksApp(app.bundleID, ownBundleID: system.ownBundleID) {
            stopCheckingTabs()
            // Hidden, never quit: reversible, and nothing is lost.
            if system.hide(app) { onBlocked?(app.name) }
            return
        }

        if blocklist.watchesSites, let browser = Browser.scriptable(app.bundleID) {
            startCheckingTabs(in: browser, bundleID: app.bundleID)
        } else {
            stopCheckingTabs()
        }
    }

    // MARK: - Tabs

    private func startCheckingTabs(in browser: Browser, bundleID: String) {
        stopCheckingTabs()
        isCheckingTabs = true

        tabTask = Task { [weak self, system] in
            while !Task.isCancelled {
                guard let self, await self.checkFrontTab(in: browser) else { break }
                await system.sleep(Self.tabInterval)
            }
        }
    }

    private func stopCheckingTabs() {
        tabTask?.cancel()
        tabTask = nil
        isCheckingTabs = false
    }

    /// Reads the front tab once and blanks it if it is listed. Returns
    /// whether to keep checking: not once the browser has been refused.
    private func checkFrontTab(in browser: Browser) async -> Bool {
        let outcome = await system.run(browser.readFrontTab)
        guard isRunning, !Task.isCancelled else { return false }

        switch outcome {
        case .notPermitted:
            refusedBrowsers.insert(browser.name)
            isCheckingTabs = false
            return false
        case .failed:
            return true
        case .value(let address):
            refusedBrowsers.remove(browser.name)
            guard blocklist.blocksPage(address) else { return true }
            _ = await system.run(browser.blankFrontTab)
            onBlocked?(URL(string: address)?.host ?? browser.name)
            return true
        }
    }
}

// MARK: - The real system

extension FocusBlocker.System {

    static var live: Self {
        Self(
            observeActivations: { handler in
                let center = NSWorkspace.shared.notificationCenter
                let token = center.addObserver(
                    forName: NSWorkspace.didActivateApplicationNotification,
                    object: nil,
                    queue: .main
                ) { note in
                    let app =
                        note.userInfo?[NSWorkspace.applicationUserInfoKey]
                        as? NSRunningApplication
                    MainActor.assumeIsolated {
                        if let app = app.flatMap(FocusBlocker.FrontApp.init) { handler(app) }
                    }
                }
                return { center.removeObserver(token) }
            },
            frontmost: {
                NSWorkspace.shared.frontmostApplication.flatMap(FocusBlocker.FrontApp.init)
            },
            hide: { app in
                NSRunningApplication(processIdentifier: app.processID)?.hide() ?? false
            },
            run: { await BrowserScriptRunner.shared.run($0) },
            sleep: { try? await Task.sleep(for: $0) },
            ownBundleID: Bundle.main.bundleIdentifier
        )
    }
}

extension FocusBlocker.FrontApp {
    init?(_ app: NSRunningApplication) {
        guard let bundleID = app.bundleIdentifier else { return nil }
        self.init(
            bundleID: bundleID,
            name: app.localizedName ?? bundleID,
            processID: app.processIdentifier
        )
    }
}

/// Runs the browser scripts off the main thread, one at a time.
private final class BrowserScriptRunner: @unchecked Sendable {

    static let shared = BrowserScriptRunner()

    private let queue = DispatchQueue(label: "app.perch.focus.browser")

    /// `errAEEventNotPermitted`: Automation was refused for that app.
    private static let notPermitted = -1_743

    func run(_ source: String) async -> FocusBlocker.ScriptOutcome {
        await withCheckedContinuation { continuation in
            queue.async {
                var error: NSDictionary?
                let result = NSAppleScript(source: source)?.executeAndReturnError(&error)

                if let code = error?[NSAppleScript.errorNumber] as? Int {
                    continuation.resume(
                        returning: code == Self.notPermitted ? .notPermitted : .failed)
                } else {
                    continuation.resume(returning: .value(result?.stringValue ?? ""))
                }
            }
        }
    }
}
