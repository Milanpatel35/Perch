import AppKit
import Combine
import Defaults
import Foundation
import KeyboardShortcuts
import PerchCore

/// Module 4 — the focus timer.
///
/// **There is no ticking anywhere in this module.** That is worth saying out
/// loud, because a Pomodoro timer is the most obvious place in the whole app
/// to put a one-second repeating timer, and `CLAUDE.md` §5.1 forbids exactly
/// that. Three things make it unnecessary:
///
/// - `PomodoroTimer` is wall-clock. A running phase is a `Date` it ends at,
///   and the time left is computed on demand.
/// - The **view** draws the countdown with `Text(timerInterval:)`, which
///   macOS renders itself. Perch does not redraw it, and it does not exist
///   when the island is not showing it.
/// - Completion is **one** `Task.sleep`, to the moment the phase ends. Not a
///   poll, and cancelled the instant anything changes.
///
/// Waking from sleep is handled by asking the timer what time it is, which is
/// the whole of TC-FOC-004 — see `PomodoroTimer.advance(to:)`.
@MainActor
final class FocusService: ObservableObject, PerchModule {

    static let moduleID: ModuleID = .focus

    @Published private(set) var timer = PomodoroTimer()
    @Published private(set) var streak = FocusStreak()

    /// What to keep out of the way during a work phase. Kept here rather
    /// than in the blocker, which only exists while a session needs it.
    @Published var blocklist: DistractionBlocklist

    /// Apps hidden and tabs blanked since the session started.
    @Published var blockedThisSession = 0

    private(set) var isActive = false

    let island: IslandController
    private let directory: URL

    /// The single scheduled wake-up: one per running phase, cancelled and
    /// replaced whenever the phase changes.
    private var completion: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []

    /// Hides apps and blanks tabs. See `FocusService+Blocking.swift`.
    let blocker: FocusBlocker

    /// Called when a work phase finishes.
    ///
    /// The notification module holds notifications through a session and
    /// releases them here (TC-NTF-006). Wired by `PerchModuleRegistry`, not
    /// by either module — neither may reach into the other.
    var onSessionEnded: (@MainActor () -> Void)?

    /// Injected so tests can drive the clock. Production passes `Date.init`.
    private let now: @MainActor () -> Date

    init(
        island: IslandController,
        directory: URL? = nil,
        blocking: FocusBlocker.System? = nil,
        now: @escaping @MainActor () -> Date = { Date() }
    ) {
        self.island = island
        self.directory = directory ?? Self.defaultDirectory
        self.now = now
        self.blocklist = Defaults[.distractionBlocklist]
        self.blocker = FocusBlocker(system: blocking ?? .live)
        blocker.onBlocked = { [weak self] name in self?.blocked(name) }
        blocker.onRefusalsChanged = { [weak self] in self?.objectWillChange.send() }
    }

    static var defaultDirectory: URL {
        let base =
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSTemporaryDirectory())

        return
            base
            .appendingPathComponent(
                Bundle.main.bundleIdentifier ?? "app.perch.Perch",
                isDirectory: true
            )
            .appendingPathComponent("Focus", isDirectory: true)
    }

    // MARK: - PerchModule

    func activate() {
        guard !isActive else { return }
        isActive = true

        load()
        timer.configuration = Defaults[.pomodoroConfiguration]

        observeWake()
        registerShortcut()

        // A session that was running when Perch last quit is not resumed. The
        // timer is a thing you start on purpose, and silently resuming one
        // from yesterday would be worse than forgetting it.
        if timer.isRunning { timer.pause(now: now()) }
        present()
        syncBlocking()
    }

    func deactivate() {
        guard isActive else { return }
        isActive = false

        completion?.cancel()
        completion = nil

        for observer in observers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observers.removeAll()

        KeyboardShortcuts.disable(.focusTimer)
        blocker.stop()
        save()

        island.withdraw(FocusActivity.identifier)
        island.withdraw(FocusFinishedActivity.identifier)
    }

    // MARK: - Driving

    func start(_ phase: PomodoroTimer.Phase? = nil) {
        guard isActive else { return }

        timer.start(phase ?? timer.phase ?? .work, now: now())
        island.withdraw(FocusFinishedActivity.identifier)
        schedule()
        present()
        startCountingBlocks()
        syncBlocking()
    }

    /// The home surface's Focus button and its F key: start when idle,
    /// otherwise pause or resume — what the button says (`HomeLauncher`).
    func launch() {
        if HomeLauncher.FocusAction(timer) == .start {
            start()
        } else {
            toggle()
        }
    }

    func toggle() {
        guard isActive else { return }

        timer.toggle(now: now())
        island.withdraw(FocusFinishedActivity.identifier)
        schedule()
        present()
        syncBlocking()
    }

    func stop() {
        guard isActive else { return }

        timer.stop()
        completion?.cancel()
        completion = nil

        island.withdraw(FocusActivity.identifier)
        island.withdraw(FocusFinishedActivity.identifier)
        syncBlocking()
        save()
    }

    func setConfiguration(_ configuration: PomodoroTimer.Configuration) {
        timer.configuration = configuration
        Defaults[.pomodoroConfiguration] = configuration

        // A duration change mid-session would move the finish line under
        // somebody. It applies to the next phase.
        guard timer.isIdle else { return }
        present()
    }

    // MARK: - The one scheduled wake-up

    private func schedule() {
        completion?.cancel()
        completion = nil

        guard isActive, let endsAt = timer.endsAt else { return }

        let delay = max(0, endsAt.timeIntervalSince(now()))
        completion = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.advance()
        }
    }

    /// Brings the timer up to date and announces anything that finished.
    ///
    /// Called by the scheduled wake-up and again on waking from sleep. Both
    /// can be right at once, which is why `advance(to:)` only ever reports a
    /// phase once.
    private func advance() {
        guard isActive else { return }
        guard let finished = timer.advance(to: now()) else {
            // Nothing finished — the sleep was cut short, or the wake handler
            // got here first. Re-arm against the real end.
            schedule()
            return
        }

        if finished == .work {
            streak.recordCompletedSession(at: now())
        }
        save()

        onSessionEnded?()
        syncBlocking()

        completion?.cancel()
        completion = nil

        island.withdraw(FocusActivity.identifier)
        island.submit(
            FocusFinishedActivity(
                finished: finished,
                next: timer.phase ?? .work,
                sessionsToday: streak.sessions(on: now()),
                streakDays: streak.streak(on: now())
            )
        )
    }

    /// The wall clock moved while we were not looking. Ask the timer what
    /// time it is — TC-FOC-004.
    private func observeWake() {
        let center = NSWorkspace.shared.notificationCenter
        observers.append(
            center.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil,
                queue: .main
            ) { _ in
                MainActor.assumeIsolated { self.handleWake() }
            }
        )
    }

    /// The wall clock moved. Internal rather than private so the tests can
    /// drive it directly: posting a real `didWakeNotification` would deliver
    /// asynchronously through an operation queue, and a test that races its
    /// own notification proves nothing.
    func handleWake() {
        advance()
        present()
    }

    // MARK: - Presenting

    private func present() {
        guard isActive else { return }
        guard !timer.isIdle else {
            island.withdraw(FocusActivity.identifier)
            return
        }

        island.submit(
            FocusActivity(
                timer: timer,
                sessionsToday: streak.sessions(on: now()),
                streakDays: streak.streak(on: now())
            )
        )
    }

    /// No default shortcut: a module that claims a global hotkey without
    /// being asked will collide with something, and the collision is silent.
    /// The clipboard's picker made the same choice for the same reason.
    private func registerShortcut() {
        KeyboardShortcuts.onKeyUp(for: .focusTimer) { [weak self] in
            MainActor.assumeIsolated { self?.toggle() }
        }
        KeyboardShortcuts.enable(.focusTimer)
    }

    // MARK: - Storage

    private var streakURL: URL { directory.appendingPathComponent("streak.json") }

    private func load() {
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        guard
            let data = try? Data(contentsOf: streakURL),
            let decoded = try? JSONDecoder().decode(FocusStreak.self, from: data)
        else { return }

        streak = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(streak) else { return }
        try? data.write(to: streakURL, options: .atomic)
    }
}

extension KeyboardShortcuts.Name {
    /// Deliberately without a default. See `registerShortcut`.
    static let focusTimer = Self("focusTimer")
}
