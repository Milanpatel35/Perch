import Foundation
import IOKit.ps
import PerchCore

/// Reads the Mac's own battery out of IOKit.
///
/// The side-effecting half of module 7. Everything that *decides* anything
/// works on the `PowerSnapshot` this produces — see `BatteryAlerts` — which
/// is what lets the rules be tested on a CI runner with no battery in it.
enum PowerSourceReader {

    /// One reading. Returns `.absent` on a desktop Mac, which is the whole
    /// of TC-BAT-005 as far as this layer is concerned.
    static func read() -> PowerSnapshot {
        guard
            let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue()
                as? [CFTypeRef]
        else { return .absent }

        for source in sources {
            guard
                let description = IOPSGetPowerSourceDescription(blob, source)?
                    .takeUnretainedValue() as? [String: Any],
                description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType
            else { continue }

            return snapshot(from: description)
        }

        return .absent
    }

    private static func snapshot(from description: [String: Any]) -> PowerSnapshot {
        let current = description[kIOPSCurrentCapacityKey] as? Int ?? 0
        let maximum = description[kIOPSMaxCapacityKey] as? Int ?? 100
        let isCharging = description[kIOPSIsChargingKey] as? Bool ?? false
        let isCharged = description[kIOPSIsChargedKey] as? Bool ?? false

        let source: PowerSnapshot.Source =
            description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            ? .wall : .battery

        return PowerSnapshot(
            isPresent: true,
            percentage: percentage(current: current, maximum: maximum),
            source: source,
            isCharging: isCharging,
            isCharged: isCharged,
            timeRemaining: timeRemaining(
                from: description,
                isCharging: isCharging,
                source: source
            )
        )
    }

    /// IOKit reports capacity against a maximum that is *usually* 100 and
    /// occasionally is not — on some models it is the design capacity in
    /// mAh. Dividing rather than trusting the number covers both.
    private static func percentage(current: Int, maximum: Int) -> Int {
        guard maximum > 0 else { return 0 }
        let ratio = Double(current) / Double(maximum)
        return min(100, max(0, Int((ratio * 100).rounded())))
    }

    /// Minutes, and `-1` for "still working it out" — which it is for a
    /// minute or two after every single change, so the optional is the
    /// common case rather than the edge one.
    private static func timeRemaining(
        from description: [String: Any],
        isCharging: Bool,
        source: PowerSnapshot.Source
    ) -> Duration? {
        let key =
            isCharging || source == .wall
            ? kIOPSTimeToFullChargeKey
            : kIOPSTimeToEmptyKey

        guard let minutes = description[key] as? Int, minutes > 0 else { return nil }
        return .seconds(minutes * 60)
    }
}
