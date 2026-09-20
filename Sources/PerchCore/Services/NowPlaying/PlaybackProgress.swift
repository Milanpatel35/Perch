import Foundation

/// Where playback is, expressed so that nothing has to tick.
///
/// The naive scrubber runs a timer at 30Hz and advances a number. That timer
/// then keeps running while the island is collapsed, while the track is
/// paused, and while the Mac is asleep — which is exactly how a notch app
/// ends up costing 3% CPU doing nothing (`CLAUDE.md` §5.1).
///
/// Instead this stores the position *as of a moment*, plus the rate it is
/// moving at, and computes the rest. A paused track has `rate == 0`, so its
/// position is a constant and no clock is needed to draw it. A playing track
/// needs a clock only while something is on screen to see it, and that clock
/// belongs to the view.
public struct PlaybackProgress: Equatable, Sendable {

    /// Position at `asOf`.
    public let elapsed: Duration

    /// Playback rate. `1.0` for normal play, `0` for paused, `2.0` for double
    /// speed, negative while scrubbing backwards.
    public let rate: Double

    /// The moment `elapsed` was true.
    public let asOf: Date

    /// Total length, when the source knows it. Live streams do not.
    public let duration: Duration?

    public init(
        elapsed: Duration,
        rate: Double,
        asOf: Date,
        duration: Duration? = nil
    ) {
        self.elapsed = elapsed
        self.rate = rate
        self.asOf = asOf
        self.duration = duration
    }

    /// Whether the position is moving. The visualiser and the scrubber's
    /// clock both hang off this — if it is false, neither may exist
    /// (TC-MED-002).
    public var isAdvancing: Bool { rate != 0 }

    /// Position at an arbitrary moment, clamped to the track.
    public func elapsed(at date: Date) -> Duration {
        guard isAdvancing else { return clamp(elapsed) }

        let drift = date.timeIntervalSince(asOf) * rate
        return clamp(elapsed + .seconds(drift))
    }

    /// Position as a fraction of the whole, or `nil` for a stream with no
    /// known length — which the scrubber draws as an indeterminate bar rather
    /// than as a full one.
    public func fraction(at date: Date) -> Double? {
        guard let duration, duration > .zero else { return nil }
        return elapsed(at: date) / duration
    }

    private func clamp(_ value: Duration) -> Duration {
        guard value > .zero else { return .zero }
        guard let duration else { return value }
        return min(value, duration)
    }
}
