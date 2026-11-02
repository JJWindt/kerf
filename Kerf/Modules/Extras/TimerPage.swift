import KerfKit
import SwiftUI

/// Timers the way the iPhone's Clock and its Live Activity show them: a big orange countdown with
/// round pause and cancel buttons, or round buttons to start one.
struct TimerPage: View {
    private let timers = TimerModule.shared
    @State private var custom = ""

    var body: some View {
        Group {
            if let main = timers.timers.first {
                running(main)
            } else {
                presets
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, ui(22))
        .padding(.top, ui(6))
    }

    static var contentHeight: CGFloat {
        let count = TimerModule.shared.timers.count
        return count == 0 ? 186 : 104 + CGFloat(min(count - 1, 2)) * 34
    }

    private func running(_ timer: TimerModule.Running) -> some View {
        VStack(alignment: .leading, spacing: ui(6)) {
            HStack(alignment: .center, spacing: ui(14)) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Timer").font(.page(13, weight: .semibold)).foregroundStyle(Color(nsColor: .systemOrange))
                    countdown(timer, size: ui(44))
                    Group {
                        if timer.paused != nil {
                            Text("Paused")
                        } else {
                            Text("Ends at \(timer.end.formatted(date: .omitted, time: .shortened))")
                        }
                    }
                    .font(.page(12, weight: .medium)).foregroundStyle(.white.opacity(0.5))
                }
                Spacer()
                RoundButton(symbol: timer.paused == nil ? "pause.fill" : "play.fill", tint: Color(nsColor: .systemOrange),
                            label: timer.paused == nil ? "Pause" : "Resume") {
                    if timer.paused == nil { timers.pause(timer) } else { timers.resume(timer) }
                }
                RoundButton(symbol: "xmark", tint: .white, label: "Cancel") { timers.cancel(timer) }
            }
            ForEach(timers.timers.dropFirst().prefix(2)) { other in
                HStack {
                    Image(systemName: "timer").foregroundStyle(Color(nsColor: .systemOrange))
                    countdown(other, size: ui(15))
                    Spacer()
                    Button { timers.cancel(other) } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.white.opacity(0.4)) }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("Cancel"))
                }
                .frame(height: ui(34))
            }
        }
    }

    @ViewBuilder private func countdown(_ timer: TimerModule.Running, size: CGFloat) -> some View {
        Group {
            if let paused = timer.paused {
                Text(verbatim: Duration.seconds(paused).formatted(.time(pattern: paused >= 3600 ? .hourMinuteSecond : .minuteSecond)))
            } else {
                Text(timerInterval: Date.now...max(timer.end, .now), countsDown: true)
            }
        }
        .font(.system(size: size, weight: size > 30 ? .light : .semibold).monospacedDigit())
        .foregroundStyle(Color(nsColor: .systemOrange))
    }

    private var presets: some View {
        VStack(spacing: ui(12)) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: ui(12)), count: 4), spacing: ui(10)) {
                ForEach(TimerModule.presets, id: \.self) { duration in
                    Button { timers.start(duration) } label: {
                        VStack(spacing: 0) {
                            Text(verbatim: duration >= 3600 ? "\(Int(duration / 3600))" : "\(Int(duration / 60))")
                                .font(.page(19, weight: .semibold).monospacedDigit())
                            Text(duration >= 3600 ? "hour" : "min").font(.page(10, weight: .medium)).foregroundStyle(.white.opacity(0.6))
                        }
                        .frame(width: ui(52), height: ui(52))
                        .background(Color(white: 0.2), in: Circle())
                        .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack(spacing: ui(8)) {
                Image(systemName: "timer").font(.page(13, weight: .semibold)).foregroundStyle(Color(nsColor: .systemOrange))
                TextField("Other time, like 7m30", text: $custom)
                    .textFieldStyle(.plain)
                    .font(.page(14))
                    .onSubmit(startCustom)
                if DurationParser.seconds(custom) != nil {
                    Button(action: startCustom) {
                        Image(systemName: "play.circle.fill").font(.page(18, weight: .semibold)).foregroundStyle(Color(nsColor: .systemOrange))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Start"))
                }
            }
            .padding(.horizontal, ui(14))
            .frame(height: ui(34))
            .background(.white.opacity(0.1), in: Capsule())
        }
    }

    private func startCustom() {
        guard let seconds = DurationParser.seconds(custom) else { return }
        timers.start(seconds)
        custom = ""
    }
}

/// A round island button like the Clock app's: a tinted circle with a symbol.
struct RoundButton: View {
    let symbol: String
    let tint: Color
    let label: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.page(17, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: ui(46), height: ui(46))
                .background(tint.opacity(0.22), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }
}
