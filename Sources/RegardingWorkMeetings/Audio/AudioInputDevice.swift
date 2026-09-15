import CoreAudio
import Foundation

struct AudioInputDeviceIdentity: Codable, Equatable, Sendable {
    let id: UInt32
    let uid: String
    let name: String
}

enum DefaultAudioInputDevice {
    static func current() -> AudioInputDeviceIdentity? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        ) == noErr, deviceID != kAudioObjectUnknown else { return nil }

        guard let name = stringProperty(
            deviceID: deviceID,
            selector: kAudioObjectPropertyName
        ) else { return nil }
        let uid = stringProperty(
            deviceID: deviceID,
            selector: kAudioDevicePropertyDeviceUID
        ) ?? "coreaudio-device-\(deviceID)"
        return AudioInputDeviceIdentity(id: deviceID, uid: uid, name: name)
    }

    private static func stringProperty(
        deviceID: AudioObjectID,
        selector: AudioObjectPropertySelector
    ) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &size,
            &value
        ) == noErr, let value else { return nil }
        return value.takeUnretainedValue() as String
    }
}
