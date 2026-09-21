import CoreAudio
import CoreMediaIO
import Foundation
import PerchCore

/// Watches whether anything is using the camera or the microphone.
///
/// The privacy dot, with something useful attached to it: macOS tells you
/// *that* the camera is on, and Perch can also say which device.
///
/// Both halves are property listeners on `…DeviceIsRunningSomewhere` —
/// CoreAudio's for the microphone, CoreMediaIO's for the camera. Neither
/// polls, and neither needs Camera or Microphone permission: asking whether a
/// device is in use is not the same as opening it, which is the whole point
/// of a privacy indicator (`CLAUDE.md` §5.3).
///
/// **Screen recording is not covered.** `docs/FEATURES.md` §6 pairs it with
/// the camera and there is no interface for it — no property, no
/// notification, and nothing short of Screen Recording permission, which
/// Perch is not going to request in order to tell you that something else has
/// it. Recorded as not done rather than faked.
@MainActor
final class CaptureWatcher {

    private var onChange: (@MainActor (HUDReading) -> Void)?

    private var audioListener: AudioObjectPropertyListenerBlock?
    private var audioDevices: [AudioDeviceID] = []

    private var videoListener: CMIOObjectPropertyListenerBlock?
    private var videoDevices: [CMIOObjectID] = []

    func start(onChange: @escaping @MainActor (HUDReading) -> Void) {
        guard audioListener == nil, videoListener == nil else { return }
        self.onChange = onChange

        attachMicrophones()
        attachCameras()
    }

    func stop() {
        if let audioListener {
            for device in audioDevices {
                var address = Self.audioRunning
                AudioObjectRemovePropertyListenerBlock(
                    device,
                    &address,
                    DispatchQueue.main,
                    audioListener
                )
            }
        }
        audioDevices.removeAll()
        audioListener = nil

        if let videoListener {
            for device in videoDevices {
                var address = Self.videoRunning
                CMIOObjectRemovePropertyListenerBlock(
                    device,
                    &address,
                    DispatchQueue.main,
                    videoListener
                )
            }
        }
        videoDevices.removeAll()
        videoListener = nil

        onChange = nil
    }

    /// The current state. `nil` when nothing is in use, which is the case
    /// nearly all of the time and is not worth a HUD.
    func reading() -> HUDReading? {
        let camera = cameraInUse()
        let microphone = microphoneInUse()

        switch (camera, microphone) {
        case (.some(let name), .some):
            return HUDReading(kind: .capture, title: "Camera and microphone in use", detail: name)
        case (.some(let name), .none):
            return HUDReading(kind: .capture, title: "Camera in use", detail: name)
        case (.none, .some(let name)):
            return HUDReading(kind: .capture, title: "Microphone in use", detail: name)
        case (.none, .none):
            return nil
        }
    }

    // MARK: - Reporting

    private func report() {
        // Nothing in use is a real transition and the view needs to know, so
        // it is reported as an explicit "off" rather than by saying nothing.
        onChange?(reading() ?? HUDReading(kind: .capture, title: "Camera and microphone off"))
    }

}

// MARK: - Microphone

extension CaptureWatcher {

    nonisolated(unsafe) fileprivate static var audioRunning = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    private func attachMicrophones() {
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in self?.report() }
        }
        audioListener = block

        audioDevices = Self.inputDeviceIDs()

        for device in audioDevices {
            var address = Self.audioRunning
            AudioObjectAddPropertyListenerBlock(device, &address, DispatchQueue.main, block)
        }
    }

    private func microphoneInUse() -> String? {
        for device in audioDevices where Self.isRunning(audio: device) {
            return Self.name(audio: device) ?? "Microphone"
        }
        return nil
    }

    /// Every device with an input stream.
    ///
    /// Enumerated straight from CoreAudio rather than matched up from
    /// `AVCaptureDevice`: translating a `uniqueID` needs a `CFString`
    /// qualifier pointer, which Swift 6 refuses to form, and this is both
    /// simpler and one framework lighter.
    private static func inputDeviceIDs() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var size = UInt32(0)
        guard
            AudioObjectGetPropertyDataSize(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                0,
                nil,
                &size
            ) == noErr,
            size > 0
        else { return [] }

        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var devices = [AudioDeviceID](repeating: 0, count: count)
        guard
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                0,
                nil,
                &size,
                &devices
            ) == noErr
        else { return [] }

        return devices.filter { hasInput($0) }
    }

    private static func hasInput(_ device: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        var size = UInt32(0)
        guard
            AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr,
            size >= UInt32(MemoryLayout<AudioBufferList>.size)
        else { return false }

        let buffer = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { buffer.deallocate() }

        guard
            AudioObjectGetPropertyData(device, &address, 0, nil, &size, buffer) == noErr
        else { return false }

        let list = UnsafeMutableAudioBufferListPointer(
            buffer.assumingMemoryBound(to: AudioBufferList.self)
        )
        return list.contains { $0.mNumberChannels > 0 }
    }

    private static func isRunning(audio device: AudioDeviceID) -> Bool {
        var address = audioRunning
        var running = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)

        guard
            AudioObjectGetPropertyData(device, &address, 0, nil, &size, &running) == noErr
        else { return false }
        return running != 0
    }

    private static func name(audio device: AudioDeviceID) -> String? {
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

// MARK: - Camera

extension CaptureWatcher {

    nonisolated(unsafe) fileprivate static var videoRunning = CMIOObjectPropertyAddress(
        mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
        mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeWildcard),
        mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementWildcard)
    )

    private func attachCameras() {
        let block: CMIOObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in self?.report() }
        }
        videoListener = block

        videoDevices = Self.cameraIDs()
        for device in videoDevices {
            var address = Self.videoRunning
            CMIOObjectAddPropertyListenerBlock(device, &address, DispatchQueue.main, block)
        }
    }

    private func cameraInUse() -> String? {
        for device in videoDevices where Self.isRunning(video: device) {
            return Self.name(video: device) ?? "Camera"
        }
        return nil
    }

    private static func cameraIDs() -> [CMIOObjectID] {
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )

        var size = UInt32(0)
        guard
            CMIOObjectGetPropertyDataSize(
                CMIOObjectID(kCMIOObjectSystemObject),
                &address,
                0,
                nil,
                &size
            ) == 0,
            size > 0
        else { return [] }

        let count = Int(size) / MemoryLayout<CMIOObjectID>.size
        var devices = [CMIOObjectID](repeating: 0, count: count)
        var used = UInt32(0)

        guard
            CMIOObjectGetPropertyData(
                CMIOObjectID(kCMIOObjectSystemObject),
                &address,
                0,
                nil,
                size,
                &used,
                &devices
            ) == 0
        else { return [] }

        return devices.filter { $0 != 0 }
    }

    private static func isRunning(video device: CMIOObjectID) -> Bool {
        var address = videoRunning
        var running = UInt32(0)
        var used = UInt32(0)

        guard
            CMIOObjectGetPropertyData(
                device,
                &address,
                0,
                nil,
                UInt32(MemoryLayout<UInt32>.size),
                &used,
                &running
            ) == 0
        else { return false }
        return running != 0
    }

    private static func name(video device: CMIOObjectID) -> String? {
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOObjectPropertyName),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        var name: Unmanaged<CFString>?
        var used = UInt32(0)

        guard
            CMIOObjectGetPropertyData(
                device,
                &address,
                0,
                nil,
                UInt32(MemoryLayout<CFTypeRef>.size),
                &used,
                &name
            ) == 0,
            let value = name?.takeRetainedValue()
        else { return nil }

        let string = value as String
        return string.isEmpty ? nil : string
    }
}
