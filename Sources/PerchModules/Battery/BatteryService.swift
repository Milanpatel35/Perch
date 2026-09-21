import Combine
import Defaults
import Foundation
import IOKit
import IOKit.ps
import PerchCore

/// Module 7 — battery and accessories.
///
/// Entirely event-driven, and it has to be: a battery read-out is the easiest
/// module in the app to turn into a polling loop, and a polling loop in a
/// menu-bar app is the thing `CLAUDE.md` §5.1 exists to prevent.
///
/// Two sources, both push:
///
/// - The Mac's own battery, through `IOPSNotificationCreateRunLoopSource`.
///   macOS calls us on every percentage point and on every change of power
///   source. There is no timer.
/// - Accessories, through `IOServiceAddMatchingNotification` on the registry
///   class the levels live under. That fires on connect and on disconnect.
///
/// What is *not* pushed is an accessory's level changing while it stays
/// connected — nothing publishes that, and the honest answer is to re-read
/// when something is about to be looked at rather than to sample on a timer.
/// `refreshAccessories()` is called when the island is about to show them.
@MainActor
final class BatteryService: ObservableObject, PerchModule {

    static let moduleID: ModuleID = .battery

    @Published private(set) var power: PowerSnapshot = .absent
    @Published private(set) var roster = AccessoryRoster()

    private(set) var isActive = false

    private let island: IslandController

    /// Every rule about when to say something. Pure, and tested without a
    /// battery — see `BatteryAlertsTests`.
    private var alerts = BatteryAlerts()

    private var powerSource: CFRunLoopSource?
    private var notificationPort: IONotificationPortRef?
    private var connectedIterator: io_iterator_t = 0
    private var disconnectedIterator: io_iterator_t = 0

    init(island: IslandController) {
        self.island = island
    }

    // MARK: - PerchModule

    func activate() {
        guard !isActive else { return }
        isActive = true

        alerts.lowThreshold = Defaults[.batteryLowThreshold]

        // Seed both before subscribing, so the first notification is a
        // change rather than a baseline. `BatteryAlerts` ignores its first
        // reading for the same reason — switching the module on should not
        // announce the state you are already in.
        power = PowerSourceReader.read()
        _ = alerts.ingest(power)
        refreshAccessories()

        observePowerSource()
        observeAccessories()
    }

    func deactivate() {
        guard isActive else { return }
        isActive = false

        if let powerSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), powerSource, .defaultMode)
        }
        powerSource = nil

        release(&connectedIterator)
        release(&disconnectedIterator)

        if let notificationPort {
            IONotificationPortDestroy(notificationPort)
        }
        notificationPort = nil

        // Nothing is remembered across a switch-off. Coming back on starts
        // from a fresh baseline instead of replaying a transition nobody was
        // watching for.
        alerts.reset()
        power = .absent
        roster = AccessoryRoster()

        island.withdraw(BatteryActivity.identifier)
        island.withdraw(BatteryStatusActivity.identifier)
    }

    // MARK: - The Mac's own battery

    private func observePowerSource() {
        let context = Unmanaged.passUnretained(self).toOpaque()

        guard
            let source = IOPSNotificationCreateRunLoopSource(
                { context in
                    guard let context else { return }
                    let service = Unmanaged<BatteryService>
                        .fromOpaque(context)
                        .takeUnretainedValue()

                    MainActor.assumeIsolated { service.powerChanged() }
                },
                context
            )?.takeRetainedValue()
        else { return }

        powerSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
    }

    private func powerChanged() {
        guard isActive else { return }

        let snapshot = PowerSourceReader.read()
        power = snapshot

        for alert in alerts.ingest(snapshot) {
            announce(alert, at: snapshot)
        }
    }

    private func announce(_ alert: BatteryAlerts.Alert, at snapshot: PowerSnapshot) {
        let reason: BatteryActivity.Reason =
            switch alert {
            case .pluggedIn(let level): .pluggedIn(level)
            case .unplugged(let level): .unplugged(level)
            case .low(let level): .low(level)
            case .charged: .charged
            }

        guard isEnabled(reason) else { return }

        island.submit(
            BatteryActivity(
                reason: reason,
                power: snapshot,
                accessories: roster.accessories
            )
        )
    }

    /// Each announcement is individually switchable, the way every HUD is.
    /// Somebody who wants the low warning and nothing else should not have
    /// to switch the whole module off to get it.
    private func isEnabled(_ reason: BatteryActivity.Reason) -> Bool {
        switch reason {
        case .low: Defaults[.batteryAnnounceLow]
        case .pluggedIn, .unplugged: Defaults[.batteryAnnouncePowerChanges]
        case .charged: Defaults[.batteryAnnounceCharged]
        }
    }

    // MARK: - Accessories

    private func observeAccessories() {
        guard let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        notificationPort = port
        IONotificationPortSetDispatchQueue(port, .main)

        let context = Unmanaged.passUnretained(self).toOpaque()

        // `IOServiceAddMatchingNotification` consumes a reference to the
        // matching dictionary, so the two registrations need one each.
        add(kIOFirstMatchNotification, to: port, context: context, into: &connectedIterator)
        add(kIOTerminatedNotification, to: port, context: context, into: &disconnectedIterator)
    }

    private func add(
        _ type: String,
        to port: IONotificationPortRef,
        context: UnsafeMutableRawPointer,
        into iterator: inout io_iterator_t
    ) {
        guard let matching = IOServiceMatching(AccessoryScanner.serviceClass) else { return }

        let result = IOServiceAddMatchingNotification(
            port,
            type,
            matching,
            { context, iterator in
                guard let context else { return }
                // The iterator must be drained or the notification never
                // fires again — this is the one piece of IOKit etiquette
                // that has no diagnostic when you get it wrong.
                drain(iterator)

                let service = Unmanaged<BatteryService>
                    .fromOpaque(context)
                    .takeUnretainedValue()
                MainActor.assumeIsolated { service.refreshAccessories() }
            },
            context,
            &iterator
        )

        // Registering arms nothing until the iterator is drained once.
        guard result == KERN_SUCCESS else { return }
        drain(iterator)
    }

    /// Re-reads every connected accessory.
    ///
    /// Called on connect, on disconnect, and when something is about to put
    /// the levels on screen. Never on a timer (`CLAUDE.md` §5.1).
    func refreshAccessories() {
        guard isActive else { return }
        roster.replace(with: AccessoryScanner.scan())
    }

    // MARK: - The readable state

    /// Opens the full list on the island. Called from the home surface's
    /// battery tile and from Preferences.
    func showStatus() {
        guard isActive else { return }

        refreshAccessories()
        island.submit(
            BatteryStatusActivity(power: power, accessories: roster.accessories)
        )
    }

    func setLowThreshold(_ percentage: Int) {
        Defaults[.batteryLowThreshold] = percentage
        alerts.lowThreshold = percentage
    }

    // MARK: - Teardown helpers

    private func release(_ iterator: inout io_iterator_t) {
        guard iterator != 0 else { return }
        IOObjectRelease(iterator)
        iterator = 0
    }
}

/// Empties an IOKit iterator.
///
/// Free-floating rather than a method because it is called from a C callback,
/// which cannot capture `self` and must not touch the actor before
/// `assumeIsolated`.
private func drain(_ iterator: io_iterator_t) {
    while true {
        let entry = IOIteratorNext(iterator)
        guard entry != 0 else { return }
        IOObjectRelease(entry)
    }
}
