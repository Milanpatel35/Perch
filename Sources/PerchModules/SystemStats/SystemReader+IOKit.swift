import Darwin
import Foundation
import IOKit
import PerchCore

/// The IO registry half of the reader: GPU, thermals and battery health.
///
/// Kept apart from the Mach half because it is the part that is allowed to
/// answer "I don't know". Everything here is a registry read — public, no
/// entitlement, no private framework — and everything here returns `nil`
/// rather than zero when the hardware does not publish it (TC-SYS-005,
/// TC-SYS-006).
extension SystemReader {

    // MARK: - GPU

    /// GPU load, from the accelerator's own `PerformanceStatistics`.
    ///
    /// **Apple Silicon only, and no Apple-Silicon-only API is called
    /// anywhere else** (TC-SYS-006). On Intel the service does not exist,
    /// the match returns nothing, and this returns `nil` — the row is hidden
    /// rather than drawn as zero.
    ///
    /// `IOReport` would give more, and it is private. `docs/COMPARISON.md`
    /// records that no competitor has a system monitor at all; being the
    /// only one and being honest about what it can read beats being the only
    /// one that breaks on the next macOS.
    func gpu() -> SystemSnapshot.GPU? {
        guard let entry = accelerator() else { return nil }
        defer { IOObjectRelease(entry) }

        guard
            let statistics = registryValue(
                entry,
                key: "PerformanceStatistics"
            ) as? [String: Any]
        else { return nil }

        var gpu = SystemSnapshot.GPU()

        // The key has been spelled both ways across releases and across
        // GPU families, so both are tried rather than one being picked.
        let utilisation =
            statistics["Device Utilization %"] as? Int
            ?? statistics["GPU Activity(%)"] as? Int
        if let utilisation {
            gpu.utilisation = min(1, Double(utilisation) / 100)
        }

        if let used = statistics["In use system memory"] as? Int, used >= 0 {
            gpu.vramUsed = UInt64(used)
        }
        if let allocated = statistics["Alloc system memory"] as? Int, allocated > 0 {
            gpu.vramTotal = UInt64(allocated)
        }

        return gpu.isEmpty ? nil : gpu
    }

    private func accelerator() -> io_registry_entry_t? {
        let matching = IOServiceMatching("IOAccelerator")
        var iterator: io_iterator_t = 0

        guard
            IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS
        else { return nil }
        defer { IOObjectRelease(iterator) }

        let entry = IOIteratorNext(iterator)
        return entry != 0 ? entry : nil
    }

    // MARK: - Thermals

    /// Fan speeds, from the SMC's registry node.
    ///
    /// **Temperature is deliberately not read here.** The only way to a CPU
    /// die temperature on Apple Silicon is `IOHIDEventSystemClient`, which
    /// is private, and `docs/FEATURES.md` §10 promises the rows degrade
    /// gracefully rather than that they always exist. A missing temperature
    /// reads as no row — never as 0°C, which would make the "over 95°C"
    /// alert say everything is fine for ever (TC-SYS-005).
    func thermal() -> SystemSnapshot.Thermal? {
        var thermal = SystemSnapshot.Thermal()
        thermal.fanRPM = fanSpeeds()
        return thermal.isEmpty ? nil : thermal
    }

    private func fanSpeeds() -> [Int] {
        let matching = IOServiceMatching("AppleSMCFanControl")
        var iterator: io_iterator_t = 0

        guard
            IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS
        else { return [] }
        defer { IOObjectRelease(iterator) }

        var speeds: [Int] = []
        var entry = IOIteratorNext(iterator)

        while entry != 0 {
            defer {
                IOObjectRelease(entry)
                entry = IOIteratorNext(iterator)
            }

            if let speed = registryValue(entry, key: "Actual Speed") as? Int, speed > 0 {
                speeds.append(speed)
            }
        }

        return speeds
    }

    // MARK: - Battery health

    /// Cycle count and health, which complement module 7 rather than
    /// duplicate it: that one owns charge and time remaining, this one owns
    /// the numbers a *monitor* wants.
    ///
    /// `nil` on a desktop Mac, where the service does not exist.
    func batteryHealth() -> SystemSnapshot.BatteryHealth? {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("AppleSmartBattery")
        )
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        guard let cycles = registryValue(service, key: "CycleCount") as? Int else { return nil }

        // `NominalChargeCapacity` against `DesignCapacity` is the ratio
        // System Settings shows as "Maximum Capacity".
        let nominal = registryValue(service, key: "NominalChargeCapacity") as? Int
        let design = registryValue(service, key: "DesignCapacity") as? Int

        let health: Double
        if let nominal, let design, design > 0 {
            health = min(1, Double(nominal) / Double(design))
        } else {
            health = 1
        }

        return SystemSnapshot.BatteryHealth(cycleCount: cycles, maximumCapacity: health)
    }

    // MARK: - Plumbing

    /// One property out of a registry entry. Public API, and `nil` for
    /// anything that is not there — which on this path is normal rather than
    /// exceptional.
    func registryValue(_ entry: io_registry_entry_t, key: String) -> Any? {
        IORegistryEntryCreateCFProperty(
            entry,
            key as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue()
    }
}
