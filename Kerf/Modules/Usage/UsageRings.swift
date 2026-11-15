import KerfKit
import SwiftUI

/// The usage rings beside the notch: the 5 hours left of it, the week right of it.
struct UsageStrip: Equatable {
    var left: Bool
    var right: Bool

    static let ring: CGFloat = 20
    /// A ring and 8 pt on each end.
    static let width: CGFloat = ring + 16
    var leading: CGFloat { left ? Self.width : 0 }
    var trailing: CGFloat { right ? Self.width : 0 }
}

/// 5 hours in orange left of the notch, the week in red right of it, with how much of each is used.
/// A ring without room beside the app's menus waits for it.
struct UsageRings: View {
    let centerWidth: CGFloat
    let fitting: UsageStrip?

    var body: some View {
        let usage = ClaudeUsageModule.shared.usage
        HStack(spacing: 0) {
            ring(usage?.session, tint: .systemOrange, name: Text("5-hour session"), shown: fitting?.left == true)
            Color.clear.frame(width: centerWidth)
            ring(usage?.week, tint: .systemRed, name: Text("Week"), shown: fitting?.right == true)
        }
        .animation(.smooth(duration: 0.2), value: fitting)
    }

    private func ring(_ limit: ClaudeUsage.Limit?, tint: NSColor, name: Text, shown: Bool) -> some View {
        Color.clear.frame(width: UsageStrip.width).overlay {
            if let limit {
                UsageRing(limit: limit, tint: Color(nsColor: tint), name: name)
                    .modifier(IslandContentEffect(hidden: shown ? 0 : 1, blur: 8))
            }
        }
    }
}

/// A ring that fills, on a dim track of its own colour, with the number small in the middle in that colour.
struct UsageRing: View {
    let limit: ClaudeUsage.Limit
    let tint: Color
    let name: Text
    private static let line: CGFloat = 2.2

    var body: some View {
        let percent = limit.percent(at: .now).rounded()
        ZStack {
            Circle().stroke(tint.opacity(0.28), lineWidth: Self.line)
            Circle().trim(from: 0, to: percent / 100)
                .stroke(tint, style: StrokeStyle(lineWidth: Self.line, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(verbatim: "\(Int(percent))")
                .font(.system(size: 8.5, weight: .medium).monospacedDigit().width(.condensed))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .contentTransition(.numericText())
                .padding(.horizontal, 2.5)
        }
        // The stroke is drawn around the path: half of it would fall outside the frame.
        .padding(Self.line / 2)
        .frame(width: UsageStrip.ring, height: UsageStrip.ring)
        .animation(.smooth(duration: 0.4), value: percent)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
        .accessibilityValue(Text("\(Int(percent)) percent used"))
    }
}
