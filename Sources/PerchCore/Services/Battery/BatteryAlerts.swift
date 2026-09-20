import Foundation

/// Decides when the battery is worth interrupting someone for.
///
/// The whole module reduces to this: a stream of `PowerSnapshot`s in, a much
/// smaller stream of alerts out. The rules are all about *not* firing —
/// every competitor that gets this wrong gets it wrong by repeating itself,
/// and a notch that announces the same thing four times is worse than one
/// that says nothing.
///
/// Pure and synchronous, so `docs/TEST-PLAN.md` § BAT runs without a battery,
/// a clock, or a Mac that has either.
public struct BatteryAlerts: Equatable, Sendable {

    public enum Alert: Equatable, Sendable {
        /// The charger went in. Carries the level at that moment.
        case pluggedIn(Int)

        /// The charger came out.
        case unplugged(Int)

        /// On battery, at or below the threshold, once per discharge cycle.
        case low(Int)

        /// Full, and still on the wall.
        case charged
    }

    /// Where `low` fires. 20% matches what macOS itself warns at.
    public var lowThreshold: Int

    /// The last snapshot seen, for transition detection.
    private var previous: PowerSnapshot?

    /// Rearmed by plugging in, not by the level recovering. A battery that
    /// wobbles across the threshold on its own — and they all do, under load
    /// — would otherwise warn repeatedly (TC-BAT-002).
    private var hasWarnedThisCycle = false

    /// Rearmed when the battery stops being full.
    private var hasAnnouncedCharged = false

    public init(lowThreshold: Int = 20) {
        self.lowThreshold = lowThreshold
    }

    /// Feeds one reading in and gets back everything worth saying about it.
    ///
    /// Usually that is nothing. `IOPSNotificationCreateRunLoopSource` fires
    /// on every percentage point and on every change of charging state, so
    /// this runs tens of times an hour and returns an empty array for nearly
    /// all of them.
    public mutating func ingest(_ snapshot: PowerSnapshot) -> [Alert] {
        defer { previous = snapshot }

        guard snapshot.isPresent else { return [] }

        // The first reading establishes where we are; it never announces.
        // Switching the module on should not tell you that you are plugged
        // in — you can see the cable. The low-water mark is seeded from it
        // so that enabling the module at 12% does not then warn at 11%.
        guard let previous, previous.isPresent else {
            hasWarnedThisCycle = snapshot.percentage <= lowThreshold
            hasAnnouncedCharged = snapshot.isCharged
            return []
        }

        var alerts: [Alert] = []
        alerts.append(contentsOf: sourceChange(from: previous, to: snapshot))
        alerts.append(contentsOf: lowWarning(for: snapshot))
        alerts.append(contentsOf: chargedAnnouncement(for: snapshot))
        return alerts
    }

    /// Resets everything. Called when the module is switched off, so that
    /// switching it back on starts from a clean baseline rather than
    /// announcing a transition that happened while it was not looking.
    public mutating func reset() {
        previous = nil
        hasWarnedThisCycle = false
        hasAnnouncedCharged = false
    }

    // MARK: - The three rules

    /// Keyed on `source`, never on `isCharging`.
    ///
    /// This is the fluctuation guard. A charger that is attached but not
    /// currently taking charge — a full battery, or macOS holding at 80% for
    /// battery health — flips `isCharging` on and off by itself. The source
    /// does not flip, so the alert does not repeat (TC-BAT-001, TC-HUD-005).
    private mutating func sourceChange(
        from previous: PowerSnapshot,
        to snapshot: PowerSnapshot
    ) -> [Alert] {
        guard previous.source != snapshot.source else { return [] }

        switch snapshot.source {
        case .wall:
            // A new cycle begins at the wall: the next discharge gets its own
            // warning.
            hasWarnedThisCycle = false
            return [.pluggedIn(snapshot.percentage)]
        case .battery:
            hasAnnouncedCharged = false
            return [.unplugged(snapshot.percentage)]
        }
    }

    private mutating func lowWarning(for snapshot: PowerSnapshot) -> [Alert] {
        guard snapshot.source == .battery else { return [] }
        guard snapshot.percentage <= lowThreshold else { return [] }
        guard !hasWarnedThisCycle else { return [] }

        hasWarnedThisCycle = true
        return [.low(snapshot.percentage)]
    }

    private mutating func chargedAnnouncement(for snapshot: PowerSnapshot) -> [Alert] {
        guard snapshot.isCharged else {
            hasAnnouncedCharged = false
            return []
        }
        guard !hasAnnouncedCharged else { return [] }

        hasAnnouncedCharged = true
        return [.charged]
    }
}
