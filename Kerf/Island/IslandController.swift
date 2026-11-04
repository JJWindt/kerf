import AppKit
import KerfKit
import SwiftUI

/// One island on one screen: its panel, hovering, opening and closing.
final class IslandController {
    let island: Island
    let panel: IslandPanel
    let screen: NSScreen
    private var monitors: [Any] = []
    private var hoverTask: Task<Void, Never>?
    private var closeTask: Task<Void, Never>?
    /// Only used when "close when the pointer leaves" is on: opened on purpose (a click, ⌥ Space,
    /// a click inside) still stays.
    private(set) var pinned = false

    /// Big enough for the open island at its tallest, and its shadow.
    static let panelSize = CGSize(width: Layout.openWidth + 140, height: 32 + Layout.tallContentHeight + 60)

    init(screen: NSScreen, interactive: Bool = true) {
        self.screen = screen
        island = Island(style: screen.islandStyle)
        let size = Self.panelSize
        let frame = screen.frame
        panel = IslandPanel(frame: NSRect(x: frame.midX - size.width / 2, y: frame.maxY - size.height, width: size.width, height: size.height))
        let host = ClickThroughHostingView(rootView: IslandRoot(island: island))
        host.sizingOptions = []
        host.frame = NSRect(origin: .zero, size: size)
        panel.contentView = host
        // Always dark, like the island itself: text fields get white text.
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.ignoresMouseEvents = true
        panel.onCancel = { [weak self] in self?.close() }
        panel.wantsKeyboard = { [weak self] in
            guard let island = self?.island else { return false }
            // Open, a click in a text field may take the keyboard; hovering never does.
            return island.mode == .expanded
        }
        island.onTap = { [weak self] in
            guard let self, island.mode != .expanded else { return }
            // A thread's notice goes straight to its chat, like tapping a notification.
            if AgentCenter.shared.requests.isEmpty, !Hub.shared.agentWaiting,
               case .agentNotice = Hub.shared.presentation, let newest = AgentCenter.shared.notices.first {
                hoverTask?.cancel()
                hoverTask = nil
                AgentCenter.shared.open(newest)
                return
            }
            open(pinned: true)
        }
        island.onClose = { [weak self] in self?.close() }
        if interactive { watchPointer() }
    }

    /// Hidden while an app is full screen on this display.
    private(set) var isHiddenForFullScreen = false

    func show() {
        guard !isHiddenForFullScreen else { return }
        panel.orderFrontRegardless()
    }

    func setHiddenForFullScreen(_ hidden: Bool) {
        guard hidden != isHiddenForFullScreen else { return }
        isHiddenForFullScreen = hidden
        if hidden {
            if island.mode == .expanded { close() }
            panel.orderOut(nil)
        } else {
            panel.orderFrontRegardless()
        }
    }

    func remove() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        panel.orderOut(nil)
    }

    /// Follows the hub: compact content, the agent dot, the page list.
    func apply(_ hub: Hub) {
        if island.pages != hub.pages { island.pages = hub.pages }
        if !hub.pages.contains(island.page), let first = hub.pages.first { island.select(first) }
        island.show(hub.presentation, waiting: hub.waitingCount)
        // The open page may need another height now.
        island.refit()
    }

    func open(page: IslandPage? = nil, keyboard: Bool = false, pinned: Bool = false) {
        hoverTask?.cancel()
        hoverTask = nil
        // Only the keyboard keeps it open after the pointer leaves: you are typing in it.
        self.pinned = self.pinned || keyboard
        if island.mode != .expanded { AgentCenter.shared.navigation.openOldest() }
        // A waiting agent or a thread's notice comes first; otherwise the AI page, every time.
        island.select(page ?? Hub.shared.attentionPage ?? .agents)
        island.go(.expanded)
        panel.ignoresMouseEvents = false
        if keyboard {
            panel.acceptsKeyboard = true
            panel.makeKeyAndOrderFront(nil)
        }
    }

    func close() {
        closeTask?.cancel()
        closeTask = nil
        pinned = false
        island.go(island.restingMode)
        if panel.isKeyWindow || panel.acceptsKeyboard {
            panel.acceptsKeyboard = false
            // Hand the keyboard back to the app underneath.
            panel.orderOut(nil)
            panel.orderFrontRegardless()
        }
    }

    // MARK: Pointer

    private func watchPointer() {
        let moved: (NSEvent) -> Void = { [weak self] _ in self?.pointerMoved() }
        let kinds: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: kinds, handler: moved) { monitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: kinds, handler: { moved($0); return $0 }) { monitors.append(local) }
        // Escape closes the open island from any app (needs Accessibility).
        if let escape = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            guard let self, event.keyCode == 53, island.mode == .expanded else { return }
            close()
        }) { monitors.append(escape) }
    }

    /// A text field in the island is being edited.
    private var isTyping: Bool {
        panel.isKeyWindow && panel.firstResponder is NSTextView
    }

    /// The area that counts as "on the island", in screen coordinates.
    private var hotZone: NSRect {
        var size = island.size(of: island.mode)
        if island.mode == .idle, island.geometry.style == .floating { size = CGSize(width: 200, height: 8) }
        let top = screen.frame.maxY - (island.geometry.style == .floating ? IslandGeometry.floatingTop : 0)
        // Up to 12 pt of air on each side, less where an app's menus come close.
        let wings = max(0, (size.width - island.geometry.idle.width) / 2)
        let air = min(12, max(0, island.menuRoom - wings - 2))
        return NSRect(x: screen.frame.midX - size.width / 2 - air, y: top - size.height - 10, width: size.width + 2 * air, height: size.height + 10)
    }

    /// Hover lifts the island at once and opens it after resting there; away closes it.
    private func pointerMoved() {
        guard !isHiddenForFullScreen else { return }
        let inside = hotZone.contains(NSEvent.mouseLocation)
        // Only touch the window server when something changes; this runs on every mouse move.
        if !panel.acceptsKeyboard, panel.ignoresMouseEvents == inside { panel.ignoresMouseEvents = !inside }
        if inside {
            closeTask?.cancel()
            closeTask = nil
            guard island.mode != .expanded else { return }
            island.setHovered(true)
            guard hoverTask == nil else { return }
            let delay = UserDefaults.standard.double(forKey: Preferences.hoverOpenDelay)
            hoverTask = Task {
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
                hoverTask = nil
                open()
            }
        } else {
            hoverTask?.cancel()
            hoverTask = nil
            island.setHovered(false)
            // Leaving the notch makes the island small again, also after clicking in it. It stays
            // while you type in it, or when you switched this off.
            guard island.mode == .expanded, closeTask == nil, !pinned, UserDefaults.standard.bool(forKey: Preferences.closesOnLeave),
                  !isTyping else { return }
            closeTask = Task {
                try? await Task.sleep(for: .seconds(0.4))
                guard !Task.isCancelled else { return }
                closeTask = nil
                close()
            }
        }
    }
}
