import KerfKit
import SwiftUI

/// The open island's pages. Their icons sit in the band beside the notch.
enum IslandPage: String, CaseIterable, Identifiable {
    case agents, ask

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .agents: "apple.intelligence"
        case .ask: "sparkle.magnifyingglass"
        }
    }

    var title: LocalizedStringResource {
        switch self {
        case .agents: "AI"
        case .ask: "Ask"
        }
    }

    /// How tall the page gets before it scrolls: a waiting question and an answer get more room.
    var maxContentHeight: CGFloat {
        switch self {
        case .agents where !AgentCenter.shared.requests.isEmpty: Layout.tallContentHeight
        case .ask where AskModule.shared.isRunning || !AskModule.shared.answer.isEmpty: Layout.tallContentHeight
        default: Layout.maxContentHeight
        }
    }

    /// Height below the band.
    var contentHeight: CGFloat {
        switch self {
        case .agents: AgentsPage.contentHeight
        case .ask: AskPage.contentHeight
        }
    }
}

struct PageView: View {
    let page: IslandPage

    var body: some View {
        switch page {
        case .agents: AgentsPage()
        case .ask: AskPage()
        }
    }
}

/// The page icons, split over both sides of the notch like the iPhone's leading and trailing views.
struct TabBand: View {
    let island: Island

    var body: some View {
        let pages = island.pages
        let half = (pages.count + 1) / 2
        HStack(spacing: 0) {
            tabs(Array(pages.prefix(half))).frame(maxWidth: .infinity)
            // Clicking the notch closes the island again.
            Color.clear.frame(width: island.geometry.style.centerWidth)
                .contentShape(Rectangle())
                .onTapGesture { island.onClose?() }
            tabs(Array(pages.dropFirst(half))).frame(maxWidth: .infinity)
        }
        .opacity(pages.count > 1 ? 1 : 0)
    }

    private func isSelected(_ page: IslandPage) -> Bool {
        page == island.page
    }

    private func tabs(_ pages: [IslandPage]) -> some View {
        // Four icons must fit beside the notch: 4 × 17 + 3 × 5 = 83 pt of 97.
        HStack(spacing: 5) {
            ForEach(pages) { page in
                Button {
                    island.select(page)
                } label: {
                    Image(systemName: page.symbol)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(isSelected(page) ? 1 : 0.45))
                        .frame(width: 17, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(page.title))
            }
        }
    }
}
