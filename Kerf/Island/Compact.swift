import KerfKit
import SwiftUI

/// What the compact island shows, one thing on each side of the notch like the iPhone's leading
/// and trailing views. Modules add cases. Everything fits the same wings as the volume: the island
/// has two sizes, compact and open, and never grows for what it shows.
enum CompactPresentation: Equatable {
    /// A short message, one thing on each side. Transient.
    case banner(BannerSide, BannerSide)
    /// An agent waits: its app's icon left, the orange dot right.
    case agent(hostPath: String?)
    /// Threads finished or asking in their own window: the newest's mark left, a tick (or a
    /// bubble) right, with how many when more than one. Stays until you click or look.
    case agentNotice(agent: AgentKind, hostPath: String?, count: Int, needsInput: Bool)

    /// Short-lived or urgent: shows even where it covers an app's menus.
    var showsOverMenus: Bool {
        switch self {
        case .banner, .agent, .agentNotice: true
        }
    }

    var noticeCount: Int {
        if case .agentNotice(_, _, let count, _) = self { count } else { 0 }
    }

    /// Same kind: update in place. Another kind: fade out, swap, fade in.
    var kind: String {
        switch self {
        case .banner(let leading, let trailing): "banner.\(leading.id).\(trailing.id)"
        case .agent: "agent"
        case .agentNotice: "agentNotice"
        }
    }
}

/// One side of a banner. Words don't fit beside the notch: a symbol, a few characters, or an
/// agent's mark.
enum BannerSide: Equatable {
    case symbol(String, Color)
    case value(String)
    case agent(AgentKind)

    var id: String {
        switch self {
        case .symbol(let name, _): name
        case .value(let text): text
        case .agent(let agent): agent.rawValue
        }
    }
}

struct BannerSideView: View {
    let side: BannerSide

    var body: some View {
        switch side {
        case .symbol(let name, let tint):
            Image(systemName: name).font(.system(size: 14, weight: .semibold)).foregroundStyle(tint)
        case .value(let text):
            Text(verbatim: text).font(.system(size: 12, weight: .semibold).monospacedDigit()).foregroundStyle(.white)
                .lineLimit(1).minimumScaleFactor(0.7)
        case .agent(let agent):
            AgentMark(agent: agent, hostPath: nil, size: 18)
        }
    }
}

struct CompactView: View {
    let presentation: CompactPresentation?
    let centerWidth: CGFloat
    let height: CGFloat
    private let wings = IslandGeometry.wing
    /// An agent is waiting: the orange dot takes the right side, whatever else shows.
    let showsAgentDot: Bool

    var body: some View {
        HStack(spacing: 0) {
            leading
                .frame(width: wings)
            Color.clear.frame(width: centerWidth)
            Group {
                if showsAgentDot { AgentDot() } else { trailing }
            }
            .frame(width: wings)
        }
        .frame(height: height)
    }

    @ViewBuilder private var leading: some View {
        switch presentation {
        case .banner(let side, _):
            BannerSideView(side: side)
        case .agent(let hostPath):
            AgentMark(agent: AgentCenter.shared.requests.first?.agent ?? .claudeCode, hostPath: hostPath, size: 18)
        case .agentNotice(let agent, let hostPath, _, _):
            AgentMark(agent: agent, hostPath: hostPath, size: 18)
        case nil:
            EmptyView()
        }
    }

    @ViewBuilder private var trailing: some View {
        switch presentation {
        case .banner(_, let side):
            BannerSideView(side: side)
        case .agent:
            AgentDot()
        case .agentNotice(_, _, let count, let needsInput):
            HStack(spacing: 3) {
                Image(systemName: needsInput ? "ellipsis.bubble.fill" : "checkmark.circle.fill").font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(nsColor: needsInput ? .systemOrange : .systemGreen))
                if count > 1 {
                    Text(verbatim: "\(count)").font(.system(size: 11, weight: .semibold).monospacedDigit()).foregroundStyle(.white.opacity(0.8))
                        .contentTransition(.numericText())
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Threads to look at: \(count)"))
        case nil:
            EmptyView()
        }
    }
}

/// Apple orange, with a soft glow. Stays until the agent has its answer.
struct AgentDot: View {
    var body: some View {
        Circle()
            .fill(Color(nsColor: .systemOrange))
            .frame(width: 9, height: 9)
            .shadow(color: Color(nsColor: .systemOrange).opacity(0.8), radius: 4)
            .accessibilityLabel(Text("An agent is waiting for you"))
    }
}
