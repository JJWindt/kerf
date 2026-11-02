import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let islands = IslandManager()
    private var hotKeys: [HotKey] = []
    private var signalSources: [DispatchSourceSignal] = []

    func applicationWillTerminate(_ notification: Notification) {
        AgentCenter.shared.stop()
        NowPlayingModule.shared.stop()
        RenderWatcher.shared.stop()
        AudioLevels.shared.stop()
        AppMixer.shared.stopAll()
    }

    /// `kill` and Ctrl-C skip applicationWillTerminate; without this the adapter would outlive Kerf.
    private func stopChildrenOnSignals() {
        for signalNumber in [SIGTERM, SIGINT, SIGHUP] {
            signal(signalNumber, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
            source.setEventHandler {
                MainActor.assumeIsolated {
                    AgentCenter.shared.stop()
                    NowPlayingModule.shared.stop()
                    RenderWatcher.shared.stop()
                    // Taps and their devices go too: the audio daemon may not clean up after us.
                    AudioLevels.shared.stop()
                    AppMixer.shared.stopAll()
                    exit(0)
                }
            }
            source.resume()
            signalSources.append(source)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // First, so a lab run that gets killed takes its taps down too.
        stopChildrenOnSignals()
        if CommandLine.arguments.contains("--lab") {
            // An unknown job must not start a second, real Kerf: it would take the agents' socket.
            guard let lab = Lab(arguments: CommandLine.arguments) else {
                print("Unknown lab job; see Lab.swift.")
                exit(1)
            }
            lab.run()
            return
        }
        islands.start()
        NowPlayingModule.shared.start()
        AgentCenter.shared.start()
        OffloadModule.shared.start()
        AskModule.shared.start()
        ShelfModule.shared.start()
        MediaKeys.shared.startWhenTrusted()
        CalendarModule.shared.start()
        PowerWatcher.shared.start()
        AppMixer.shared.start()
        ClipboardModule.shared.start()
        DownloadsWatcher.shared.start()
        RenderWatcher.shared.start()
        WeatherModule.shared.start()
        hotKeys = [
            HotKey(keyCode: HotKey.space, modifiers: .option) { [weak self] in self?.islands.openAsk(sendingSelection: false) },
            HotKey(keyCode: HotKey.space, modifiers: [.option, .shift]) { [weak self] in self?.islands.openAsk(sendingSelection: true) },
        ]
        LoginItem.registerOnFirstLaunch()
    }
}
