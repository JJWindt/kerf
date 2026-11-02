import Foundation
import ServiceManagement

enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("Kerf: login item: \(error.localizedDescription)")
        }
    }

    /// Kerf opens at login by default. Only from /Applications, so a debug build never registers.
    static func registerOnFirstLaunch() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Preferences.didRegisterLoginItem),
              Bundle.main.bundlePath.hasPrefix("/Applications/") else { return }
        set(true)
        defaults.set(true, forKey: Preferences.didRegisterLoginItem)
    }
}
