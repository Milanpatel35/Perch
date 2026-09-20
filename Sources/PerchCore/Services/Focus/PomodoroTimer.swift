import Foundation

/// The focus timer, as a pure value.
///
/// **Everything is wall-clock.** A running phase is stored as the `Date` it
/// ends at, never as a number of seconds counting down, and the remaining
/// time is always *computed* from that. That is the whole of TC-FOC-004: a
/// Mac that sleeps for twenty minutes wakes up with twenty minutes less on
/// the clock, without anybody having to account for it, because nothing was
/// ever counting.
///
/// It also means there is no ticking anywhere in Perch. The module schedules
/// exactly one wake-up, for the moment the phase ends, and the view draws the
/// countdown with `Text(timerInterval:)`, which macOS renders itself. No
/// per-second timer exists at any point (`CLAUDE.md` §5.1).
public struct PomodoroTimer: Equatable, Sendable {

    public enum Phase: String, Equatable, Sendable, Codable, CaseIterable {
        case work
        case shortBreak
        case longBreak

        public var isBreak: Bool { self != .work }

        public var displayName: String {
            switch self {
            case .work: String(localized: "Focus")
            case .shortBreak: String(localized: "Break")
            case .longBreak: String(localized: "Long break")
            }
        }
    }

    public enum State: Equatable, Sendable {
        case idle

        /// Running. `endsAt` is the truth; remaining time is derived from it.
        case running(phase: Phase, endsAt: Date)

        /// Paused, holding exactly what was left. TC-FOC-003 is that this
        /// number survives the round trip unchanged.
        case paused(phase: Phase, remaining: Duration)
    }

    public struct Configuration: Equatable, Sendable, Codable {
        public var work: Duration
        public var shortBreak: Duration
        public var longBreak: Duration

        /// Work sessions before the long break. Four is the Pomodoro
        /// technique's own number and the default everywhere.
        public var sessionsBeforeLongBreak: Int

        public init(
            work: Duration = .seconds(25 * 60),
            shortBreak: Duration = .seconds(5 * 60),
            longBreak: Duration = .seconds(15 * 60),
            sessionsBeforeLongBreak: Int = 4
        ) {
            self.work = work
            self.shortBreak = shortBreak
            self.longBreak = longBreak
            self.sessionsBeforeLongBreak = sessionsBeforeLongBreak
        }

        public func duration(of phase: Phase) -> Duration {
            switch phase {
            case .work: work
            case .shortBreak: shortBreak
            case .longBreak: longBreak
            }
        }
    }

    public private(set) var state: State = .idle
    public var configuration: Configuration

    /// Work sessions finished since the last long break. Drives which break
    /// comes next; the durable counts live in `FocusStreak`.
    public private(set) var completedInCycle = 0

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    // MARK: - Reading

    public var isRunning: Bool {
        if case .running = state { return true }
        return false
    }

    public var isPaused: Bool {
        if case .paused = state { return true }
        return false
    }

    public var isIdle: Bool { state == .idle }

    public var phase: Phase? {
        switch state {
        case .idle: nil
        case .running(let phase, _), .paused(let phase, _): phase
        }
    }

    /// When the current phase ends, for the view's countdown and for the one
    /// wake-up the module schedules.
    public var endsAt: Date? {
        if case .running(_, let endsAt) = state { return endsAt }
        return nil
    }

    /// How much of the current phase is left.
    ///
    /// Bounded at both ends, and both bounds are there for a reason.
    ///
    /// **Never negative:** a phase that is over has nothing left, not a debt.
    ///
    /// **Never more than the phase is long:** if the wall clock jumps
    /// backwards — a manual change, an NTP step — the arithmetic would
    /// otherwise say a 25-minute session has 85 minutes left, which is true
    /// and useless. The clamp only affects what is *shown*; `advance(to:)`
    /// still compares against the real `endsAt`, so a clock going backwards
    /// can never make a phase finish early.
    public func remaining(at now: Date) -> Duration? {
        switch state {
        case .idle:
            nil
        case .running(let phase, let endsAt):
            .seconds(
                min(
                    configuration.duration(of: phase).seconds,
                    max(0, endsAt.timeIntervalSince(now))
                )
            )
        case .paused(_, let remaining):
            remaining
        }
    }

    /// 0–1 through the current phase, for the ring.
    public func progress(at now: Date) -> Double? {
        guard let phase, let remaining = remaining(at: now) else { return nil }

        let total = configuration.duration(of: phase).seconds
        guard total > 0 else { return nil }
        return min(1, max(0, 1 - (remaining.seconds / total)))
    }

    // MARK: - Driving

    /// Starts a phase. Defaults to work, which is what "start" means when
    /// nothing is running.
    public mutating func start(_ phase: Phase = .work, now: Date) {
        state = .running(
            phase: phase,
            endsAt: now.addingTimeInterval(
                configuration.duration(of: phase).seconds
            ))
    }

    /// Pause keeps what is left, exactly (TC-FOC-003).
    public mutating func pause(now: Date) {
        guard case .running(let phase, let endsAt) = state else { return }
        state = .paused(
            phase: phase,
            remaining: .seconds(max(0, endsAt.timeIntervalSince(now)))
        )
    }

    public mutating func resume(now: Date) {
        guard case .paused(let phase, let remaining) = state else { return }
        state = .running(phase: phase, endsAt: now.addingTimeInterval(remaining.seconds))
    }

    public mutating func toggle(now: Date) {
        switch state {
        case .idle: start(now: now)
        case .running: pause(now: now)
        case .paused: resume(now: now)
        }
    }

    /// Stops everything and forgets the cycle. Deliberately different from
    /// pausing: this is "I am done", not "hold on".
    public mutating func stop() {
        state = .idle
        completedInCycle = 0
    }

    /// Brings the timer up to date and reports what finished on the way.
    ///
    /// Called when the scheduled wake-up fires, and again on waking from
    /// sleep — where it does the whole of TC-FOC-004 by itself, because a
    /// phase whose `endsAt` is in the past is simply over.
    ///
    /// - Returns: the phase that ended, or `nil` if nothing did.
    @discardableResult
    public mutating func advance(to now: Date) -> Phase? {
        guard case .running(let phase, let endsAt) = state, now >= endsAt else {
            return nil
        }

        if phase == .work {
            completedInCycle += 1
        }

        // The next phase is queued but **not started**. A break that begins
        // by itself while you are still typing is a break you do not take,
        // and a work session that begins by itself is worse.
        state = .paused(
            phase: next(after: phase),
            remaining: configuration.duration(
                of: next(after: phase)
            ))

        return phase
    }

    /// What comes after a phase. Long break every `sessionsBeforeLongBreak`
    /// work sessions; work after any break.
    public func next(after phase: Phase) -> Phase {
        guard phase == .work else { return .work }

        let threshold = max(1, configuration.sessionsBeforeLongBreak)
        return completedInCycle % threshold == 0 ? .longBreak : .shortBreak
    }
}
