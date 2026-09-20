import AppKit
import Foundation

/// The agent that draws the stock overlay.
private let osdBundleID = "com.apple.OSDUIHelper"

/// Stops macOS drawing its own overlay while Perch is drawing one.
///
/// Without this the module is worse than useless: you press a volume key and
/// get *two* HUDs, one in the notch and one in the middle of the screen. That
/// is TC-HUD-001, and it is the row the whole module rests on.
///
/// **How.** `OSDUIHelper` is suspended with `SIGSTOP` while the module is on
/// and resumed with `SIGCONT` the moment it goes off. It is never killed: a
/// suspended process is a completely reversible state, `SIGCONT` restores the
/// stock HUD immediately and exactly (TC-HUD-003), and killing it would only
/// have launchd respawn it for as long as Perch ran.
/// [ADR 0005](../../../docs/adr/0005-private-apis-for-the-hud.md) is the
/// decision, including what happens if a future macOS renames the agent.
///
/// **Catching it when it launches, which is the hard half.** `OSDUIHelper` is
/// started on demand the first time something wants an overlay, so it is
/// usually not running when the module is switched on. There is no
/// notification for it: `NSWorkspace.didLaunchApplicationNotification` does
/// **not** fire for this agent — verified on hardware, launched both directly
/// and through LaunchServices — because it is not an application `NSWorkspace`
/// reports at all.
///
/// So the trigger is Perch's own HUD events, which is the one moment we know
/// that something asked macOS for an overlay. `reassert()` is called then, and
/// it schedules a single *delayed* stop rather than stopping immediately: a
/// process suspended while its window is on screen leaves that window frozen
/// there until it resumes, which would be a worse bug than the one being
/// fixed. Waiting until the stock overlay has faded makes the suspend clean.
///
/// The cost of that is exact and worth stating plainly: after `OSDUIHelper`
/// starts, **one** stock overlay is drawn before it is caught. It then stays
/// suspended for the rest of the session — so it is one overlay per launch of
/// the agent, not one per key press.
@MainActor
final class StockHUD {

    /// Longer than the stock overlay stays on screen, so the process is idle
    /// and window-less by the time it is suspended.
    private static let settleDelay: Duration = .seconds(2.5)

    /// Whether suppression is *wanted*.
    private(set) var isSuppressed = false

    /// Whether a running agent is actually suspended right now. Distinct from
    /// `isSuppressed`: the agent is often not running at all, and then there
    /// is nothing yet to suspend.
    private(set) var hasStoppedAgent = false

    private var pendingStop: Task<Void, Never>?

    /// Switches suppression on, and stops the agent if it is already running.
    @discardableResult
    func suppress() -> Bool {
        isSuppressed = true
        hasStoppedAgent = signalAll(SIGSTOP)
        return hasStoppedAgent
    }

    /// Puts it back, immediately. Must be safe to call when nothing was ever
    /// suspended, because `deactivate()` is (TC-HUD-003).
    func restore() {
        isSuppressed = false
        hasStoppedAgent = false

        pendingStop?.cancel()
        pendingStop = nil

        signalAll(SIGCONT)
    }

    /// Called when Perch shows a HUD of its own.
    ///
    /// That is the only reliable signal that something asked macOS for an
    /// overlay, and therefore that `OSDUIHelper` may just have been started.
    /// Does nothing once the agent is already suspended, so the common case
    /// costs one boolean.
    func reassert() {
        guard isSuppressed, !hasStoppedAgent, pendingStop == nil else { return }

        pendingStop = Task { [weak self] in
            try? await Task.sleep(for: Self.settleDelay)
            guard !Task.isCancelled, let self, self.isSuppressed else { return }

            self.hasStoppedAgent = self.signalAll(SIGSTOP)
            self.pendingStop = nil
        }
    }

    // MARK: - Internals

    @discardableResult
    private func signalAll(_ signal: Int32) -> Bool {
        let running = NSRunningApplication.runningApplications(
            withBundleIdentifier: osdBundleID
        )
        guard !running.isEmpty else { return false }

        var sent = false
        for app in running where app.processIdentifier > 0 {
            // A failure here is not worth surfacing: the only ways it fails
            // are the process having exited between the lookup and the call,
            // or somebody having already stopped it. Both are fine.
            if kill(app.processIdentifier, signal) == 0 { sent = true }
        }
        return sent
    }
}
