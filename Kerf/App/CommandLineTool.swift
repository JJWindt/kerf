import Foundation
import KerfKit

enum CommandLineTool {
    static let usage = """
    kerf: talk to the Kerf notch app

      kerf hook claude-code|copilot [EVENT]
                                      for hooks: reads the hook's JSON on stdin
      kerf notify [--agent NAME] [--title TITLE] MESSAGE
                                      a short message in the notch
      kerf notify --ask [--agent NAME] [--title TITLE] MESSAGE
                                      asks to allow; exit 0 allowed, 1 declined, 2 no answer
      kerf answer allow|always|deny   answers the first waiting question
      kerf debug                      what the running app sees
      kerf version
    """

    /// Runs a subcommand and returns its exit status, or nil to start the app.
    static func run(_ arguments: [String]) -> Int32? {
        // Started as `kerf` (Homebrew's link, the hooks' bin/kerf) it is only ever the command,
        // never a second app.
        let asCommand = arguments.first.map { URL(fileURLWithPath: $0).lastPathComponent == "kerf" } ?? false
        guard arguments.count > 1 else {
            guard asCommand else { return nil }
            print(usage)
            return 0
        }
        switch arguments[1] {
        case "hook":
            return hook(agent: arguments.count > 2 ? arguments[2] : "", event: arguments.count > 3 ? arguments[3] : nil)
        case "notify":
            return notify(Array(arguments.dropFirst(2)))
        case "answer":
            guard arguments.count > 2, ["allow", "always", "deny"].contains(arguments[2]) else {
                print(usage)
                return 64
            }
            let envelope = AgentEnvelope(agent: .other, payload: .object(["hook_event_name": "KerfAnswer", "decision": .string(arguments[2])]))
            guard let line = try? JSONEncoder().encode(envelope) else { return 2 }
            return UnixSocket.send(line, to: KerfPaths.socket, waitForReply: false, timeout: 1) == nil ? 2 : 0
        case "debug":
            let envelope = AgentEnvelope(agent: .other, payload: .object(["hook_event_name": "KerfDebug"]))
            guard let line = try? JSONEncoder().encode(envelope),
                  let reply = UnixSocket.send(line, to: KerfPaths.socket, waitForReply: true, timeout: 3) else {
                print("Kerf isn't running.")
                return 2
            }
            print(String(decoding: reply, as: UTF8.self))
            return 0
        case "version", "--version":
            // Through a symlink (Homebrew's `kerf`, the hooks' bin/kerf) Bundle.main is the link's folder.
            let app = Bundle.main.executableURL.map { $0.resolvingSymlinksInPath().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent() }
            let bundle = app.flatMap(Bundle.init(url:)) ?? Bundle.main
            print(bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?")
            return 0
        case "help", "--help":
            print(usage)
            return 0
        default:
            guard asCommand else { return nil }
            print(usage)
            return 64
        }
    }

    /// Never in the way: if Kerf isn't running or doesn't answer, print nothing and let the tool
    /// ask as it always does.
    private static func hook(agent name: String, event: String?) -> Int32 {
        let agent = AgentKind(rawValue: name) ?? .other
        let input = FileHandle.standardInput.readDataToEndOfFile()
        guard var payload = JSONValue.parse(input) else { return 0 }
        if agent == .copilot { payload = CopilotPayload.normalized(payload, event: event) }
        let host = ProcessTree.hostApp()
        let envelope = AgentEnvelope(agent: agent, host: host?.bundlePath, payload: payload)
        guard let line = try? JSONEncoder().encode(envelope) else { return 0 }
        guard envelope.waitsForReply else {
            _ = UnixSocket.send(line, to: KerfPaths.socket, waitForReply: false, timeout: 1)
            return 0
        }
        guard let answer = UnixSocket.send(line, to: KerfPaths.socket, waitForReply: true, timeout: 590),
              let reply = try? JSONDecoder().decode(AgentReply.self, from: answer),
              let output = HookOutput.json(for: AgentEvent(payload), reply: reply, agent: agent) else { return 0 }
        FileHandle.standardOutput.write(output + Data([0x0A]))
        return 0
    }

    private static func notify(_ arguments: [String]) -> Int32 {
        var name = "Agent"
        var title: String?
        var ask = false
        var words: [String] = []
        var index = 0
        while index < arguments.count {
            switch arguments[index] {
            case "--agent" where index + 1 < arguments.count:
                name = arguments[index + 1]
                index += 1
            case "--title" where index + 1 < arguments.count:
                title = arguments[index + 1]
                index += 1
            case "--ask":
                ask = true
            default:
                words.append(arguments[index])
            }
            index += 1
        }
        let message = words.joined(separator: " ")
        guard !message.isEmpty else {
            print(usage)
            return 64
        }
        let payload: JSONValue = ask
            ? .object(["hook_event_name": "PermissionRequest", "tool_name": .string(title ?? name),
                       "tool_input": .object(["description": .string(message)]), "session_id": .string(name)])
            : .object(["hook_event_name": "Notification", "message": .string(message), "title": title.map { .string($0) } ?? .null,
                       "session_id": .string(name)])
        let envelope = AgentEnvelope(agent: .other, host: ProcessTree.hostApp()?.bundlePath, payload: payload, name: name)
        guard let line = try? JSONEncoder().encode(envelope) else { return 2 }
        guard ask else { return UnixSocket.send(line, to: KerfPaths.socket, waitForReply: false, timeout: 1) == nil ? 2 : 0 }
        guard let answer = UnixSocket.send(line, to: KerfPaths.socket, waitForReply: true, timeout: 590),
              let reply = try? JSONDecoder().decode(AgentReply.self, from: answer) else { return 2 }
        switch reply.decision {
        case .allow, .always: return 0
        case .deny: return 1
        case .passThrough: return 2
        }
    }
}
