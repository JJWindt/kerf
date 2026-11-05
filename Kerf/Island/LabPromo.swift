import AppKit
import KerfKit

/// The promo video's island: real states on a fixed timeline. `scripts/promo/compose.swift`
/// adds the backdrop, captions, cursor and sound at the same times, so keep the two in step.
extension Lab {
    private static func promoSession(_ id: String, agent: AgentKind = .claudeCode, project: String, title: String,
                                     state: AgentCenter.Session.State, minutes: Double, branch: String? = nil,
                                     subagents: Int = 0, unread: Bool = false) -> AgentCenter.Session {
        var session = AgentCenter.Session(id: id, agent: agent, name: agent.displayName, hostPath: terminal, project: project, state: state,
                                          updated: .now.addingTimeInterval(-minutes * 60), lastMessage: nil, title: title, unread: unread)
        session.stateSince = .now.addingTimeInterval(-minutes * 60)
        session.subagents = Set((0..<subagents).map { "agent-\($0)" })
        if let branch { session.repository = .init(id: "/\(project)/.git", branch: branch, revision: "", repositories: ["octocat/\(project)"]) }
        return session
    }

    /// Four threads; `waiting` says which of them are blocked on you.
    private static func promoSessions(waiting: Set<String>, done: Set<String> = []) -> [AgentCenter.Session] {
        func state(_ id: String) -> AgentCenter.Session.State { waiting.contains(id) ? .waiting : done.contains(id) ? .idle : .working }
        return [
            promoSession("atlas", project: "atlas", title: "Run the Atlas tests", state: state("atlas"), minutes: 4, unread: done.contains("atlas")),
            promoSession("kerf", project: "kerf", title: "Set up the project folders", state: state("kerf"), minutes: 9, branch: "v1-agentic", subagents: 2),
            promoSession("tempo", agent: .copilot, project: "tempo", title: "Review the weekly summary", state: state("tempo"), minutes: 12),
            promoSession("dot", project: "kerf", title: "Port the waiting dot", state: state("dot"), minutes: 23, branch: "fix/waiting-dot"),
        ]
    }

    private static func promoRequest(_ sessionID: String, _ payload: JSONValue) -> AgentCenter.Request {
        AgentCenter.Request(sessionID: sessionID, agent: .claudeCode, name: "Claude Code", hostPath: terminal, project: payload.project,
                            cwd: payload.workingDirectory, event: AgentEvent(payload), connection: nil)
    }

    func promo(_ controller: IslandController, _ directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let recorder = FrameRecorder(window: controller.panel, directory: directory)
        let center = AgentCenter.shared
        let permission = Self.promoRequest("atlas", .object([
            "hook_event_name": "PermissionRequest", "tool_name": "Bash", "cwd": "/Users/me/GitHub/atlas",
            "tool_input": .object(["command": "xcodebuild -project Atlas.xcodeproj -scheme Atlas test"]),
        ]))
        let question = Self.promoRequest("kerf", .object([
            "hook_event_name": "PreToolUse", "tool_name": "AskUserQuestion", "cwd": "/Users/me/GitHub/kerf",
            "tool_input": .object(["questions": .array([.object([
                "question": "Which folder names for a project?", "header": "Folders", "multiSelect": .bool(false),
                "options": .array([.object(["label": "Short, no numbers"]), .object(["label": "Numbered Dutch"]),
                                   .object(["label": "Numbered English"]), .object(["label": "Client / Project"])]),
            ])])]),
        ]))
        let script: [(Double, String, () -> Void)] = [
            (0, "idle", {
                PullRequests.shared.preview(pulls: [])
                center.preview(nil, sessions: [])
            }),
            (1.2, "dot", { center.preview(nil, sessions: Self.promoSessions(waiting: ["atlas", "kerf", "tempo"])) }),
            (5.4, "permission", { center.preview(permission, sessions: Self.promoSessions(waiting: ["atlas", "kerf", "tempo"])) }),
            (5.6, "open", { controller.open() }),
            (9.3, "allow", { center.answer(permission, AgentReply(decision: .allow)) }),
            (9.45, "close", { controller.close() }),
            (11.8, "question", { center.preview(question, sessions: Self.promoSessions(waiting: ["kerf", "tempo"])) }),
            (12.0, "open", { controller.open() }),
            (14.9, "pick", {
                var draft = QuestionDraft()
                draft.picked = ["Short, no numbers"]
                center.questionDrafts[question.id] = draft
            }),
            (15.3, "answer", {
                var reply = AgentReply(decision: .allow)
                reply.answers = ["Which folder names for a project?": "Short, no numbers"]
                center.answer(question, reply)
            }),
            (15.45, "close", { controller.close() }),
            (17.6, "threads", { controller.open(page: .agents) }),
            (25.6, "jump", { controller.close() }),
            // One change of compact kind per step: two within the island's 0.1 s swap leave the first one showing.
            (30.25, "pulls-ready", { Self.previewPullAlert() }),
            (30.4, "pull-alert", { center.preview(nil, sessions: Self.promoSessions(waiting: [])) }),
            (32.8, "pulls", { controller.open(page: .agents) }),
            (36.0, "close", { controller.close() }),
            (36.85, "done-ready", { center.preview(nil, sessions: Self.promoSessions(waiting: [], done: ["atlas"])) }),
            (37.0, "done", { PullRequests.shared.preview(pulls: []) }),
            (40.5, "idle", { center.preview(nil, sessions: []) }),
        ]
        Task {
            try? await Task.sleep(for: .seconds(0.6))
            recorder.begin()
            let clock = ContinuousClock()
            let start = clock.now
            for (time, name, step) in script {
                try? await clock.sleep(until: start + .seconds(time))
                recorder.mark(name)
                step()
            }
            try? await clock.sleep(until: start + .seconds(45.5))
            recorder.finish()
            Self.quit(0)
        }
    }
}
