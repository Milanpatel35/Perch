import AppKit
import Combine
import Defaults
import Foundation
import IOKit
import IOKit.ps
import PerchCore

/// Module 6 — the HUD replacement.
///
/// Alcove's whole personality, and the module with the most moving parts:
/// six watchers, every one event-driven, feeding one pure policy that decides
/// what actually reaches the island.
///
/// The shape is deliberate and worth keeping. Each watcher knows how to read
/// one thing from macOS and nothing else. `HUDPolicy` holds every rule about
/// what is worth showing, and is pure. This type owns lifetimes and nothing
/// more — which is why the interesting tests are `HUDPolicyTests` rather than
/// anything that needs a running Mac.
///
/// Two of the eight rows in `docs/FEATURES.md` §6 are **not** here, and are
/// recorded there rather than faked: keyboard backlight, whose level can be
/// read but whose changes nothing publishes, and AirDrop, which has no
/// interface at all.
@MainActor
final class HUDService: ObservableObject, PerchModule {

    static let moduleID: ModuleID = .hud

    /// Which HUDs are on, and every rule about what reaches the island.
    @Published private(set) var policy = HUDPolicy()

    /// Whether the stock overlay is currently suspended. Preferences shows
    /// this, because it is the one thing this module does to the rest of the
    /// system and it should not be invisible.
    @Published private(set) var isSuppressingStockHUD = false

    private(set) var isActive = false

    private let island: IslandController

    private let volume = VolumeWatcher()
    private let brightness = BrightnessBridge()
    private let focus = FocusWatcher()
    private let capture = CaptureWatcher()
    private let stockHUD = StockHUD()

    private var power: PowerSnapshot = .absent
    private var alerts = BatteryAlerts()
    private var powerSource: CFRunLoopSource?
    private var notificationPort: IONotificationPortRef?
    private var connectedIterator: io_iterator_t = 0
    private var disconnectedIterator: io_iterator_t = 0

    init(island: IslandController) {
        self.island = island
    }

    /// Whether the brightness HUD can work on this Mac at all. False means
    /// `DisplayServices` did not load, and Preferences says so rather than
    /// offering a switch that does nothing.
    var isBrightnessAvailable: Bool { brightness.isAvailable }

    // MARK: - PerchModule

    func activate() {
        guard !isActive else { return }
        isActive = true

        policy = HUDPolicy(enabled: Defaults[.enabledHUDs])

        volume.start { [weak self] reading in self?.show(reading) }
        brightness.start { [weak self] display in self?.brightnessChanged(on: display) }
        focus.start { [weak self] reading in self?.show(reading) }
        capture.start { [weak self] reading in self?.show(reading) }
        observePower()

        // Seed everything before suppressing, so the first key press shows a
        // change rather than the state you were already in.
        seed()

        if Defaults[.hudSuppressesStockHUD] {
            stockHUD.suppress()
            isSuppressingStockHUD = true
        }
    }

    func deactivate() {
        guard isActive else { return }
        isActive = false

        volume.stop()
        brightness.stop()
        focus.stop()
        capture.stop()
        stopObservingPower()

        // The stock HUD comes back immediately, and comes back whether or not
        // this module was the thing that suspended it (TC-HUD-003).
        stockHUD.restore()
        isSuppressingStockHUD = false

        policy.reset()
        island.withdraw(HUDActivity.identifier)
    }

    // MARK: - Presenting

    /// The one path to the island, and the only place the policy is asked.
    private func show(_ reading: HUDReading) {
        guard isActive, policy.admit(reading) else { return }

        // Showing a HUD is the one moment we know something asked macOS for
        // an overlay, which is the only usable signal that `OSDUIHelper` may
        // just have started. See `StockHUD.reassert`.
        stockHUD.reassert()

        island.submit(HUDActivity(reading: reading))
    }

    /// Records the current state without showing any of it.
    ///
    /// Switching the module on must not fire six HUDs at once. Each reading
    /// goes through `admit` so it becomes the baseline, and the activity is
    /// withdrawn afterwards rather than each watcher being special-cased.
    private func seed() {
        if let reading = volume.reading() { _ = policy.admit(reading) }
        if let level = brightness.mainDisplayBrightness {
            _ = policy.admit(Self.brightnessReading(level))
        }
        _ = policy.admit(focus.reading())
        if let reading = capture.reading() { _ = policy.admit(reading) }

        power = PowerSourceReader.read()
        _ = alerts.ingest(power)

        island.withdraw(HUDActivity.identifier)
    }

    // MARK: - Brightness

    private func brightnessChanged(on display: CGDirectDisplayID) {
        // Only the display the island is on. A brightness change on a second
        // monitor drawing a HUD on the laptop is noise.
        guard display == CGMainDisplayID() else { return }
        guard let level = brightness.brightness(of: display) else { return }

        show(Self.brightnessReading(level))
    }

    private static func brightnessReading(_ level: Double) -> HUDReading {
        HUDReading(kind: .brightness, level: level, title: "Brightness")
    }

    // MARK: - Power and Bluetooth

    /// The same two IOKit sources module 7 uses, and for the same reason:
    /// both are genuine push notifications, so neither module needs a timer.
    ///
    /// The charging HUD also shares module 7's rule about keying on the power
    /// *source* rather than on `isCharging` — see `BatteryAlerts`. TC-HUD-005
    /// is TC-BAT-001 wearing a different hat, and it is answered by the same
    /// pure type rather than by a second copy of the logic.
    private func observePower() {
        let context = Unmanaged.passUnretained(self).toOpaque()

        if let source = IOPSNotificationCreateRunLoopSource(
            { context in
                guard let context else { return }
                let service = Unmanaged<HUDService>.fromOpaque(context).takeUnretainedValue()
                MainActor.assumeIsolated { service.powerChanged() }
            },
            context
        )?.takeRetainedValue() {
            powerSource = source
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        }

        guard let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        notificationPort = port
        IONotificationPortSetDispatchQueue(port, .main)

        // Two registrations, two callbacks. The C callback is handed only the
        // iterator, so the direction cannot be recovered afterwards — it has
        // to be baked into which function pointer was registered.
        addAccessoryNotification(
            kIOFirstMatchNotification,
            to: port,
            callback: Self.connected,
            into: &connectedIterator
        )
        addAccessoryNotification(
            kIOTerminatedNotification,
            to: port,
            callback: Self.disconnected,
            into: &disconnectedIterator
        )
    }

    private func stopObservingPower() {
        if let powerSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), powerSource, .defaultMode)
        }
        powerSource = nil

        for iterator in [connectedIterator, disconnectedIterator] where iterator != 0 {
            IOObjectRelease(iterator)
        }
        connectedIterator = 0
        disconnectedIterator = 0

        if let notificationPort {
            IONotificationPortDestroy(notificationPort)
        }
        notificationPort = nil

        alerts.reset()
        power = .absent
    }

    private func powerChanged() {
        guard isActive else { return }

        let snapshot = PowerSourceReader.read()
        power = snapshot

        for alert in alerts.ingest(snapshot) {
            guard let reading = Self.powerReading(alert) else { continue }
            show(reading)
        }
    }

    private static func powerReading(_ alert: BatteryAlerts.Alert) -> HUDReading? {
        switch alert {
        case .pluggedIn(let level):
            HUDReading(kind: .power, title: "Charging", detail: "\(level)%")
        case .unplugged(let level):
            HUDReading(kind: .power, title: "On battery", detail: "\(level)%")
        case .charged:
            HUDReading(kind: .power, title: "Fully charged")
        // The low-battery warning belongs to module 7, which can raise it to
        // `systemAlert`. A HUD is ambient by definition and would quietly
        // downgrade it into something you might miss.
        case .low:
            nil
        }
    }

    private static let connected: IOServiceMatchingCallback = { context, iterator in
        let names = accessoryNames(draining: iterator)
        guard let context else { return }
        let service = Unmanaged<HUDService>.fromOpaque(context).takeUnretainedValue()
        MainActor.assumeIsolated { service.accessories(names, connected: true) }
    }

    private static let disconnected: IOServiceMatchingCallback = { context, iterator in
        let names = accessoryNames(draining: iterator)
        guard let context else { return }
        let service = Unmanaged<HUDService>.fromOpaque(context).takeUnretainedValue()
        MainActor.assumeIsolated { service.accessories(names, connected: false) }
    }

    private func addAccessoryNotification(
        _ type: String,
        to port: IONotificationPortRef,
        callback: IOServiceMatchingCallback,
        into iterator: inout io_iterator_t
    ) {
        guard let matching = IOServiceMatching(AccessoryScanner.serviceClass) else { return }

        let result = IOServiceAddMatchingNotification(
            port,
            type,
            matching,
            callback,
            Unmanaged.passUnretained(self).toOpaque(),
            &iterator
        )
        guard result == KERN_SUCCESS else { return }

        // Arming the notification means draining it once. What comes out here
        // is whatever was already connected, which is not news.
        _ = accessoryNames(draining: iterator)
    }

    private func accessories(_ names: [String], connected: Bool) {
        guard isActive else { return }

        for name in names {
            show(
                HUDReading(
                    kind: .bluetooth,
                    title: connected ? "Connected" : "Disconnected",
                    detail: name
                )
            )
        }
    }

    // MARK: - Settings

    func setEnabled(_ kind: HUDKind, _ isOn: Bool) {
        policy.setEnabled(kind, isOn)
        Defaults[.enabledHUDs] = policy.enabled
    }

    func setSuppressesStockHUD(_ suppresses: Bool) {
        Defaults[.hudSuppressesStockHUD] = suppresses
        guard isActive else { return }

        if suppresses {
            stockHUD.suppress()
        } else {
            stockHUD.restore()
        }
        isSuppressingStockHUD = suppresses
    }

    /// Tells the module that Perch itself is about to change something, so
    /// the notification that follows is not announced back at the person who
    /// asked for it (TC-HUD-007).
    func expectSelfInflictedChange(to kind: HUDKind) {
        policy.suppressNext(kind)
    }
}

/// Empties an IOKit iterator, collecting the product names on the way out.
///
/// Free-floating because it is called from a C callback, which cannot capture
/// `self` and must not touch the actor before `assumeIsolated`.
private func accessoryNames(draining iterator: io_iterator_t) -> [String] {
    var names: [String] = []
    while true {
        let entry = IOIteratorNext(iterator)
        guard entry != 0 else { return names }
        names.append(AccessoryScanner.productName(of: entry) ?? "Device")
        IOObjectRelease(entry)
    }
}
