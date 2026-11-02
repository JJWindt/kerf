import SwiftUI

/// Sound: the Mac's volume and brightness, and a level for every app that plays.
struct MixerPage: View {
    private let mixer = AppMixer.shared
    private let system = SystemControls.shared

    var body: some View {
        VStack(alignment: .leading, spacing: ui(4)) {
            row(icon: Image(systemName: "laptopcomputer"), name: Host.current().localizedName ?? "Mac", value: system.volume,
                symbol: "speaker.wave.2.fill", label: "Volume") { system.setVolume($0) }
            // Rows by position, not by app: when the order changes, each row simply shows its new
            // app. Nothing slides or fades.
            ForEach(Array(mixer.channels.enumerated()), id: \.offset) { _, channel in
                row(icon: channel.icon.map { Image(nsImage: $0) } ?? Image(systemName: "app.fill"), name: channel.name, value: channel.gain,
                    symbol: channel.isPlaying ? "speaker.wave.2.fill" : "speaker.fill", label: LocalizedStringKey(channel.name)) {
                    mixer.setGain($0, for: channel)
                }
                .opacity(channel.isPlaying ? 1 : 0.55)
            }
            .transaction { $0.animation = nil }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, ui(20))
        .padding(.top, ui(6))
        .task {
            system.refresh()
            // Which app plays changes without notice: look again while the page is open.
            while !Task.isCancelled {
                mixer.refresh()
                try? await Task.sleep(for: .seconds(1.5))
            }
        }
    }

    private func row(icon: Image, name: String, value: Double, symbol: String, label: LocalizedStringKey, change: @escaping (Double) -> Void) -> some View {
        HStack(spacing: ui(10)) {
            icon.resizable().aspectRatio(contentMode: .fit).frame(width: ui(24), height: ui(24))
            Text(verbatim: name).font(.page(13, weight: .semibold)).lineLimit(1).frame(width: ui(92), alignment: .leading)
            CapsuleSlider(value: value, symbol: symbol, label: label, change: change)
                .frame(height: ui(24))
        }
        .frame(height: ui(28))
    }

    static var contentHeight: CGFloat {
        let rows = 1 + min(AppMixer.shared.channels.count, 4)
        return CGFloat(rows) * 40 + 14
    }
}
