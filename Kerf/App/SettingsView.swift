import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") { GeneralSettings() }
            Tab("Agents", systemImage: "sparkles") { AgentSettings() }
            Tab("Offload", systemImage: "sdcard") { OffloadSettings() }
            Tab("Pages", systemImage: "square.grid.2x2") { PageSettings() }
        }
        .frame(width: 560)
        .scenePadding()
    }
}

struct GeneralSettings: View {
    @AppStorage(Preferences.showOnExternalDisplays) private var showOnExternalDisplays = true
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
            HUDSetting()
            LabeledContent("Open the island", value: "⌥ Space")
            LabeledContent("Ask Claude about the selection", value: "⌥⇧ Space")
        }
        .formStyle(.grouped)
    }
}

/// Volume and brightness in the notch instead of macOS's own bar. Needs Accessibility.
struct HUDSetting: View {
    @AppStorage(MediaKeys.enabledKey) private var replaces = true
    @State private var trusted = SelectionReader.isTrusted

    var body: some View {
        Toggle(isOn: $replaces) {
            Text("Show volume and brightness in the notch")
            if !trusted {
                Text("Needs Accessibility, also used for asking Claude about selected text.")
            }
        }
        .onChange(of: replaces) { _, on in
            if on { MediaKeys.shared.start() } else { MediaKeys.shared.stop() }
        }
        if !trusted {
            Button("Allow Accessibility…") {
                SelectionReader.requestTrust()
                Task {
                    // Picked up once the switch in System Settings is on.
                    for _ in 0..<60 {
                        try? await Task.sleep(for: .seconds(2))
                        if SelectionReader.isTrusted {
                            trusted = true
                            MediaKeys.shared.start()
                            return
                        }
                    }
                }
            }
        }
    }
}

/// Which pages the open island has, and the extras that need a permission first.
struct PageSettings: View {
    @State private var bluetooth = IOBluetoothWatcher.shared.isAllowed

    var body: some View {
        Form {
            Section {
                ForEach(IslandPage.placeable) { page in
                    Picker(selection: Binding(
                        get: { page.placement },
                        set: {
                            page.placement = $0
                            Hub.shared.refresh()
                        }
                    )) {
                        ForEach(PagePlacement.allCases, id: \.self) { Text($0.title).tag($0) }
                    } label: {
                        Label { Text(page.title) } icon: { Image(systemName: page.symbol) }
                    }
                }
            } header: {
                Text("Pages")
            } footer: {
                Text("Four icons fit on each side of the notch. The rest goes under …")
            }
            Section("Downloads") {
                Toggle("Show downloads in the notch", isOn: Binding(
                    get: { UserDefaults.standard.bool(forKey: DownloadsWatcher.enabledKey) },
                    set: { on in
                        UserDefaults.standard.set(on, forKey: DownloadsWatcher.enabledKey)
                        if on { DownloadsWatcher.shared.start() } else { DownloadsWatcher.shared.stop() }
                    }
                ))
            }
            Section("AirPods") {
                if bluetooth {
                    Toggle("Show AirPods when they connect", isOn: Binding(
                        get: { UserDefaults.standard.object(forKey: IOBluetoothWatcher.enabledKey) as? Bool ?? true },
                        set: { UserDefaults.standard.set($0, forKey: IOBluetoothWatcher.enabledKey) }
                    ))
                } else {
                    Button("Show AirPods when they connect…") {
                        IOBluetoothWatcher.shared.requestAccess()
                        Task {
                            try? await Task.sleep(for: .seconds(5))
                            bluetooth = IOBluetoothWatcher.shared.isAllowed
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}
