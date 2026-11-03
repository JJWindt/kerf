import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let islands = IslandManager()
    private var hotKeys: [HotKey] = []
    private var signalSources: [DispatchSourceSignal] = []

    func applicationWillTerminate(_ notification: Notification) {
        AgentCenter.shared.stop()
    }

    /// `kill` and Ctrl-C skip applicationWillTerminate; without this the socket would stay behind.
    private func stopOnSignals() {
        for signalNumber in [SIGTERM, SIGINT, SIGHUP] {
            signal(signalNumber, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
            source.setEventHandler {
                MainActor.assumeIsolated {
                    AgentCenter.shared.stop()
                    exit(0)
                }
            }
            source.resume()
            signalSources.append(source)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        stopOnSignals()
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
        AgentCenter.shared.start()
        AskModule.shared.start()
        hotKeys = [
            HotKey(keyCode: HotKey.space, modifiers: .option) { [weak self] in self?.islands.openAsk() },
        ]
        LoginItem.registerOnFirstLaunch()
    }
}
