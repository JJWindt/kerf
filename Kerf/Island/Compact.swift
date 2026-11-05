import KerfKit
import SwiftUI

/// What the compact island shows, one thing on each side of the notch like the iPhone's leading
/// and trailing views. Everything fits the same wings beside the notch: the island
/// has two sizes, compact and open, and never grows for what it shows.
enum CompactPresentation: Equatable {
    /// A short message, one thing on each side. Transient.
    case banner(BannerSide, BannerSide)
    /// An agent waits: its app's icon left, the orange dot (and how many wait) right.
    case agent(agent: AgentKind, hostPath: String?)
    /// Threads finished or asking in their own window: the newest's mark left, a tick (or a
    /// bubble) right, with how many when more than one. Stays until you click or look.
    case agentNotice(agent: AgentKind, hostPath: String?, count: Int, needsInput: Bool, failed: Bool)
    /// Your PRs: a check failed, changes were asked or one got merged.
    case pullNotice(count: Int, tone: PullTone)

    /// Short-lived or urgent: shows even where it covers an app's menus.
    var showsOverMenus: Bool {
        switch self {
        case .banner, .agent, .agentNotice: true
        case .pullNotice: false
        }
    }

    var noticeCount: Int {
        if case .agentNotice(_, _, let count, _, _) = self { count } else { 0 }
    }

    /// Same kind: update in place. Another kind: fade out, swap, fade in.
    var kind: String {
        switch self {
        case .banner(let leading, let trailing): "banner.\(leading.id).\(trailing.id)"
        case .agent: "agent"
        case .agentNotice: "agentNotice"
        case .pullNotice: "pullNotice"
        }
    }
}

/// One side of a banner. Words don't fit beside the notch: a symbol or an agent's mark.
enum BannerSide: Equatable {
    case symbol(String, Color)
    case agent(AgentKind)

    var id: String {
        switch self {
        case .symbol(let name, _): name
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
    /// Threads waiting on you: the orange dot takes the right side, whatever else shows.
    let waitingCount: Int

    var body: some View {
        HStack(spacing: 0) {
            leading
                .frame(width: wings)
            Color.clear.frame(width: centerWidth)
            Group {
                if waitingCount > 0 { AgentDot(count: waitingCount) } else { trailing }
            }
            .frame(width: wings)
        }
        .frame(height: height)
    }

    @ViewBuilder private var leading: some View {
        switch presentation {
        case .banner(let side, _):
            BannerSideView(side: side)
        case .agent(let agent, let hostPath):
            AgentMark(agent: agent, hostPath: hostPath, size: 18)
        case .agentNotice(let agent, let hostPath, _, _, _):
            AgentMark(agent: agent, hostPath: hostPath, size: 18)
        case .pullNotice:
            Image(systemName: "arrow.triangle.pull").font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.8))
        case nil:
            EmptyView()
        }
    }

    @ViewBuilder private var trailing: some View {
        switch presentation {
        case .banner(_, let side):
            BannerSideView(side: side)
        case .agent:
            AgentDot(count: waitingCount)
        case .agentNotice(_, _, let count, let needsInput, let failed):
            HStack(spacing: 3) {
                // A thread that stopped on an error outranks one that asks, which outranks one that's done.
                Image(systemName: failed ? "exclamationmark.triangle.fill" : needsInput ? "ellipsis.bubble.fill" : "checkmark.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(nsColor: failed ? .systemRed : needsInput ? .systemOrange : .systemGreen))
                if count > 1 {
                    Text(verbatim: "\(count)").font(.system(size: 11, weight: .semibold).monospacedDigit()).foregroundStyle(.white.opacity(0.8))
                        .contentTransition(.numericText())
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Threads to look at: \(count)"))
        case .pullNotice(let count, let tone):
            HStack(spacing: 3) {
                Image(systemName: tone.symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(nsColor: tone.color))
                if count > 1 { Text(verbatim: "\(count)").font(.system(size: 11, weight: .semibold)) }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Pull requests to look at: \(count)"))
        case nil:
            EmptyView()
        }
    }
}

/// Apple orange, with a soft glow. Stays until the thread moves on; with more than one thread
/// waiting, how many.
struct AgentDot: View {
    var count = 1
    var glows = true

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Color(nsColor: .systemOrange))
                .frame(width: 9, height: 9)
                .shadow(color: Color(nsColor: .systemOrange).opacity(glows ? 0.8 : 0), radius: glows ? 4 : 0)
            if count > 1 {
                Text(verbatim: "\(count)").font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Color(nsColor: .systemOrange))
                    .contentTransition(.numericText())
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(count > 1 ? Text("\(count) threads are waiting for you") : Text("An agent is waiting for you"))
    }
}

/// What a pull request notice says, most pressing first.
enum PullTone: Equatable {
    case failed, changes, merged

    var symbol: String {
        switch self {
        case .failed: "exclamationmark.circle.fill"
        case .changes: "text.bubble.fill"
        case .merged: "arrow.triangle.merge"
        }
    }

    var color: NSColor {
        switch self {
        case .failed: .systemRed
        case .changes: .systemOrange
        case .merged: .systemPurple
        }
    }
}
