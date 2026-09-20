import Foundation

/// The Mac's own battery, as one value.
///
/// Built from `IOPSCopyPowerSourcesInfo` by `PowerSourceReader` in the module
/// layer. Everything that decides *what to say about it* works on this type
/// instead, which is why the alert rules can be tested without a battery —
/// and the machines CI runs on do not have one.
public struct PowerSnapshot: Equatable, Sendable {

    /// Where the Mac is drawing power from.
    ///
    /// Deliberately not "is charging". A charger that is attached but not
    /// charging — because the battery is full, or because macOS is holding
    /// at 80% for battery health — is still on the wall, and the island
    /// should not announce a power change every time that flickers
    /// (TC-BAT-001, TC-HUD-005).
    public enum Source: String, Equatable, Sendable, CaseIterable {
        case battery
        case wall
    }

    /// False on a Mac mini, a Studio or an iMac.
    ///
    /// A desktop Mac hides the battery row entirely rather than drawing it at
    /// 0%, and its accessories are still listed (TC-BAT-005).
    public let isPresent: Bool

    /// 0–100. Meaningless when `isPresent` is false.
    public let percentage: Int

    public let source: Source

    /// Actively taking charge. False on a full battery that is still plugged
    /// in, and false while macOS holds the charge for battery health.
    public let isCharging: Bool

    /// Full, and on the wall.
    public let isCharged: Bool

    /// Time to empty on battery, time to full while charging.
    ///
    /// `nil` while macOS is still working it out, which it is for the first
    /// minute or two after any change — and which is why the UI has to have
    /// something to say other than a number.
    public let timeRemaining: Duration?

    public init(
        isPresent: Bool,
        percentage: Int,
        source: Source,
        isCharging: Bool,
        isCharged: Bool,
        timeRemaining: Duration?
    ) {
        self.isPresent = isPresent
        self.percentage = percentage
        self.source = source
        self.isCharging = isCharging
        self.isCharged = isCharged
        self.timeRemaining = timeRemaining
    }

    /// What a desktop Mac reports.
    public static let absent = Self(
        isPresent: false,
        percentage: 0,
        source: .wall,
        isCharging: false,
        isCharged: false,
        timeRemaining: nil
    )

    public var isPluggedIn: Bool { source == .wall }
}
