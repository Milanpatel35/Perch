import Foundation

/// How often to sample, and — much more importantly — when not to at all.
///
/// **This is the rule `CLAUDE.md` §4 singles the module out for.** A system
/// monitor is the easiest way in the whole app to violate §5.1: it is the
/// one module whose natural implementation is a repeating timer. The rule
/// that stops it is that the sampler's lifetime belongs to the *view*, not
/// to the module — collapsed with no gauge showing means **no timer exists**.
/// Not a slower timer. None (TC-SYS-009).
///
/// Making that a value rather than an `if` inside a service is the point:
/// it is a unit test, and it stays true when somebody adds a fourth state.
public enum SamplerPolicy {

    /// What the module is being asked to draw right now.
    public enum Demand: Equatable, Sendable {
        /// Nothing on screen: island idle, or showing another module.
        case none

        /// The two-glyph micro-gauge beside the notch
        /// (`docs/FEATURES.md` §10).
        case microGauge

        /// The full grid of sparklines.
        case expanded
    }

    /// The interval to sample at, or `nil` for "do not sample".
    ///
    /// `nil` is the answer the whole module is built around. A caller that
    /// treats it as "use a default" has broken TC-SYS-009, which is why this
    /// returns an optional rather than a number a mistake could pass through.
    public static func interval(for demand: Demand) -> Duration? {
        switch demand {
        case .none: nil
        case .microGauge: .seconds(5)
        case .expanded: .seconds(2)
        }
    }

    /// Whether a sampler should exist at all.
    public static func samples(_ demand: Demand) -> Bool {
        interval(for: demand) != nil
    }
}

/// A fixed-length history, for the sparklines.
///
/// Sixty points at the expanded interval is two minutes of history and 480
/// bytes. It is a ring rather than an array that is appended to and trimmed,
/// because the trimming version is the one that shows up in a profile after
/// an hour (TC-SYS-015).
public struct StatHistory: Equatable, Sendable {

    public private(set) var values: [Double] = []

    public let capacity: Int

    public init(capacity: Int = 60) {
        self.capacity = max(1, capacity)
        values.reserveCapacity(self.capacity)
    }

    public mutating func record(_ value: Double) {
        values.append(value)
        if values.count > capacity {
            values.removeFirst(values.count - capacity)
        }
    }

    public mutating func clear() {
        values.removeAll(keepingCapacity: true)
    }

    public var latest: Double? { values.last }

    /// The ceiling a sparkline is drawn against.
    ///
    /// Never zero: a flat line at zero must draw as a flat line at the
    /// bottom, not as a blank box (TC-SYS-014). For a fraction the ceiling
    /// is 1; for a rate it is the tallest point so far, so a network graph
    /// scales to what actually happened rather than to a guess.
    public func ceiling(minimum: Double = 1) -> Double {
        max(values.max() ?? minimum, minimum)
    }

    public var isEmpty: Bool { values.isEmpty }
}
