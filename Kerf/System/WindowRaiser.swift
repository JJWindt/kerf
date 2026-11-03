import AppKit
import ApplicationServices

/// Brings one window of an app to the front by its title, through Accessibility. Without that
/// permission the app just comes forward with whatever window it had.
enum WindowRaiser {
    /// Tries for a second: an app that was closed needs a moment to show its windows.
    static func raise(appAt path: String, where matches: @escaping (String) -> Bool) {
        guard AXIsProcessTrusted() else { return }
        Task {
            for _ in 0..<10 {
                if let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleURL?.path == path }),
                   raiseWindow(of: app.processIdentifier, where: matches) {
                    return
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    private static func raiseWindow(of pid: pid_t, where matches: (String) -> Bool) -> Bool {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.25)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return false }
        for window in windows {
            var title: CFTypeRef?
            guard AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &title) == .success,
                  let title = title as? String, matches(title) else { continue }
            AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
            AXUIElementPerformAction(window, kAXRaiseAction as CFString)
            return true
        }
        return false
    }
}
