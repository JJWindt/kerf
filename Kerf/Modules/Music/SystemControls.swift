import AudioToolbox
import CoreAudio
import SwiftUI

/// Volume and display brightness, for the sliders on the music page. The volume follows changes
/// made anywhere (keys, Control Center) through a Core Audio listener.
@Observable
final class SystemControls {
    static let shared = SystemControls()

    private(set) var volume = SystemVolume.level
    private(set) var brightness = Brightness.level
    @ObservationIgnored private var listening: AudioObjectID?

    func refresh() {
        volume = SystemVolume.isMuted ? 0 : SystemVolume.level
        brightness = Brightness.level
        listen()
    }

    func setVolume(_ value: Double) {
        SystemVolume.level = value
        volume = value
    }

    func setBrightness(_ value: Double) {
        Brightness.level = value
        brightness = value
    }

    /// Hears volume changes on the current output.
    private func listen() {
        var device = AudioDeviceID()
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr,
              device != listening else { return }
        listening = device
        var volumeAddress = AudioObjectPropertyAddress(mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                                                       mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        AudioObjectAddPropertyListenerBlock(device, &volumeAddress, .main) { _, _ in
            MainActor.assumeIsolated { SystemControls.shared.volume = SystemVolume.level }
        }
    }
}

/// Control Center's slider: a thick capsule that fills white, with its symbol inside, dark where
/// the fill covers it.
struct CapsuleSlider: View {
    let value: Double
    let symbol: String
    let label: LocalizedStringKey
    let change: (Double) -> Void

    var body: some View {
        GeometryReader { proxy in
            let height = proxy.size.height
            let fill = height + (proxy.size.width - height) * min(max(value, 0), 1)
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.16))
                Image(systemName: symbol).font(.system(size: height * 0.42, weight: .semibold)).foregroundStyle(.white.opacity(0.75))
                    .frame(width: height)
                Capsule().fill(.white).frame(width: fill)
                    .overlay(alignment: .leading) {
                        Image(systemName: symbol).font(.system(size: height * 0.42, weight: .semibold)).foregroundStyle(.black.opacity(0.75))
                            .frame(width: height)
                    }
                    .clipShape(Capsule())
            }
            .contentShape(Capsule())
            .gesture(DragGesture(minimumDistance: 0).onChanged {
                change(min(max(($0.location.x - height / 2) / max(proxy.size.width - height, 1), 0), 1))
            })
        }
        .accessibilityElement()
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text(value, format: .percent.precision(.fractionLength(0))))
        .accessibilityAdjustableAction { direction in
            change(min(max(value + (direction == .increment ? 0.0625 : -0.0625), 0), 1))
        }
    }
}
