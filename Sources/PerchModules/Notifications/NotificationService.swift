import AppKit
import Combine
import Defaults
import PerchCore
import SwiftUI

/// Module 8 — notification mirroring.
///
/// **Nothing polls.** An `AXObserver` on the process that draws banners
/// pushes every one as it appears; between two notifications the module is
/// running no code at all. What it costs when off is nothing — the observer
/// is removed and the run loop source with it (TC-NTF-009).
///
/// Every rule about which notifications reach the island lives in
/// `NotificationPolicy` in Core, where it is a unit test rather than a
/// judgement call in a callback.
@MainActor
final class NotificationService: ObservableObject, PerchModule {

    static let moduleID: ModuleID = .notifications

    @Published private(set) var policy = NotificationPolicy()

    /// Whether the watcher is actually attached. False means Accessibility
    /// has not been granted, or the banner process could not be found —
    /// both of which the settings pane explains (TC-NTF-008).
    @Published private(set) var isWatching = false

    /// Apps Perch has seen post a notification, for the list in Preferences.
    ///
    /// Built from what has actually arrived rather than from every installed
    /// app: a list of four hundred bundle identifiers is not a preference,
    /// it is a haystack.
    @Published private(set) var knownApps: [String: String] = [:]

    private(set) var isActive = false

    private let island: IslandController
    private let watcher = NotificationWatcher()

    /// Read on demand, once per banner. The HUD module owns the only kqueue
    /// on the Focus database; this asks the same reader for an answer
    /// without watching anything (TC-NTF-007).
    private let focusWatcher = FocusWatcher()

    /// Whether a Pomodoro is running. Injected by the registry from the
    /// focus module when it is switched on, because a module may not reach
    /// into another one — the switchboard is the only thing that knows about
    /// both (`CLAUDE.md` §4).
    var isFocusSessionRunning: @MainActor () -> Bool = { false }

    init(island: IslandController) {
        self.island = island
        self.policy = NotificationPolicy(configuration: Defaults[.notificationPolicy])
    }

    // MARK: - PerchModule

    func activate() {
        guard !isActive else { return }
        isActive = true

        watcher.onNotification = { [weak self] notification in
            self?.receive(notification)
        }

        // Accessibility is not requested here. The module can be switched on
        // and explain itself first; the prompt comes from the button in its
        // settings pane (`CLAUDE.md` §5.3, TC-PRV-002).
        isWatching = watcher.start()
    }

    func deactivate() {
        guard isActive else { return }
        isActive = false

        watcher.onNotification = nil
        watcher.stop()
        isWatching = false

        policy.reset()
        island.setRequiresKeyFocus(false)
        island.withdrawAll(from: .notifications)
    }

    // MARK: - Arrival

    private func receive(_ notification: MirroredNotification) {
        guard isActive else { return }

        remember(notification)

        let wasFocusRunning = isFocusSessionRunning()

        let outcome = policy.receive(
            notification,
            isFocusSessionRunning: wasFocusRunning,
            isDoNotDisturbOn: focusWatcher.isFocusOn
        )

        switch outcome {
        case .present(let burst):
            present(burst)
        case .hold, .drop:
            break
        }
    }

    private func present(_ burst: NotificationPolicy.Burst) {
        island.submit(
            NotificationActivity(
                burst: burst,
                canReplyNow: burst.latest.canReply && watcher.isTrusted
            )
        )
    }

    /// Releases everything held through a focus session.
    ///
    /// Called by the focus module when a session ends, through the registry.
    /// Oldest first, so the order they arrived in is the order they appear.
    func releaseHeldNotifications() {
        guard isActive else { return }

        for burst in policy.releaseHeld() {
            present(burst)
        }
    }

    private func remember(_ notification: MirroredNotification) {
        guard let bundleID = notification.bundleID else { return }
        knownApps[bundleID] = notification.appName
    }

    // MARK: - Actions

    /// Sends a reply through the banner the notification came from.
    ///
    /// Returns false when the banner has gone or never had a field, which
    /// the view turns into "open the app" rather than a silent failure
    /// (TC-NTF-011).
    @discardableResult
    func reply(with text: String) -> Bool {
        guard isActive, watcher.reply(with: text) else { return false }
        dismiss()
        return true
    }

    /// Brings the app that posted the notification forward, and clears the
    /// island. The fallback for everything the reply field cannot do.
    func open() {
        defer { dismiss() }

        guard
            let bundleID = policy.current?.bundleID,
            let app =
                NSRunningApplication
                .runningApplications(withBundleIdentifier: bundleID)
                .first
        else { return }

        app.activate()
    }

    /// Takes the keyboard for the reply field, and gives it straight back.
    ///
    /// The island is a surface you touch, not one you focus — typing has to
    /// keep going to the app in front of you (TC-ISL-008). The clipboard's
    /// search field is the only other thing that raises this, and it lowers
    /// it the moment the picker closes.
    func setReplyFieldActive(_ isActive: Bool) {
        guard self.isActive else { return }
        island.setRequiresKeyFocus(isActive)
    }

    func dismiss() {
        guard let burst = policy.current else { return }
        island.setRequiresKeyFocus(false)
        island.withdraw(
            NotificationActivity(burst: burst, canReplyNow: false).id
        )
        policy.clearCurrent()
    }

    /// Asks for Accessibility and attaches if it is granted. Called from the
    /// settings pane, never on switching the module on.
    func requestAccessibility() {
        watcher.requestTrust()
        isWatching = watcher.start()
    }

    func setConfiguration(_ configuration: NotificationPolicy.Configuration) {
        policy.setConfiguration(configuration)
        Defaults[.notificationPolicy] = configuration
    }
}
