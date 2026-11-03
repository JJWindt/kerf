import AppKit
import KerfKit

/// An island on the notched display, and a floating one on each other display if wanted.
final class IslandManager {
    /// The running manager, for modules that need to close an island.
    static weak var current: IslandManager?
    private var controllers: [CGDirectDisplayID: IslandController] = [:]
    private var screenObserver: NSObjectProtocol?
    private var defaultsObserver: NSObjectProtocol?
    private var fullScreenObservers: [NSObjectProtocol] = []
    private var scanTask: Task<Void, Never>?
    /// The frontmost app's menu titles from the last look.
    private var menuItems: [CGRect] = []

    func start() {
        Self.current = self
        Preferences.register()
        Hub.shared.observe { [weak self] in self?.applyHub() }
        rebuild()
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuild() }
        }
        defaultsObserver = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuildIfDisplaysChanged() }
        }
        // Switching spaces or apps may enter or leave full screen; the space animation takes a moment.
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification] {
            fullScreenObservers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.checkFullScreenSoon() }
            })
        }
    }

    private var wantedScreens: [NSScreen] {
        let external = UserDefaults.standard.bool(forKey: Preferences.showOnExternalDisplays)
        return NSScreen.screens.filter { $0.notchSize != nil || external }
    }

    private func rebuildIfDisplaysChanged() {
        if Set(wantedScreens.map(\.displayID)) != Set(controllers.keys) { rebuild() }
    }

    private func rebuild() {
        controllers.values.forEach { $0.remove() }
        controllers = [:]
        for screen in wantedScreens {
            let controller = IslandController(screen: screen)
            controller.apply(Hub.shared)
            controller.show()
            controllers[screen.displayID] = controller
        }
        checkFullScreenSoon()
    }

    private func checkFullScreenSoon() {
        scanTask?.cancel()
        scanTask = Task {
            // Menus are there at once; full screen takes the space animation to settle.
            for (delay, menus) in [(0.15, true), (0.6, false), (1.2, true)] {
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
                let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
                let scan = await Task.detached(priority: .utility) { MenuBarScan(front: front, readMenus: menus) }.value
                guard !Task.isCancelled else { return }
                apply(scan, front: front)
            }
        }
    }

    /// An island hides while the app in front fills its display: a full-screen window, sized to
    /// the whole display or to everything below the notch. Its wings keep clear of the menus.
    private func apply(_ scan: MenuBarScan, front: pid_t?) {
        if let items = scan.menuItems { menuItems = items }
        let frames = scan.windows.filter { $0.pid == front && $0.layer == 0 }.map(\.bounds)
        for controller in controllers.values {
            let display = CGDisplayBounds(controller.screen.displayID)
            let notch = controller.screen.safeAreaInsets.top
            let fills = frames.contains { frame in
                frame.minX <= display.minX + 1 && frame.width >= display.width - 1
                    && frame.maxY >= display.maxY - 1 && frame.minY <= display.minY + notch + 1
            }
            controller.setHiddenForFullScreen(fills)
            if let range = controller.screen.notchRange {
                let items = menuItems.filter { abs($0.minY - display.minY) < 2 } + scan.statusItems(on: display)
                controller.island.setMenuRoom(MenuBarRoom.free(notchMinX: range.lowerBound, notchMaxX: range.upperBound, items: items))
            }
        }
    }

    private func applyHub() {
        controllers.values.forEach { $0.apply(Hub.shared) }
    }

    /// The island on the screen under the pointer, else the notched one.
    private var currentController: IslandController? {
        let mouse = NSEvent.mouseLocation
        return controllers.values.first { $0.screen.frame.contains(mouse) }
            ?? controllers.values.first { $0.screen.notchSize != nil }
            ?? controllers.values.first
    }

    /// After the last agent question is answered, islands open on it close.
    func closeAgents() {
        controllers.values.filter { $0.island.mode == .expanded && $0.island.page == .agents }.forEach { $0.close() }
    }

    /// ⌥ Space opens the ask field, or closes it again.
    func openAsk() {
        guard let controller = currentController else { return }
        if controller.island.mode == .expanded, controller.island.page == .ask {
            controller.close()
            return
        }
        controller.open(page: .ask, keyboard: true)
    }

    func closeAll() {
        controllers.values.filter { $0.island.mode == .expanded }.forEach { $0.close() }
    }

    /// Open islands follow their page's height.
    func refit() {
        controllers.values.forEach { $0.island.refit() }
    }
}
