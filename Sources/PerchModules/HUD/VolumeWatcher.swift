import CoreAudio
import Foundation
import PerchCore

/// Watches the output device's volume and mute.
///
/// The one HUD in the module that is entirely public API. CoreAudio has
/// property listeners, so there is no timer and no private symbol here — the
/// system calls us when the level moves.
///
/// Three properties, not one. Volume, mute and *which device is the default*
/// all have to be watched: plugging in headphones changes the device, and a
/// listener attached to the old one would go quiet and never say why.
@MainActor
final class VolumeWatcher {

    private var onChange: (@MainActor (HUDReading) -> Void)?
    private var device: AudioDeviceID?

    /// Held so the same block can be removed again. CoreAudio matches
    /// listeners by block identity, and a block literal written twice is two
    /// different blocks — which is how a "removed" listener keeps firing.
    private var listener: AudioObjectPropertyListenerBlock?

    func start(onChange: @escaping @MainActor (HUDReading) -> Void) {
        guard listener == nil else { return }
        self.onChange = onChange

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            // CoreAudio calls this on its own queue.
            Task { @MainActor in self?.report() }
        }
        listener = block

        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &Self.defaultDeviceAddress,
            DispatchQueue.main,
            block
        )

        attachToCurrentDevice()
    }

    func stop() {
        guard let listener else { return }

        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &Self.defaultDeviceAddress,
            DispatchQueue.main,
            listener
        )
        detachFromDevice()

        self.listener = nil
        onChange = nil
    }

    /// The current state, without waiting for a change. Used to seed the
    /// policy at activation so switching the module on does not then
    /// announce the volume you were already at.
    func reading() -> HUDReading? {
        guard let device = Self.currentDevice() else { return nil }

        let muted = Self.isMuted(device)
        guard let level = Self.volume(of: device) else {
            // A device with no software volume control — most USB interfaces
            // and some external DACs. Mute is still worth a HUD; a level is
            // not available at all.
            return HUDReading(
                kind: .volume,
                isMuted: muted,
                title: muted ? "Muted" : "Volume",
                detail: Self.name(of: device)
            )
        }

        return HUDReading(
            kind: .volume,
            level: muted ? 0 : level,
            isMuted: muted,
            title: muted ? "Muted" : "Volume",
            detail: Self.name(of: device)
        )
    }

    // MARK: - Device listeners

    private func report() {
        // The default device may have changed underneath us, in which case
        // the listeners have to move with it.
        if Self.currentDevice() != device {
            detachFromDevice()
            attachToCurrentDevice()
        }
        guard let reading = reading() else { return }
        onChange?(reading)
    }

    private func attachToCurrentDevice() {
        guard let device = Self.currentDevice(), let listener else { return }
        self.device = device

        for address in Self.deviceAddresses {
            var address = address
            AudioObjectAddPropertyListenerBlock(device, &address, DispatchQueue.main, listener)
        }
    }

    private func detachFromDevice() {
        guard let device, let listener else { return }

        for address in Self.deviceAddresses {
            var address = address
            AudioObjectRemovePropertyListenerBlock(device, &address, DispatchQueue.main, listener)
        }
        self.device = nil
    }

    // MARK: - CoreAudio

    nonisolated(unsafe) private static var defaultDeviceAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    private static let deviceAddresses: [AudioObjectPropertyAddress] = [
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        ),
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
    ]

    private static func currentDevice() -> AudioDeviceID? {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultDeviceAddress,
            0,
            nil,
            &size,
            &deviceID
        )
        return status == noErr && deviceID != 0 ? deviceID : nil
    }

    /// The main-element scalar, falling back to the average of the channels.
    ///
    /// Plenty of devices publish no main element and only per-channel
    /// volumes; asking only for the main one reports silence on those.
    private static func volume(of device: AudioDeviceID) -> Double? {
        if let main = scalar(device, element: kAudioObjectPropertyElementMain) {
            return main
        }

        let channels = [1, 2].compactMap { scalar(device, element: AudioObjectPropertyElement($0)) }
        guard !channels.isEmpty else { return nil }
        return channels.reduce(0, +) / Double(channels.count)
    }

    private static func scalar(
        _ device: AudioDeviceID,
        element: AudioObjectPropertyElement
    ) -> Double? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: element
        )
        guard AudioObjectHasProperty(device, &address) else { return nil }

        var value = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        guard
            AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr,
            value.isFinite
        else { return nil }

        return Double(value)
    }

    private static func isMuted(_ device: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(device, &address) else { return false }

        var muted = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard
            AudioObjectGetPropertyData(device, &address, 0, nil, &size, &muted) == noErr
        else { return false }

        return muted != 0
    }

    /// CoreAudio and CoreMediaIO both hand back a retained `CFString`.
    ///
    /// Read through `Unmanaged` rather than into a `CFString` variable:
    /// Swift 6 rejects `&someCFString` outright, because taking a raw pointer
    /// to a variable that may hold an object reference is exactly the kind of
    /// thing that used to work by accident.
    private static func name(of device: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<CFTypeRef>.size)

        guard
            AudioObjectGetPropertyData(device, &address, 0, nil, &size, &name) == noErr,
            let value = name?.takeRetainedValue()
        else { return nil }

        let string = value as String
        return string.isEmpty ? nil : string
    }
}
