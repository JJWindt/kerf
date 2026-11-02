import Foundation

/// The coding tools Kerf knows by name. Anything else comes in through `kerf notify`.
public enum AgentKind: String, Codable, Sendable, CaseIterable {
    case claudeCode = "claude-code"
    case codex
    case copilot
    case other

    public var displayName: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        case .copilot: "Copilot"
        case .other: "Agent"
        }
    }

    /// Only Claude Code can keep an "always allow" as a rule; elsewhere it would mean just once.
    public var remembersAlways: Bool { self == .claudeCode }
}

/// One line from `kerf hook` or `kerf notify` to the app, over the socket.
public struct AgentEnvelope: Codable, Equatable, Sendable {
    public var version = 1
    public var agent: AgentKind
    /// The app the tool runs in, from the process tree: "T3 Code", "Terminal", "Visual Studio Code".
    public var host: String?
    /// The hook's own JSON, as the tool sent it.
    public var payload: JSONValue
    /// `kerf notify`: a name for tools Kerf doesn't know.
    public var name: String?

    public init(agent: AgentKind, host: String? = nil, payload: JSONValue, name: String? = nil) {
        self.agent = agent
        self.host = host
        self.payload = payload
        self.name = name
    }

    /// Whether the tool waits for your answer.
    public var waitsForReply: Bool {
        switch AgentEvent(payload) {
        case .permission, .question: true
        default: false
        }
    }
}

/// Your answer, back over the socket.
public struct AgentReply: Codable, Equatable, Sendable {
    public enum Decision: String, Codable, Sendable {
        /// Allow once.
        case allow
        /// Allow, and keep allowing this command in this project.
        case always
        case deny
        /// No decision: the tool asks in its own window as usual.
        case passThrough
    }

    public var decision: Decision
    public var message: String?
    /// For questions: question text → chosen label or typed answer.
    public var answers: [String: String]?

    public init(decision: Decision, message: String? = nil, answers: [String: String]? = nil) {
        self.decision = decision
        self.message = message
        self.answers = answers
    }
}
