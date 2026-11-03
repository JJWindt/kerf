import ApplicationServices
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") { GeneralSettings() }
            Tab("Agents", systemImage: "sparkles") { AgentSettings() }
        }
        .frame(width: 560)
        .scenePadding()
    }
}

struct GeneralSettings: View {
    @AppStorage(Preferences.showOnExternalDisplays) private var showOnExternalDisplays = false
    @AppStorage(Preferences.hoverOpenDelay) private var hoverOpenDelay = 0.25
    @AppStorage(Preferences.playsSounds) private var playsSounds = true
    @AppStorage(Preferences.closesOnLeave) private var closesOnLeave = true
    @State private var launchAtLogin = LoginItem.isEnabled

    var body: some View {
        Form {
            Toggle("Open at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, on in LoginItem.set(on) }
            Toggle("Show on displays without a notch", isOn: $showOnExternalDisplays)
            Toggle(isOn: $closesOnLeave) {
                Text("Close when the pointer leaves")
                Text("Off: the island stays open until you press Escape or click the notch.")
            }
            LabeledContent("Open after hovering") {
                Picker("Open after hovering", selection: $hoverOpenDelay) {
                    Text("0.25 seconds").tag(0.25)
                    Text("0.5 seconds").tag(0.5)
                    Text("1 second").tag(1.0)
                    Text("1.5 seconds").tag(1.5)
                }
                .labelsHidden()
                .fixedSize()
            }
            Toggle("Play sounds", isOn: $playsSounds)
            AccessibilitySetting()
            LabeledContent("Open the island", value: "⌥ Space")
        }
        .formStyle(.grouped)
    }
}

/// Accessibility lets Escape close the island from any app and keeps the island's wings clear of
/// an app's menus. Everything else works without it.
struct AccessibilitySetting: View {
    @State private var trusted = AXIsProcessTrusted()

    var body: some View {
        if !trusted {
            LabeledContent {
                Button("Allow…") {
                    let prompt = "AXTrustedCheckOptionPrompt"  // kAXTrustedCheckOptionPrompt, which Swift 6 sees as shared state
                    AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary)
                    Task {
                        // Picked up once the switch in System Settings is on.
                        for _ in 0..<60 {
                            try? await Task.sleep(for: .seconds(2))
                            if AXIsProcessTrusted() {
                                trusted = true
                                return
                            }
                        }
                    }
                }
            } label: {
                Text("Accessibility")
                Text("Lets Escape close the island from any app.")
            }
        }
    }
}
