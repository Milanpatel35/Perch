import Foundation
import IOKit
import PerchCore

/// Reads charge levels out of the IO registry.
///
/// There is no public API for "what is my mouse's battery level". The levels
/// every Mac app shows — Apple's own menu bar included — come from the IO
/// registry, where each connected accessory publishes an
/// `AppleDeviceManagementHIDEventService` entry carrying `BatteryPercent` and,
/// for AirPods, one key per bud plus the case.
///
/// The framework is public IOKit and needs no entitlement and no permission.
/// What is undocumented is the class name and the key spellings, so a macOS
/// release could rename them — see
/// [ADR 0004](../../../docs/adr/0004-ioregistry-for-accessory-levels.md).
/// When that happens the scan returns nothing and the accessory list is
/// empty, which is the correct failure: no crash, no stale numbers, and the
/// Mac's own battery — which *is* public API — keeps working.
enum AccessoryScanner {

    /// The registry class every Bluetooth accessory that reports a level
    /// appears as: AirPods, Beats, Magic Mouse, Magic Keyboard, Magic
    /// Trackpad, and most third-party BLE HID devices.
    static let serviceClass = "AppleDeviceManagementHIDEventService"

    /// One scan. Cheap — a registry walk over a handful of entries — but not
    /// free, which is why nothing calls it on a timer. It runs when a device
    /// connects or disconnects, and when something is about to be shown.
    static func scan() -> [AccessoryBattery] {
        guard let matching = IOServiceMatching(serviceClass) else { return [] }

        var iterator: io_iterator_t = 0
        guard
            IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
                == KERN_SUCCESS
        else { return [] }
        defer { IOObjectRelease(iterator) }

        var found: [AccessoryBattery] = []
        while true {
            let entry = IOIteratorNext(iterator)
            guard entry != 0 else { break }
            defer { IOObjectRelease(entry) }

            if let accessory = accessory(from: entry) {
                found.append(accessory)
            }
        }
        return found
    }

    /// Builds one accessory, or nothing at all.
    ///
    /// A device that reports no level is skipped rather than listed at zero.
    /// Plenty of things publish this service without a battery in them, and a
    /// list of dongles claiming to be flat helps nobody.
    private static func accessory(from entry: io_registry_entry_t) -> AccessoryBattery? {
        let properties = properties(of: entry)

        let levels = AccessoryBattery.Levels(
            single: level(properties["BatteryPercent"]),
            left: level(properties["BatteryPercentLeft"]),
            right: level(properties["BatteryPercentRight"]),
            caseLevel: level(properties["BatteryPercentCase"])
        )
        guard !levels.isEmpty else { return nil }

        let name = properties["Product"] as? String ?? "Accessory"

        return AccessoryBattery(
            id: identifier(for: entry, properties: properties),
            name: name,
            kind: .classify(productName: name),
            levels: levels
        )
    }

    /// The Bluetooth address, which survives a reconnection — that is what
    /// stops a device that goes out of range and comes back appearing twice
    /// (TC-BAT-004). The registry entry ID is the fallback, and is stable
    /// only for as long as the device stays put.
    private static func identifier(
        for entry: io_registry_entry_t,
        properties: [String: Any]
    ) -> String {
        if let address = properties["DeviceAddress"] as? String, !address.isEmpty {
            return address
        }

        var entryID: UInt64 = 0
        guard IORegistryEntryGetRegistryEntryID(entry, &entryID) == KERN_SUCCESS else {
            return UUID().uuidString
        }
        return "ioreg:\(entryID)"
    }

    /// The registry hands back an `NSNumber`; what counts as a level at all
    /// is `AccessoryBattery.Levels.reported`, in Core, where it is tested.
    private static func level(_ value: Any?) -> Int? {
        AccessoryBattery.Levels.reported((value as? NSNumber)?.intValue)
    }

    private static func properties(of entry: io_registry_entry_t) -> [String: Any] {
        var unmanaged: Unmanaged<CFMutableDictionary>?
        guard
            IORegistryEntryCreateCFProperties(entry, &unmanaged, kCFAllocatorDefault, 0)
                == KERN_SUCCESS,
            let properties = unmanaged?.takeRetainedValue() as? [String: Any]
        else { return [:] }

        return properties
    }
}
