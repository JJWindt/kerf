import KerfKit
import SwiftUI

enum Layout {
    /// The open island's width: the pages are drawn at 80%, the band beside the notch needs this.
    static let openWidth: CGFloat = 380
    /// Taller pages scroll.
    static let maxContentHeight: CGFloat = 320
    /// A waiting question, a permission or an answer gets more room, so it reads in full.
    static let tallContentHeight: CGFloat = 440
}

/// One island's shape and what it shows. Width and height are animated separately, so each axis
/// gets its own spring; content visibility is its own animated value, so leaving content can blur away.
@Observable
final class Island {
    let geometry: IslandGeometry
    private(set) var mode: IslandMode = .idle
    private(set) var width: CGFloat
    private(set) var height: CGFloat
    /// 0 hidden, 1 shown.
    private(set) var compactShown = 0.0
    private(set) var expandedShown = 0.0
    /// The page's own fade, for switching pages while open.
    private(set) var pageShown = 1.0
    /// The open content is only in the view tree while it can be seen, so nothing in it ticks when closed.
    private(set) var expandedMounted = false
    private(set) var isHovered = false
    private(set) var presentation: CompactPresentation?
    /// Threads waiting on you, for the orange dot.
    private(set) var waitingCount = 0
    var showsAgentDot: Bool { waitingCount > 0 }
    private(set) var page: IslandPage = .home
    var pages: [IslandPage] = [.home]
    /// Each page's height as last laid out; until then its estimate.
    private var measuredHeights: [IslandPage: CGFloat] = [:]
    @ObservationIgnored var onTap: (() -> Void)?
    @ObservationIgnored var onClose: (() -> Void)?
    @ObservationIgnored private var swapGeneration = 0

    init(style: IslandStyle) {
        geometry = IslandGeometry(style: style)
        width = geometry.idle.width
        height = geometry.idle.height
    }

    /// Free room beside the notch, from the menu bar. Infinite until known and on other displays.
    private(set) var menuRoom: CGFloat = .infinity

    /// What shows beside the notch: the presentation when it fits next to the app's menus. The
    /// rest waits for room, or a hover.
    var fittingPresentation: CompactPresentation? {
        guard let presentation else { return nil }
        return presentation.showsOverMenus || MenuBarRoom.fits(wings: IslandGeometry.wing, in: menuRoom) ? presentation : nil
    }

    var restingMode: IslandMode { fittingPresentation != nil || showsAgentDot ? .compact : .idle }

    func setMenuRoom(_ room: CGFloat) {
        guard room != menuRoom else { return }
        menuRoom = room
        settle()
    }

    func size(of mode: IslandMode) -> CGSize {
        var size = switch mode {
        case .idle: geometry.idle
        case .compact: geometry.compact()
        case .expanded: CGSize(width: Layout.openWidth, height: geometry.style.bandHeight + contentHeight)
        }
        let floatingIdle = mode == .idle && geometry.style == .floating
        if isHovered, mode != .expanded, !floatingIdle {
            size.width += IslandGeometry.hoverLift.width
            size.height += IslandGeometry.hoverLift.height
        }
        return size
    }

    func go(_ next: IslandMode) {
        guard next != mode else { return }
        let previous = mode
        let springs = Motion.springs(from: previous, to: next)
        mode = next
        if next == .expanded {
            isHovered = false
            expandedMounted = true
            pageShown = 1
        }
        // Asked fresh each time: the open page may measure itself while the width starts moving.
        withAnimation(springs.width) { width = size(of: next).width }
        withAnimation(springs.height) { height = size(of: next).height }
        withAnimation(Motion.fadeOut(from: previous)) {
            if next != .compact { compactShown = 0 }
        }
        if next != .expanded {
            withAnimation(Motion.fadeOut(from: previous), completionCriteria: .removed) {
                expandedShown = 0
            } completion: { [weak self] in
                guard let self, mode != .expanded else { return }
                expandedMounted = false
            }
        }
        // A level answers a key press: no waiting for the shape.
        let quick = if case .level = presentation { true } else { false }
        guard let fadeIn = quick && next == .compact ? .smooth(duration: 0.1) : Motion.fadeIn(to: next, from: previous) else { return }
        withAnimation(fadeIn) {
            if next == .compact { compactShown = 1 }
            if next == .expanded { expandedShown = 1 }
        }
    }

    /// Back to where the island rests, unless it is open.
    func settle() {
        guard mode != .expanded else { return }
        if mode == restingMode { resize(.spring(Motion.appear)) } else { go(restingMode) }
    }

    func setHovered(_ hovered: Bool) {
        guard hovered != isHovered, mode != .expanded else { return }
        isHovered = hovered
        resize(.spring(Motion.hover))
    }

    /// New compact content. Same kind updates in place; another kind fades out, swaps and fades in.
    func show(_ new: CompactPresentation?, waiting: Int) {
        let kindChanged = new?.kind != presentation?.kind
        guard kindChanged || new != presentation || waiting != waitingCount else { return }
        // Something new for you: one more thread waiting, or one more thread with a notice.
        if waiting > waitingCount || !kindChanged && (new?.noticeCount ?? 0) > (presentation?.noticeCount ?? 0) { bump() }
        guard kindChanged, mode == .compact, compactShown > 0 else {
            presentation = new
            withAnimation(.smooth(duration: 0.25)) { waitingCount = waiting }
            settle()
            return
        }
        swapGeneration += 1
        let generation = swapGeneration
        withAnimation(.easeOut(duration: 0.1)) { compactShown = 0 }
        Task {
            try? await Task.sleep(for: .seconds(0.1))
            guard generation == swapGeneration else { return }
            presentation = new
            waitingCount = waiting
            guard mode == .compact else { return }
            if restingMode == .idle {
                go(.idle)
            } else {
                resize(.spring(Motion.appear))
                withAnimation(.smooth(duration: 0.2)) { compactShown = 1 }
            }
        }
    }

    /// Switches pages while open: the page fades, the island takes the new page's height.
    func select(_ next: IslandPage) {
        guard next != page else { return }
        guard mode == .expanded else {
            page = next
            return
        }
        swapGeneration += 1
        let generation = swapGeneration
        withAnimation(.easeOut(duration: 0.08)) { pageShown = 0 }
        Task {
            try? await Task.sleep(for: .seconds(0.08))
            guard generation == swapGeneration else { return }
            page = next
            resize(.spring(Motion.expand))
            withAnimation(.smooth(duration: 0.22)) { pageShown = 1 }
        }
    }

    /// The open page's height: all of it, up to the cap.
    var contentHeight: CGFloat {
        min(measuredHeights[page] ?? ui(page.contentHeight), page.maxContentHeight)
    }

    /// The open page is taller than the island gets.
    var contentScrolls: Bool { (measuredHeights[page] ?? 0) > page.maxContentHeight }

    /// A page laid itself out: the island takes its height, growing or shrinking with it.
    func setContentHeight(_ height: CGFloat, for page: IslandPage) {
        guard abs((measuredHeights[page] ?? -1) - height) > 0.5 else { return }
        measuredHeights[page] = height
        // After this layout pass, not inside it: a resize that set off the measuring would
        // otherwise put its older height back over this one.
        if page == self.page { Task { self.refit() } }
    }

    /// Open: follow the page's height when its content changes.
    func refit() {
        guard mode == .expanded else { return }
        let target = size(of: .expanded)
        guard abs(target.height - height) > 0.5 || abs(target.width - width) > 0.5 else { return }
        resize(.spring(Motion.expand))
    }

    /// One small bump, like an iPhone Live Activity update.
    func bump() {
        guard mode != .expanded, !Motion.reduceMotion else { return }
        let rest = size(of: mode == .idle ? .compact : mode)
        withAnimation(.spring(Motion.bump)) {
            width = rest.width + 12
            height = rest.height + 3
        }
        Task {
            try? await Task.sleep(for: .seconds(0.12))
            resize(.spring(Motion.bump))
        }
    }

    private func resize(_ animation: Animation) {
        // Asked fresh for each axis, like `go`: setting the width can lay out a page that just
        // came in, and the height it measures must win over the estimate from before.
        withAnimation(animation) { width = size(of: mode).width }
        withAnimation(animation) { height = size(of: mode).height }
    }
}
