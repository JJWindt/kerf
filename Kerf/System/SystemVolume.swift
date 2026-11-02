import AudioToolbox
import CoreAudio

/// The default output's volume, as the volume keys change it. No permission needed.
enum SystemVolume {
    private static func device() -> AudioDeviceID? {
        var id = AudioDeviceID()
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id)
        return status == noErr ? id : nil
    }

    private static var volumeAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                                   mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
    }

    private static var muteAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute, mScope: kAudioDevicePropertyScopeOutput,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    /// Some outputs (HDMI, some interfaces) have no software volume; their keys pass through.
    static var isSettable: Bool {
        guard let device = device() else { return false }
        var address = volumeAddress
        var settable: DarwinBoolean = false
        return AudioObjectIsPropertySettable(device, &address, &settable) == noErr && settable.boolValue
    }

    static var level: Double {
        get {
            guard let device = device() else { return 0 }
            var value = Float32(0)
            var size = UInt32(MemoryLayout<Float32>.size)
            var address = volumeAddress
            AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value)
            return Double(value)
        }
        set {
            guard let device = device() else { return }
            var value = Float32(min(max(newValue, 0), 1))
            var address = volumeAddress
            AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &value)
            if value > 0, isMuted { isMuted = false }
        }
    }

    static var isMuted: Bool {
        get {
            guard let device = device() else { return false }
            var value = UInt32(0)
            var size = UInt32(MemoryLayout<UInt32>.size)
            var address = muteAddress
            AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value)
            return value != 0
        }
        set {
            guard let device = device() else { return }
            var value = UInt32(newValue ? 1 : 0)
            var address = muteAddress
            AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
        }
    }
}
