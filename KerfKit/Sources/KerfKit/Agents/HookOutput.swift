import Foundation

/// What `kerf hook` prints so Claude Code or Copilot acts on your answer.
public enum HookOutput {
    /// Nil prints nothing: the tool carries on as if Kerf weren't there.
    public static func json(for event: AgentEvent, reply: AgentReply, agent: AgentKind) -> Data? {
        switch (event, reply.decision) {
        case (_, .passThrough):
            return nil
        case (.permission(let tool, let input, let suggestions), let decision):
            var answer: [String: JSONValue] = ["behavior": .string(decision == .deny ? "deny" : "allow")]
            if decision == .deny { answer["message"] = .string(reply.message ?? "Declined in Kerf.") }
            if decision == .always, agent.remembersAlways {
                answer["updatedPermissions"] = AlwaysRule.entries(tool: tool, input: input, suggestions: suggestions)
            }
            guard agent == .copilot else { return wrap(["hookEventName": "PermissionRequest", "decision": .object(answer)]) }
            // Copilot documents `behavior` at the top; the Claude-style part is for its VS Code mode.
            var flat = answer
            flat["hookSpecificOutput"] = .object(["hookEventName": "PermissionRequest", "decision": .object(answer)])
            return JSONValue.object(flat).encoded()
        case (.question(_, let raw), .allow), (.question(_, let raw), .always):
            guard let answers = reply.answers, !answers.isEmpty else { return nil }
            return wrap([
                "hookEventName": "PreToolUse",
                "permissionDecision": "allow",
                "updatedInput": .object(["questions": raw, "answers": .object(answers.mapValues { .string($0) })]),
            ])
        default:
            return nil
        }
    }

    private static func wrap(_ specific: [String: JSONValue]) -> Data {
        JSONValue.object(["hookSpecificOutput": .object(specific)]).encoded()
    }
}

/// "Always allow" means this command in this project: a rule in the project's
/// .claude/settings.local.json, which Claude Code writes itself.
public enum AlwaysRule {
    public static func entries(tool: String, input: JSONValue, suggestions: [JSONValue]) -> JSONValue {
        // Claude Code's own suggestion knows the rule syntax best.
        if let suggestion = suggestions.first(where: { $0["type"]?.string == "addRules" }), var entry = suggestion.object {
            entry["destination"] = .string("localSettings")
            entry["behavior"] = .string("allow")
            return .array([.object(entry)])
        }
        var rule: [String: JSONValue] = ["toolName": .string(tool)]
        if tool == "Bash", let command = input["command"]?.string { rule["ruleContent"] = .string(command) }
        return .array([.object([
            "type": "addRules",
            "rules": .array([.object(rule)]),
            "behavior": "allow",
            "destination": "localSettings",
        ])])
    }
}

extension JSONValue: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self = .string(value)
    }
}
