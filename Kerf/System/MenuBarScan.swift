import AppKit
import ApplicationServices

/// One look at the screens for the island: which windows are where (for full screen) and where
/// the frontmost app's menus and the status items sit (so wings don't cover them). Runs off the
/// main thread: asking another app through Accessibility can take a moment.
nonisolated struct MenuBarScan: Sendable {
    struct Window: Sendable {
        let pid: pid_t
        let layer: Int
        let bounds: CGRect
    }

    let windows: [Window]
    /// The frontmost app's menu titles in global screen points, top-left origin; nil when not asked.
    let menuItems: [CGRect]?

    init(front: pid_t?, readMenus: Bool) {
        let info = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]) ?? []
        windows = info.compactMap { window in
            guard let pid = window[kCGWindowOwnerPID as String] as? pid_t, let layer = window[kCGWindowLayer as String] as? Int,
                  let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds) else { return nil }
            return Window(pid: pid, layer: layer, bounds: rect)
        }
        menuItems = readMenus ? front.map(Self.menuTitles) : nil
    }

    /// Menu titles through Accessibility, which Kerf has for the volume keys. Without it: none.
    private static func menuTitles(of pid: pid_t) -> [CGRect] {
        guard AXIsProcessTrusted() else { return [] }
        let app = AXUIElementCreateApplication(pid)
        // A busy app must not hold Kerf up.
        AXUIElementSetMessagingTimeout(app, 0.25)
        guard let bar = element(app, kAXMenuBarAttribute) else { return [] }
        var children: CFTypeRef?
        guard AXUIElementCopyAttributeValue(bar, kAXChildrenAttribute as CFString, &children) == .success,
              let items = children as? [AXUIElement] else { return [] }
        return items.compactMap { item in
            var values: CFArray?
            guard AXUIElementCopyMultipleAttributeValues(item, [kAXPositionAttribute, kAXSizeAttribute] as CFArray, [], &values) == .success,
                  let pair = values as? [AnyObject], pair.count == 2,
                  CFGetTypeID(pair[0]) == AXValueGetTypeID(), CFGetTypeID(pair[1]) == AXValueGetTypeID() else { return nil }
            var origin = CGPoint.zero
            var size = CGSize.zero
            guard AXValueGetValue(pair[0] as! AXValue, .cgPoint, &origin), AXValueGetValue(pair[1] as! AXValue, .cgSize, &size) else { return nil }
            return CGRect(origin: origin, size: size)
        }
    }

    private static func element(_ parent: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(parent, attribute as CFString, &value) == .success, let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    /// Status items (Wi-Fi, the clock, other apps' icons) on a display's menu bar.
    func statusItems(on display: CGRect) -> [CGRect] {
        windows.filter { $0.layer == Int(CGWindowLevelForKey(.statusWindow)) && abs($0.bounds.minY - display.minY) < 2 }.map(\.bounds)
    }
}
