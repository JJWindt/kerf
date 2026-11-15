import KerfKit
import SwiftUI

/// A usage ring at one end of the open island's band: the 5 hours in orange on the left, the week
/// in red on the right. Nothing while usage is off or not known.
struct BandUsageRing: View {
    let edge: HorizontalEdge
    /// From the island's edge, and the air between the ring and the tabs: with three tabs beside
    /// it, 12 + 20 + 4 + 61 pt fills the 97 pt beside the notch.
    private static let inset: CGFloat = 12
    static let gap: CGFloat = 4

    var body: some View {
        let usage = ClaudeUsageModule.shared.usage
        if let limit = edge == .leading ? usage?.session : usage?.week {
            UsageRing(limit: limit, tint: Color(nsColor: edge == .leading ? .systemOrange : .systemRed),
                      name: edge == .leading ? Text("5-hour session") : Text("Week"))
                .padding(edge == .leading ? .leading : .trailing, Self.inset)
        }
    }
}

/// A ring that fills, on a dim track of its own colour, with the number small in the middle in that colour.
struct UsageRing: View {
    let limit: ClaudeUsage.Limit
    let tint: Color
    let name: Text
    static let size: CGFloat = 20
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
        .frame(width: Self.size, height: Self.size)
        .animation(.smooth(duration: 0.4), value: percent)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
        .accessibilityValue(Text("\(Int(percent)) percent used"))
    }
}
