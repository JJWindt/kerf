import KerfKit
import SwiftUI

/// What the island opens on: what plays on the left, what's left of today on the right. Each side
/// leads to its own page. With nothing playing, only the agenda.
struct HomePage: View {
    private let music = NowPlayingModule.shared

    var body: some View {
        // Both sides as tall as the taller one: the music reaches the bottom like the agenda.
        HStack(alignment: .top, spacing: ui(20)) {
            if music.state != nil {
                HomeMusic().frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
            HomeAgenda().frame(maxWidth: .infinity, alignment: .leading)
        }
        .fixedSize(horizontal: false, vertical: true)
        .foregroundStyle(.white)
        .padding(.horizontal, ui(20))
        .padding(.top, ui(6))
        .onAppear { music.refreshNow() }
    }

    static var contentHeight: CGFloat { 110 }
}

private struct HomeMusic: View {
    private let music = NowPlayingModule.shared

    var body: some View {
        if let state = music.state {
            VStack(alignment: .leading, spacing: ui(6)) {
                HStack(spacing: ui(10)) {
                    Button { music.openSource() } label: {
                        ArtworkView(image: music.artwork, size: ui(44), radius: ui(10))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Open the app that plays"))
                    VStack(alignment: .leading, spacing: ui(1)) {
                        Text(verbatim: state.title).font(.page(13, weight: .semibold)).lineLimit(1)
                        if !state.artist.isEmpty {
                            Text(verbatim: state.artist).font(.page(12)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                        }
                    }
                    Spacer(minLength: ui(4))
                    Waveform(tint: music.tint, isPlaying: state.isPlaying, size: ui(14))
                }
                Spacer(minLength: 0)
                if let duration = state.duration {
                    Scrubber(state: state, duration: duration) { music.seek(to: $0) }
                }
                HStack(spacing: ui(22)) {
                    IslandIconButton(symbol: "backward.fill", label: "Previous", size: ui(15)) { music.send(.previous) }
                    IslandIconButton(symbol: state.isPlaying ? "pause.fill" : "play.fill", label: state.isPlaying ? "Pause" : "Play", size: ui(20)) {
                        music.send(.toggle)
                    }
                    .contentTransition(.symbolEffect(.replace))
                    IslandIconButton(symbol: "forward.fill", label: "Next", size: ui(15)) { music.send(.next) }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

private struct HomeAgenda: View {
    private let calendar = CalendarModule.shared
    @Environment(Island.self) private var island

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let upcoming = calendar.events.filter { $0.end > context.date }
            VStack(alignment: .leading, spacing: ui(6)) {
                Text(context.date, format: .dateTime.weekday(.wide).day().month(.wide))
                    .font(.page(12, weight: .semibold)).foregroundStyle(.white.opacity(0.6))
                if !calendar.hasAccess {
                    Button("Show your calendar") { calendar.requestAccess() }
                        .buttonStyle(.plain).font(.page(13, weight: .medium))
                } else if upcoming.isEmpty {
                    Text("Nothing else today").font(.page(13)).foregroundStyle(.white.opacity(0.55))
                } else {
                    ForEach(upcoming.prefix(3)) { event in
                        row(event, isNext: event.id == upcoming.first?.id, now: context.date)
                    }
                }
            }
        }
        .contentShape(Rectangle())
        // The whole day is one tap away.
        .onTapGesture { island.select(.today) }
    }

    private func row(_ event: CalendarModule.Event, isNext: Bool, now: Date) -> some View {
        HStack(spacing: ui(8)) {
            Capsule().fill(event.color).frame(width: ui(3), height: ui(28))
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: event.title).font(.page(12, weight: .semibold)).lineLimit(1)
                Text(event.when(now: now)).font(.page(11)).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
            }
            Spacer(minLength: ui(4))
            if isNext, event.joinURL != nil {
                Button { calendar.join(event) } label: {
                    Image(systemName: "video.fill").font(.page(11, weight: .semibold))
                        .foregroundStyle(Color(red: 0.306, green: 0.733, blue: 0.988))
                        .frame(width: ui(28), height: ui(24))
                        .background(Color(red: 0, green: 0.169, blue: 0.345), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Join"))
            }
        }
    }
}
