import KerfKit
import SwiftUI

/// Apple Music's Dynamic Island card, for whatever plays.
struct MusicPage: View {
    private let music = NowPlayingModule.shared

    var body: some View {
        content.onAppear { music.refreshNow() }
    }

    @ViewBuilder private var content: some View {
        if let state = music.state {
            VStack(spacing: ui(6)) {
                HStack(spacing: ui(12)) {
                    Button { music.openSource() } label: {
                        ArtworkView(image: music.artwork, size: ui(54), radius: ui(12))
                            .overlay(alignment: .bottomTrailing) { SourceIcon(bundleID: state.sourceBundleID).offset(x: ui(5), y: ui(5)) }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Open the app that plays"))
                    VStack(alignment: .leading, spacing: ui(2)) {
                        Text(verbatim: state.title).font(.page(15, weight: .semibold)).lineLimit(1)
                        if !state.artist.isEmpty {
                            Text(verbatim: state.artist).font(.page(13)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                        }
                    }
                    Spacer(minLength: ui(8))
                    Waveform(tint: music.tint, isPlaying: state.isPlaying, size: ui(20))
                }
                if let duration = state.duration {
                    Scrubber(state: state, duration: duration) { music.seek(to: $0) }
                }
                HStack(spacing: ui(44)) {
                    IslandIconButton(symbol: "backward.fill", label: "Previous") { music.send(.previous) }
                    IslandIconButton(symbol: state.isPlaying ? "pause.fill" : "play.fill", label: state.isPlaying ? "Pause" : "Play", size: ui(26)) {
                        music.send(.toggle)
                    }
                    .contentTransition(.symbolEffect(.replace))
                    IslandIconButton(symbol: "forward.fill", label: "Next") { music.send(.next) }
                }
                .frame(height: ui(36))
            }
            .padding(.horizontal, ui(24))
            .padding(.top, ui(6))
        } else {
            VStack(spacing: ui(6)) {
                Image(systemName: "music.note").font(.page(24, weight: .semibold)).foregroundStyle(.white.opacity(0.5))
                Text("Nothing is playing").font(.page(14, weight: .medium)).foregroundStyle(.white.opacity(0.6))
            }
            .frame(maxWidth: .infinity, minHeight: ui(110))
        }
    }
}

/// The app that plays, small on the artwork's corner, as iOS marks a third-party source.
struct SourceIcon: View {
    let bundleID: String

    var body: some View {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .frame(width: ui(20), height: ui(20))
                .shadow(color: .black.opacity(0.5), radius: ui(2))
        }
    }
}

/// The position: a thin bar with times. Ticks once a second, and only while the page is open.
struct Scrubber: View {
    let state: NowPlayingState
    let duration: Double
    let seek: (Double) -> Void
    @State private var dragged: Double?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let elapsed = dragged ?? state.elapsed(at: context.date)
            VStack(spacing: ui(4)) {
                GeometryReader { proxy in
                    LevelBar(value: elapsed / duration)
                        .contentShape(Rectangle().inset(by: -8))
                        .gesture(DragGesture(minimumDistance: 0)
                            .onChanged { dragged = min(max($0.location.x / proxy.size.width, 0), 1) * duration }
                            .onEnded { _ in
                                if let dragged { seek(dragged) }
                                dragged = nil
                            })
                }
                .frame(height: ui(4))
                HStack {
                    Text(verbatim: NowPlayingState.clock(elapsed))
                    Spacer()
                    Text(verbatim: "-" + NowPlayingState.clock(max(duration - elapsed, 0)))
                }
                .font(.page(11, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.5))
            }
        }
    }
}
