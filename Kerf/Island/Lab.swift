import AppKit
import KerfKit
import SwiftUI

/// Checks the island without real data or permissions.
///
///     Kerf --lab motion <dir>         the iPhone recording's script, every frame saved
///     Kerf --lab shot <scene> <file>  one settled frame of a scene (see `scenes`)
///     Kerf --lab menus <pid> <file>   an app's menu titles and the room they leave
///     Kerf --lab focus                whether the island keeps the keyboard as it should
struct Lab {
    enum Job {
        case motion(URL)
        case shot(String, URL)
        /// Opens with the keyboard, switches to another app, closes: logs whether the island stays.
        case focus
        /// Writes an app's menu titles and the room they leave beside the notch to a file.
        case menus(pid: pid_t, file: URL)
    }

    let job: Job

    init?(arguments: [String]) {
        guard let index = arguments.firstIndex(of: "--lab"), arguments.count > index + 1 else { return nil }
        if arguments[index + 1] == "focus" {
            job = .focus
            return
        }
        guard arguments.count > index + 2 else { return nil }
        switch arguments[index + 1] {
        case "motion": job = .motion(URL(fileURLWithPath: arguments[index + 2]))
        case "shot" where arguments.count > index + 3: job = .shot(arguments[index + 2], URL(fileURLWithPath: arguments[index + 3]))
        case "menus" where arguments.count > index + 3:
            job = .menus(pid: pid_t(arguments[index + 2]) ?? 0, file: URL(fileURLWithPath: arguments[index + 3]))
        default: return nil
        }
    }

    /// Scenes for `shot`: set up an island, then it settles for a second and a half.
    static let scenes: [String: @MainActor (IslandController) -> Void] = [
        "idle": { _ in },
        "banner": { $0.island.show(.banner(.agent(.claudeCode), .symbol("bell.fill", Color(nsColor: .systemOrange))), waiting: 0) },
        "dot": { $0.island.show(nil, waiting: 1) },
        // Three threads blocked on you: the dot with its count.
        "dot-count": { _ in
            var sessions = sampleSessions
            for index in sessions.indices { sessions[index].state = .waiting }
            AgentCenter.shared.preview(nil, sessions: sessions)
        },
        "agent": { _ in previewAgent(question: false) },
        "agent-copilot": { controller in
            previewAgent(question: false, agent: .copilot)
            controller.open(page: .agents)
        },
        "agent-notice": { _ in AgentCenter.shared.preview(nil, sessions: sampleSessions) },
        // A thread that stopped on a rate limit: the red triangle instead of the tick.
        "agent-failed": { _ in AgentCenter.shared.preview(nil, sessions: sampleSessions.filter { $0.failure != nil }) },
        "ask": { $0.open(page: .ask) },
        "ask-answer": { controller in
            AskModule.shared.preview(question: "Wat doet een PreToolUse-hook in Claude Code?",
                                     answer: "Een **PreToolUse**-hook draait vlak voordat Claude een tool gebruikt.\n\n- Je kunt de aanroep toestaan of weigeren\n- Of de input aanpassen\n- Met een `matcher` kies je voor welke tools hij draait")
            controller.open(page: .ask)
        },
        "ask-typed": { controller in
            AskModule.shared.text = "Hoe schrijf ik een hook die elke Bash-call logt"
            controller.open(page: .ask, keyboard: true)
        },
        "agent-open": { previewAgent(question: false); $0.open() },
        "agent-question": { previewAgent(question: true); $0.open() },
        "agent-question-long": { previewLongQuestion(); $0.open() },
        "agent-long": { previewLongCommand(); $0.open() },
        // The island is open on the threads when a question comes in: it must grow to fit.
        "agent-arrives": { controller in
            AgentCenter.shared.preview(nil, sessions: sampleSessions)
            controller.open(page: .agents)
            Task {
                try? await Task.sleep(for: .seconds(0.6))
                previewLongQuestion()
            }
        },
        // Ask first, then the AI page with a question waiting.
        "agent-switch": { controller in
            controller.open(page: .ask)
            Task {
                try? await Task.sleep(for: .seconds(0.5))
                previewLongQuestion()
                controller.island.select(.agents)
            }
        },
        "agent-sessions": { controller in
            AgentCenter.shared.preview(nil, sessions: sampleSessions)
            previewPulls()
            controller.open(page: .agents)
        },
    ]

    static let terminal = "/System/Applications/Utilities/Terminal.app"

    static var sampleSessions: [AgentCenter.Session] {
        var working = AgentCenter.Session(id: "1", agent: .claudeCode, name: "Claude Code", hostPath: terminal, project: "kerf", state: .working,
                                          updated: .now, lastMessage: nil, title: "Make the timer its own tab", unread: false)
        working.stateSince = .now.addingTimeInterval(-41 * 60)
        working.subagents = ["a", "b"]
        var done = AgentCenter.Session(id: "2", agent: .claudeCode, name: "Claude Code", hostPath: terminal, project: "atlas", state: .idle,
                                       updated: .now.addingTimeInterval(-600), lastMessage: "Tests pass.", title: "Fix the sync check-in", unread: true)
        done.stateSince = .now.addingTimeInterval(-600)
        var waiting = AgentCenter.Session(id: "3", agent: .copilot, name: "Copilot", hostPath: terminal, project: "tempo", state: .waiting,
                                          updated: .now, lastMessage: nil, title: "Review the weekly summary", unread: false)
        waiting.stateSince = .now.addingTimeInterval(-12 * 60)
        var failed = AgentCenter.Session(id: "4", agent: .claudeCode, name: "Claude Code", hostPath: terminal, project: "kerf", state: .idle,
                                         updated: .now.addingTimeInterval(-180), lastMessage: nil, title: "Port the waiting dot", unread: true)
        failed.stateSince = .now.addingTimeInterval(-180)
        failed.needsInput = true
        failed.failure = "rate_limit"
        return [waiting, failed, working, done]
    }

    static func previewPulls() {
        let json = #"[{"number":42,"title":"Kerf: AI tab with threads","repository":{"nameWithOwner":"octocat/kerf"},"url":"https://github.com/octocat/kerf/pull/42","updatedAt":"2026-10-31T10:00:00Z","isDraft":false,"checks":"failing"},{"number":17,"title":"Weekly summary in Tempo","repository":{"nameWithOwner":"octocat/tempo"},"url":"https://github.com/octocat/tempo/pull/17","updatedAt":"2026-10-30T18:00:00Z","isDraft":true,"checks":"pending","changesRequested":true}]"#
        PullRequests.shared.preview(pulls: GitHub.decode([GitHub.Item].self, from: Data(json.utf8)) ?? [])
    }

    static func previewAgent(question: Bool, agent: AgentKind = .claudeCode) {
        let payload: JSONValue = question
            ? .object(["hook_event_name": "PreToolUse", "tool_name": "AskUserQuestion", "cwd": "/Users/me/GitHub/kerf",
                       "tool_input": .object(["questions": .array([.object([
                           "question": "Which folder names for a project?", "header": "Folders", "multiSelect": .bool(false),
                           "options": .array([.object(["label": "Short, no numbers"]), .object(["label": "Numbered Dutch"]),
                                              .object(["label": "Numbered English"]), .object(["label": "Client / Project"])]),
                       ])])])])
            : .object(["hook_event_name": "PermissionRequest", "tool_name": "Bash", "cwd": "/Users/me/GitHub/atlas",
                       "tool_input": .object(["command": "xcodebuild -project Atlas.xcodeproj -scheme Atlas test"])])
        let request = AgentCenter.Request(sessionID: "1", agent: agent, name: agent.displayName, hostPath: terminal, project: payload.project,
                                          cwd: payload.workingDirectory, event: AgentEvent(payload), connection: nil)
        AgentCenter.shared.preview(request, sessions: sampleSessions)
    }

    /// A question with more text than fits on a line, and options with descriptions.
    static func previewLongQuestion() {
        let options: [JSONValue] = [
            .object(["label": "Keep one version and drop the personal parts", "description": "Simplest to maintain. The removed code stays in git history if you ever want it back."]),
            .object(["label": "Two versions with a build setting", "description": "The public build leaves the personal parts out; your own build keeps them. More upkeep."]),
            .object(["label": "Decide later", "description": "Nothing changes now."]),
        ]
        let payload: JSONValue = .object(["hook_event_name": "PreToolUse", "tool_name": "AskUserQuestion", "cwd": "/Users/me/GitHub/kerf",
            "tool_input": .object(["questions": .array([.object([
                "question": "The personal integrations are connected on your own Mac right now. What should happen to them in the version others install, and in your own copy?",
                "header": "Personal", "multiSelect": .bool(false), "options": .array(options),
            ])])])])
        let request = AgentCenter.Request(sessionID: "1", agent: .claudeCode, name: "Claude Code", hostPath: terminal, project: payload.project,
                                          cwd: payload.workingDirectory, event: AgentEvent(payload), connection: nil)
        AgentCenter.shared.preview(request, sessions: sampleSessions)
    }

    /// A permission for a command too long for three lines.
    static func previewLongCommand() {
        let command = "cd ~/GitHub/kerf && xcodebuild -project Kerf.xcodeproj -scheme Kerf -configuration Release -derivedDataPath build/DerivedData archive -archivePath build/Kerf.xcarchive && xcodebuild -exportArchive -archivePath build/Kerf.xcarchive -exportOptionsPlist scripts/ExportOptions.plist -exportPath build/export -allowProvisioningUpdates && ditto -c -k --keepParent build/export/Kerf.app build/Kerf.zip && shasum -a 256 build/Kerf.zip"
        let payload: JSONValue = .object(["hook_event_name": "PermissionRequest", "tool_name": "Bash", "cwd": "/Users/me/GitHub/kerf",
                                          "tool_input": .object(["command": .string(command)])])
        let request = AgentCenter.Request(sessionID: "1", agent: .claudeCode, name: "Claude Code", hostPath: terminal, project: payload.project,
                                          cwd: payload.workingDirectory, event: AgentEvent(payload), connection: nil)
        AgentCenter.shared.preview(request, sessions: sampleSessions)
    }

    func run() {
        Preferences.register()
        guard let screen = NSScreen.screens.first(where: { $0.notchSize != nil }) ?? NSScreen.main else { Self.quit(1) }
        let controller = IslandController(screen: screen, interactive: false)
        Hub.shared.observe { controller.apply(Hub.shared) }
        controller.apply(Hub.shared)
        controller.show()
        switch job {
        case .motion(let directory): motion(controller, directory)
        case .shot(let scene, let file): shot(controller, scene, file)
        case .focus: focus(controller)
        case .menus(let pid, let file):
            let scan = MenuBarScan(front: pid, readMenus: true)
            let display = CGDisplayBounds(screen.displayID)
            let items = (scan.menuItems ?? []).filter { abs($0.minY - display.minY) < 2 } + scan.statusItems(on: display)
            var lines = (scan.menuItems ?? []).map { "menu \(Int($0.minX))...\(Int($0.maxX)) y \(Int($0.minY))" }
            lines += scan.statusItems(on: display).map { "status \(Int($0.minX))...\(Int($0.maxX))" }
            if let range = screen.notchRange {
                lines.append("notch \(Int(range.lowerBound))...\(Int(range.upperBound))")
                lines.append("room \(MenuBarRoom.free(notchMinX: range.lowerBound, notchMaxX: range.upperBound, items: items))")
            }
            try? lines.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
            Self.quit(0)
        }
    }

    static func quit(_ status: Int32) -> Never {
        exit(status)
    }

    private func focus(_ controller: IslandController) {
        func log(_ step: String) {
            let panel = controller.panel
            print("\(step): visible \(panel.isVisible) key \(panel.isKeyWindow) onScreen \(panel.occlusionState.contains(.visible)) mode \(controller.island.mode) frame \(panel.frame.origin.y)")
        }
        Task {
            try? await Task.sleep(for: .seconds(0.5))
            controller.open(page: .ask, keyboard: true)
            try? await Task.sleep(for: .seconds(1))
            log("open")
            NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first?.activate()
            try? await Task.sleep(for: .seconds(1))
            log("finder active")
            controller.close()
            try? await Task.sleep(for: .seconds(1))
            log("closed")
            Self.quit(0)
        }
    }

    private func shot(_ controller: IslandController, _ scene: String, _ file: URL) {
        guard let setUp = Self.scenes[scene] else {
            print("Unknown scene \(scene). Scenes: \(Self.scenes.keys.sorted().joined(separator: ", "))")
            Self.quit(1)
        }
        Task {
            try? await Task.sleep(for: .seconds(0.4))
            setUp(controller)
            if ProcessInfo.processInfo.environment["KERF_LAB_DEBUG"] != nil {
                try? await Task.sleep(for: .seconds(0.3))
                print("page \(controller.island.page) pages \(controller.island.pages)")
            }
            try? await Task.sleep(for: .seconds(1.6))
            if let image = FrameRecorder.snapshot(of: controller.panel) { writePNG(image, to: file) }
            Self.quit(0)
        }
    }

    private func motion(_ controller: IslandController, _ directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let recorder = FrameRecorder(window: controller.panel, directory: directory)
        let script: [(Double, String, () -> Void)] = [
            (1, "compact", { Self.previewAgent(question: false) }),
            (3, "expanded", { controller.open() }),
            (6, "compact", { controller.close() }),
            (8, "expanded", { controller.open() }),
            (11, "compact", { controller.close() }),
            (13, "idle", { AgentCenter.shared.preview(nil, sessions: []) }),
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
            try? await clock.sleep(until: start + .seconds(14.5))
            recorder.finish()
            Self.quit(0)
        }
    }
}
