import CoreAudio
import Foundation

/// Where the sound is going, and how to send it somewhere else.
///
/// This is the "AirPlay / output device picker" row of `docs/FEATURES.md` §1.
/// AirPlay targets, Bluetooth headphones, USB interfaces and the built-in
/// speakers are all the same thing to CoreAudio — an output device — so
/// routing to an AirPlay speaker is setting the default output device, and
/// needs no private API and no network.
///
/// Read on demand, never observed. The list matters only while the picker is
/// open, and a property listener that outlives the menu is a wakeup for every
/// device that ever connects (`CLAUDE.md` §5.1).
@MainActor
enum AudioOutputService {

    struct Device: Identifiable, Hashable, Sendable {
        let id: AudioDeviceID
        let name: String
        let transport: UInt32

        /// The symbol that makes the list scannable: you pick by shape, not
        /// by reading four device names.
        var symbolName: String {
            switch transport {
            case kAudioDeviceTransportTypeAirPlay: "airplayaudio"
            case kAudioDeviceTransportTypeBluetooth,
                kAudioDeviceTransportTypeBluetoothLE:
                "headphones"
            case kAudioDeviceTransportTypeUSB: "cable.connector"
            case kAudioDeviceTransportTypeHDMI,
                kAudioDeviceTransportTypeDisplayPort:
                "tv"
            case kAudioDeviceTransportTypeVirtual,
                kAudioDeviceTransportTypeAggregate:
                "square.stack.3d.up"
            default: "speaker.wave.2"
            }
        }
    }

    /// Every device that can play sound, in the order CoreAudio reports them.
    static func outputDevices() -> [Device] {
        deviceIDs()
            .filter(hasOutput)
            .compactMap { id in
                guard let name = name(of: id) else { return nil }
                return Device(id: id, name: name, transport: transport(of: id))
            }
    }

    static var currentOutputDeviceID: AudioDeviceID? {
        var address = address(kAudioHardwarePropertyDefaultOutputDevice)
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )
        return status == noErr ? deviceID : nil
    }

    /// Routes system audio to a device.
    ///
    /// - Returns: whether CoreAudio accepted it. A device that has just gone
    ///   away returns `false` rather than throwing, and the picker simply
    ///   reloads.
    @discardableResult
    static func setOutputDevice(_ id: AudioDeviceID) -> Bool {
        var address = address(kAudioHardwarePropertyDefaultOutputDevice)
        var deviceID = id
        let size = UInt32(MemoryLayout<AudioDeviceID>.size)

        return AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            size,
            &deviceID
        ) == noErr
    }

    // MARK: - CoreAudio

    private static func address(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private static func deviceIDs() -> [AudioDeviceID] {
        var propertyAddress = address(kAudioHardwarePropertyDevices)
        var size = UInt32(0)

        guard
            AudioObjectGetPropertyDataSize(
                AudioObjectID(kAudioObjectSystemObject),
                &propertyAddress,
                0,
                nil,
                &size
            ) == noErr,
            size > 0
        else { return [] }

        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)

        guard
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &propertyAddress,
                0,
                nil,
                &size,
                &ids
            ) == noErr
        else { return [] }

        return ids
    }

    /// A device counts as an output if it has at least one output channel.
    /// Microphones and aggregate input devices are in the same list and must
    /// not appear in the picker.
    private static func hasOutput(_ id: AudioDeviceID) -> Bool {
        var propertyAddress = address(
            kAudioDevicePropertyStreamConfiguration,
            scope: kAudioDevicePropertyScopeOutput
        )
        var size = UInt32(0)

        guard
            AudioObjectGetPropertyDataSize(id, &propertyAddress, 0, nil, &size) == noErr,
            size > 0
        else { return false }

        let buffer = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { buffer.deallocate() }

        guard
            AudioObjectGetPropertyData(id, &propertyAddress, 0, nil, &size, buffer) == noErr
        else { return false }

        let list = UnsafeMutableAudioBufferListPointer(
            buffer.assumingMemoryBound(to: AudioBufferList.self)
        )
        return list.contains { $0.mNumberChannels > 0 }
    }

    private static func name(of id: AudioDeviceID) -> String? {
        var propertyAddress = address(kAudioObjectPropertyName)
        var size = UInt32(MemoryLayout<CFString?>.size)
        var name: CFString?

        let status = withUnsafeMutablePointer(to: &name) { pointer in
            AudioObjectGetPropertyData(id, &propertyAddress, 0, nil, &size, pointer)
        }
        guard status == noErr else { return nil }
        return name as String?
    }

    private static func transport(of id: AudioDeviceID) -> UInt32 {
        var propertyAddress = address(kAudioDevicePropertyTransportType)
        var size = UInt32(MemoryLayout<UInt32>.size)
        var transport = UInt32(0)

        guard
            AudioObjectGetPropertyData(
                id, &propertyAddress, 0, nil, &size, &transport
            ) == noErr
        else { return 0 }

        return transport
    }
}
