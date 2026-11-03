import AppKit
import ApplicationServices
import KerfKit
import SwiftUI

/// Claude Code, Codex, T3 Code and anything using `kerf notify`: their sessions, and the
/// questions waiting for you. Only those questions leave a dot in the notch.
@Observable
final class AgentCenter {
    static let shared = AgentCenter()

    struct Session: Identifiable, Equatable {
        enum State {
            case working, waiting, idle
        }

        let id: String
        var agent: AgentKind
        var name: String
        var hostPath: String?
        var project: String?
        var state: State {
            didSet { if state != oldValue { stateSince = .now } }
        }
        var updated: Date
        var lastMessage: String?
        /// The first thing you asked in this thread.
        var title: String?
        /// Finished since you last looked.
        var unread = false
        /// Asks for you in its own window; unread too.
        var needsInput = false
        /// Found running without a hook having said so; the next hook event takes over.
        var foundByScan = false
        /// The agent's own session id, for finding its chat in P3 or T3 Code.
        var nativeID: String?
        /// Since when it works, waits or is done.
        var stateSince = Date.now
    }

    struct Request: Identifiable {
        let id = UUID()
        let sessionID: String
        let agent: AgentKind
        let name: String
        let hostPath: String?
        let project: String?
        let cwd: String?
        let event: AgentEvent
        let connection: UnixSocketServer.Connection?
    }

    private(set) var sessions: [Session] = []
    private(set) var requests: [Request] = []
    @ObservationIgnored private var server: UnixSocketServer?

    static let showsDoneKey = "agents.showsDone"

    func start() {
        let files = FileManager.default
        try? files.createDirectory(at: KerfPaths.commandLink.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Hooks call a stable path; point it at this copy of the app.
        if let executable = Bundle.main.executablePath {
            try? files.removeItem(at: KerfPaths.commandLink)
            try? files.createSymbolicLink(atPath: KerfPaths.commandLink.path, withDestinationPath: executable)
        }
        server = try? UnixSocketServer(path: KerfPaths.socket) { line, connection in
            Task { @MainActor in AgentCenter.shared.receive(line, connection) }
        }
        findRunning()
    }

    /// Threads already busy before Kerf heard of them: started before Kerf, or while it restarted.
    /// At launch and when the AI page opens; hooks tell the rest.
    func findRunning() {
        Task.detached(priority: .utility) {
            let found = RunningThreads.claudeCode()
            await MainActor.run { AgentCenter.shared.merge(found) }
        }
    }

    private func merge(_ found: [RunningThreads.Found]) {
        var next = sessions
        let ids = Set(found.map { "\(AgentKind.claudeCode.rawValue)..\($0.sessionID)" })
        // A guess whose turn ended without a hook (Kerf missed it) goes again.
        next.removeAll { $0.foundByScan && !ids.contains($0.id) }
        for thread in found {
            let id = "\(AgentKind.claudeCode.rawValue)..\(thread.sessionID)"
            guard !next.contains(where: { $0.id == id }) else { continue }
            var session = Session(id: id, agent: .claudeCode, name: AgentKind.claudeCode.displayName, hostPath: thread.hostPath,
                                  project: ProjectName.of(thread.cwd), state: .working, updated: thread.updated, title: thread.title)
            session.foundByScan = true
            session.nativeID = thread.sessionID
            session.stateSince = thread.updated
            next.append(session)
        }
        next.sort { $0.updated > $1.updated }
        guard next != sessions else { return }
        sessions = next
        Hub.shared.refresh()
    }

    func stop() {
        server?.stop()
        server = nil
    }

    private func receive(_ line: Data, _ connection: UnixSocketServer.Connection) {
        guard let envelope = try? JSONDecoder().decode(AgentEnvelope.self, from: line) else {
            connection.reply(nil)
            return
        }
        handle(envelope, connection: connection)
    }

    func handle(_ envelope: AgentEnvelope, connection: UnixSocketServer.Connection?) {
        let payload = envelope.payload
        if payload["hook_event_name"]?.string == "KerfDebug" {
            let music = NowPlayingModule.shared
            let report: JSONValue = .object([
                "nowPlaying": music.state.map { .string("\($0.title) [\($0.isPlaying ? "playing" : "paused")] \($0.sourceBundleID)") } ?? .null,
                "musicUpdated": music.lastUpdate.map { .string($0.formatted(.iso8601)) } ?? .null,
                "compact": .string(Hub.shared.presentation.map { $0.kind } ?? "none"),
                "pages": .string(Hub.shared.pages.map(\.rawValue).joined(separator: ",")),
                "more": .string(Hub.shared.morePages.map(\.rawValue).joined(separator: ",")),
                "threads": .number(Double(visibleThreads.count)),
                "accessibility": .bool(AXIsProcessTrusted()),
                "mediaKeys": .bool(MediaKeys.shared.isRunning),
                "mixer": .string(AppMixer.shared.channels.map { "\($0.name) \(Int($0.gain * 100))%\($0.isPlaying ? " playing" : "")" }.joined(separator: ", ")),
                "waiting": .number(Double(requests.count)),
            ])
            connection?.reply(report.encoded())
            return
        }
        // `kerf answer`: answer the first waiting question from a script.
        if payload["hook_event_name"]?.string == "KerfAnswer" {
            connection?.reply(nil)
            if let request = requests.first, let decision = payload["decision"]?.string.flatMap(AgentReply.Decision.init) {
                answer(request, AgentReply(decision: decision))
            }
            return
        }
        let event = AgentEvent(payload)
        let name = envelope.name ?? envelope.agent.displayName
        let sessionID = "\(envelope.agent.rawValue).\(envelope.name ?? "").\(payload.sessionID)"
        let isNew = !sessions.contains { $0.id == sessionID }
        var session = sessions.first { $0.id == sessionID }
            ?? Session(id: sessionID, agent: envelope.agent, name: name, hostPath: envelope.host, project: payload.project, state: .idle, updated: .now)
        session.updated = .now
        session.foundByScan = false
        if !payload.sessionID.isEmpty { session.nativeID = payload.sessionID }
        session.project = payload.project ?? session.project
        session.hostPath = envelope.host ?? session.hostPath
        // A thread Kerf joins halfway gets its title from the transcript.
        if isNew, session.title == nil, let transcript = payload.transcriptPath { loadTitle(sessionID, from: transcript) }

        switch event {
        case .permission, .question:
            let request = Request(sessionID: sessionID, agent: envelope.agent, name: name, hostPath: session.hostPath,
                                  project: session.project, cwd: payload.workingDirectory, event: event, connection: connection)
            requests.append(request)
            connection?.onClose = { [id = request.id] in
                Task { @MainActor in AgentCenter.shared.drop(id) }
            }
            session.state = .waiting
            session.needsInput = false
            Sounds.play(.question)
        case .notification(let type, _):
            connection?.reply(nil)
            if envelope.agent == .other {
                Hub.shared.flash(.banner(.agent(envelope.agent), .symbol("bell.fill", Color(nsColor: .systemOrange))))
            } else if type == "elicitation_dialog" || type == "agent_needs_input" {
                // Stays in the notch until you look or the thread moves on.
                session.needsInput = true
                session.unread = true
            }
        case .stop(let last):
            connection?.reply(nil)
            session.state = .idle
            session.unread = true
            session.needsInput = false
            session.lastMessage = last.map { String($0.prefix(300)) }
            if Self.showsDone { Sounds.play(.done) }
        case .sessionEnd:
            connection?.reply(nil)
            sessions.removeAll { $0.id == sessionID }
            Hub.shared.refresh()
            return
        case .promptSubmitted(let prompt):
            connection?.reply(nil)
            session.state = .working
            session.unread = false
            session.needsInput = false
            if session.title == nil { session.title = prompt.flatMap(ThreadTitle.from) }
        case .sessionStart, .other:
            connection?.reply(nil)
        }
        if let index = sessions.firstIndex(where: { $0.id == sessionID }) {
            sessions[index] = session
        } else {
            sessions.append(session)
        }
        // Newest first, nothing older than a day.
        sessions = sessions.filter { $0.updated > .now.addingTimeInterval(-86_400) }.sorted { $0.updated > $1.updated }
        Hub.shared.refresh()
    }

    func answer(_ request: Request, _ reply: AgentReply) {
        if let data = try? JSONEncoder().encode(reply) {
            request.connection?.onClose = nil
            request.connection?.reply(data)
        }
        requests.removeAll { $0.id == request.id }
        if let index = sessions.firstIndex(where: { $0.id == request.sessionID }) {
            sessions[index].state = reply.decision == .deny ? .idle : .working
        }
        Hub.shared.refresh()
        if requests.isEmpty { IslandManager.current?.closeAgents() }
    }

    /// What the AI page lists: threads that run, wait, or finished since you last looked.
    var visibleThreads: [Session] {
        sessions.filter { $0.state != .idle || $0.unread }
    }

    static var showsDone: Bool { UserDefaults.standard.object(forKey: showsDoneKey) as? Bool ?? true }

    /// What stays in the notch until you click it or the thread moves on: threads that finished
    /// or ask for him in their own window. Newest first.
    var notices: [Session] {
        let showsDone = Self.showsDone
        return sessions.filter { $0.unread && ($0.needsInput || showsDone) }
    }

    /// Seen: the thread leaves the list, and its notice leaves the notch.
    func markRead(_ id: String) {
        guard let index = sessions.firstIndex(where: { $0.id == id }), sessions[index].unread else { return }
        sessions[index].unread = false
        sessions[index].needsInput = false
        Hub.shared.refresh()
    }

    /// The thread's own chat: in P3 or T3 Code the chat itself, elsewhere the app it runs in.
    func open(_ session: Session) {
        markRead(session.id)
        guard let host = session.hostPath else { return }
        let native = session.nativeID
        Task.detached(priority: .userInitiated) {
            let link = native.flatMap { CodeThreadLink.url(hostPath: host, sessionID: $0) }
            await MainActor.run {
                let app = URL(fileURLWithPath: host)
                let configuration = NSWorkspace.OpenConfiguration()
                // Straight to that app: T3 Code would take the link otherwise, it has the same scheme.
                if let link {
                    NSWorkspace.shared.open([link], withApplicationAt: app, configuration: configuration)
                } else {
                    NSWorkspace.shared.openApplication(at: app, configuration: configuration)
                }
            }
        }
    }

    private func loadTitle(_ sessionID: String, from path: String) {
        Task.detached(priority: .utility) {
            guard let handle = FileHandle(forReadingAtPath: path) else { return }
            let head = handle.readData(ofLength: 256 * 1024)
            try? handle.close()
            guard let title = ThreadTitle.fromTranscript(head) else { return }
            await MainActor.run {
                guard let index = AgentCenter.shared.sessions.firstIndex(where: { $0.id == sessionID }),
                      AgentCenter.shared.sessions[index].title == nil else { return }
                AgentCenter.shared.sessions[index].title = title
            }
        }
    }

    /// The tool stopped waiting: answered in its own window, or timed out.
    private func drop(_ id: UUID) {
        guard requests.contains(where: { $0.id == id }) else { return }
        requests.removeAll { $0.id == id }
        Hub.shared.refresh()
    }

    /// Lab only.
    func preview(_ request: Request?, sessions: [Session]) {
        requests = request.map { [$0] } ?? []
        self.sessions = sessions
        Hub.shared.refresh()
    }
}

/// Soft system sounds, and only if you want sounds.
enum Sounds {
    enum Kind {
        case question, done
    }

    static func play(_ kind: Kind) {
        guard UserDefaults.standard.bool(forKey: Preferences.playsSounds) else { return }
        let sound = NSSound(named: kind == .question ? "Tink" : "Pop")
        sound?.volume = kind == .question ? 0.35 : 0.25
        sound?.play()
    }
}
