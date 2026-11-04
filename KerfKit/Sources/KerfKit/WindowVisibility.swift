import CoreGraphics

public enum WindowVisibility {
    /// Whether a window of the app in front is full screen, so the island steps aside. Below a
    /// MacBook notch a maximized window has the same bounds as a full-screen one; Accessibility
    /// tells them apart, and without it the Dock does: a full-screen space doesn't show it.
    public static func hidesIsland(window: CGRect, display: CGRect, notch: CGFloat = 0, isFullScreen: Bool?, dockShown: Bool = true) -> Bool {
        guard display.contains(CGPoint(x: window.midX, y: window.midY)) else { return false }
        if let isFullScreen { return isFullScreen }
        guard window.minX <= display.minX + 1, window.maxX >= display.maxX - 1, window.maxY >= display.maxY - 1 else { return false }
        // Over the menu bar too: full screen whatever the Dock does.
        if window.minY <= display.minY + 1 { return true }
        return !dockShown && window.minY <= display.minY + notch + 1
    }
}
