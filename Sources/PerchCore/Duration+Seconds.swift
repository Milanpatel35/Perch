import Foundation

extension Duration {

    /// Seconds as a `Double`, for the many APIs that predate `Duration`.
    ///
    /// `Duration` is the right currency inside Perch — it is exact, it is
    /// `Sendable`, and it makes a unit mistake impossible. The edges of the
    /// system still speak `TimeInterval`, so the conversion lives here, once,
    /// rather than as a scattering of `/ 1_000_000_000`.
    public var seconds: Double {
        Double(components.seconds) + (Double(components.attoseconds) / 1e18)
    }

    /// Builds a duration from a possibly-absent, possibly-nonsense number of
    /// seconds.
    ///
    /// System frameworks report a track's length as `0`, as a negative, or as
    /// `NaN` often enough that every caller would otherwise need the same
    /// three guards.
    public static func seconds(validating value: Double?) -> Duration? {
        guard let value, value.isFinite, value > 0 else { return nil }
        return .seconds(value)
    }
}
