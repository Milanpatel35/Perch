import AppKit
import Foundation
import PerchCore

/// The bridge to `DisplayServices`, macOS's display brightness service.
///
/// The second private framework in Perch, and the second file to be alone in
/// its folder for the same reason as `MediaRemoteBridge`: it is the piece a
/// future macOS is most likely to break, and it should be readable, auditable
/// and replaceable without touching the module around it.
/// [ADR 0005](../../../docs/adr/0005-private-apis-for-the-hud.md) is the
/// decision.
///
/// **Why private at all.** There is no public API that reports display
/// brightness, and none at all that reports a *change* to it.
/// `IODisplayGetFloatParameter` is the old public answer and returns nothing
/// useful on Apple Silicon.
///
/// **How the risk is contained.** Nothing is linked; every symbol is resolved
/// by `dlsym` at activation and every one is optional. If a future macOS
/// removes them, `isAvailable` goes false, the brightness HUD reports itself
/// unavailable in Preferences, and the other five carry on. Nothing here runs
/// at launch, so nothing here can fail at launch.
///
/// **The callback's arguments are deliberately ignored.** Its real signature
/// is undocumented, and a probe against this machine returned a garbage
/// string and a denormal double where the name and value should have been.
/// What the callback reliably means is "something changed" — so the brightness
/// is read back through the getter, which *is* verified.
@MainActor
final class BrightnessBridge {

    private typealias Get =
        @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32

    /// The observer is passed as an opaque context and handed back to the
    /// callback. `@convention(c)` cannot capture, so this is the only way
    /// through.
    private typealias Register =
        @convention(c) (
            CGDirectDisplayID,
            UnsafeMutableRawPointer?,
            @convention(c) (UnsafeMutableRawPointer?, CGDirectDisplayID, UnsafeRawPointer?, Double)
                ->
                Void
        ) -> Int32

    private typealias Unregister =
        @convention(c) (
            CGDirectDisplayID,
            UnsafeMutableRawPointer?,
            @convention(c) (UnsafeMutableRawPointer?, CGDirectDisplayID, UnsafeRawPointer?, Double)
                ->
                Void
        ) -> Int32

    private static let frameworkPath =
        "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices"

    private var handle: UnsafeMutableRawPointer?
    private var get: Get?
    private var register: Register?
    private var unregister: Unregister?

    private var registered: Set<CGDirectDisplayID> = []
    private var onChange: (@MainActor (CGDirectDisplayID) -> Void)?

    /// Whether the framework loaded and every symbol resolved. False means
    /// the brightness HUD is simply not available on this Mac, which
    /// Preferences says out loud rather than offering a switch that does
    /// nothing.
    private(set) var isAvailable = false

    // MARK: - Lifecycle

    func start(onChange: @escaping @MainActor (CGDirectDisplayID) -> Void) {
        guard handle == nil else { return }
        self.onChange = onChange

        guard let handle = dlopen(Self.frameworkPath, RTLD_LAZY) else { return }
        self.handle = handle

        guard
            let getSymbol = dlsym(handle, "DisplayServicesGetBrightness"),
            let registerSymbol = dlsym(
                handle,
                "DisplayServicesRegisterForBrightnessChangeNotifications"
            ),
            let unregisterSymbol = dlsym(
                handle,
                "DisplayServicesUnregisterForBrightnessChangeNotifications"
            )
        else { return }

        get = unsafeBitCast(getSymbol, to: Get.self)
        register = unsafeBitCast(registerSymbol, to: Register.self)
        unregister = unsafeBitCast(unregisterSymbol, to: Unregister.self)
        isAvailable = true

        observeDisplays()
    }

    func stop() {
        for display in registered {
            _ = unregister?(display, Unmanaged.passUnretained(self).toOpaque(), Self.callback)
        }
        registered.removeAll()

        NotificationCenter.default.removeObserver(
            self,
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        onChange = nil
        get = nil
        register = nil
        unregister = nil
        isAvailable = false

        // Deliberately not `dlclose`d. ADR 0002 records why for MediaRemote
        // and the reasoning is identical: a framework that registered
        // callbacks and is then unloaded leaves those callbacks pointing at
        // unmapped memory, and the crash arrives later and somewhere else.
        handle = nil
    }

    /// Reads a display's brightness. `nil` when the display does not have
    /// one — an external monitor on DisplayPort usually does not.
    func brightness(of display: CGDirectDisplayID) -> Double? {
        guard let get else { return nil }

        var value: Float = 0
        guard get(display, &value) == 0, value.isFinite, value >= 0 else { return nil }
        return Double(value)
    }

    var mainDisplayBrightness: Double? {
        brightness(of: CGMainDisplayID())
    }

    // MARK: - Registration

    /// Registers for every display, and re-registers when the arrangement
    /// changes. `CLAUDE.md` §5.4 — a display arriving or leaving is where
    /// competing apps break most often, and a HUD that stops working after
    /// you plug a monitor in is exactly that bug.
    private func observeDisplays() {
        registerForCurrentDisplays()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    @objc private func screensChanged() {
        MainActor.assumeIsolated { registerForCurrentDisplays() }
    }

    private func registerForCurrentDisplays() {
        guard let register else { return }

        let context = Unmanaged.passUnretained(self).toOpaque()
        for display in Self.activeDisplays() where !registered.contains(display) {
            guard register(display, context, Self.callback) == 0 else { continue }
            registered.insert(display)
        }
    }

    private static func activeDisplays() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else {
            return [CGMainDisplayID()]
        }

        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &displays, &count) == .success else {
            return [CGMainDisplayID()]
        }
        return Array(displays.prefix(Int(count)))
    }

    /// Fires on the main thread whenever a display's brightness moves. The
    /// name and value arguments are undocumented and were observed to be
    /// garbage, so they are ignored and the level is read back instead.
    private static let callback:
        @convention(c) (UnsafeMutableRawPointer?, CGDirectDisplayID, UnsafeRawPointer?, Double) ->
            Void = { context, display, _, _ in
                guard let context else { return }
                let bridge = Unmanaged<BrightnessBridge>.fromOpaque(context)
                    .takeUnretainedValue()

                MainActor.assumeIsolated { bridge.onChange?(display) }
            }
}
