import Foundation

/// Adds Kerf's hooks to Claude Code's ~/.claude/settings.json or Codex's ~/.codex/hooks.json,
/// and takes them out again, touching nothing else in the file. Copilot gets a file of its own.
public enum HookInstaller {
    public struct Hook: Equatable, Sendable {
        public var event: String
        public var matcher: String?
        public var timeout: Int
    }

    /// The stable path of the `kerf` command; the app points it at itself on every launch.
    public static let commandPath = "$HOME/Library/Application Support/Kerf/bin/kerf"

    public static func command(for agent: AgentKind) -> String {
        "\"\(commandPath)\" hook \(agent.rawValue)"
    }

    /// Waiting for an answer gets Claude Code's full ten minutes; the rest must be quick.
    public static func hooks(for agent: AgentKind) -> [Hook] {
        switch agent {
        case .claudeCode:
            [
                Hook(event: "PermissionRequest", matcher: nil, timeout: 600),
                Hook(event: "PreToolUse", matcher: "AskUserQuestion", timeout: 600),
                Hook(event: "Notification", matcher: nil, timeout: 10),
                Hook(event: "Stop", matcher: nil, timeout: 10),
                Hook(event: "SessionStart", matcher: nil, timeout: 10),
                Hook(event: "SessionEnd", matcher: nil, timeout: 10),
                Hook(event: "UserPromptSubmit", matcher: nil, timeout: 10),
            ]
        case .codex:
            [
                Hook(event: "PermissionRequest", matcher: nil, timeout: 600),
                Hook(event: "Stop", matcher: nil, timeout: 10),
                Hook(event: "SessionStart", matcher: nil, timeout: 10),
                Hook(event: "SessionEnd", matcher: nil, timeout: 10),
                Hook(event: "UserPromptSubmit", matcher: nil, timeout: 10),
            ]
        case .copilot:
            [
                Hook(event: "PermissionRequest", matcher: nil, timeout: 600),
                Hook(event: "Notification", matcher: nil, timeout: 10),
                Hook(event: "Stop", matcher: nil, timeout: 10),
                Hook(event: "SessionStart", matcher: nil, timeout: 10),
                Hook(event: "SessionEnd", matcher: nil, timeout: 10),
                Hook(event: "UserPromptSubmit", matcher: nil, timeout: 10),
            ]
        case .other:
            []
        }
    }

    /// Copilot reads every file in ~/.copilot/hooks, so Kerf keeps its own there and never edits
    /// Copilot's. PascalCase event names make Copilot send Claude Code's fields; the event name in
    /// the command covers versions that leave it out.
    public static func copilotFile() -> String {
        let events = hooks(for: .copilot).map { hook in
            OrderedJSON.Member(hook.event, .array([.object([
                .init("type", .string("command")),
                .init("bash", .string("\(command(for: .copilot)) \(hook.event)")),
                .init("timeoutSec", .number(String(hook.timeout))),
            ])]))
        }
        return OrderedJSON.object([.init("version", .number("1")), .init("hooks", .object(events))]).printed() + "\n"
    }

    public static func isCopilotFile(_ text: String?) -> Bool {
        guard let text, let root = try? OrderedJSON.parse(text), case .object(let events)? = root["hooks"] else { return false }
        return events.contains { event in
            (event.value.arrayValue ?? []).contains { entry in
                let command = entry["bash"]?.stringValue ?? entry["command"]?.stringValue ?? ""
                return command.contains("/Kerf/bin/kerf") && command.contains("hook copilot")
            }
        }
    }

    public static func isKerfHandler(_ handler: OrderedJSON, agent: AgentKind) -> Bool {
        guard let command = handler["command"]?.stringValue else { return false }
        return command.contains("/Kerf/bin/kerf") && command.hasSuffix("hook \(agent.rawValue)")
    }

    public static func isInstalled(in text: String?, agent: AgentKind) -> Bool {
        guard let text, let root = try? OrderedJSON.parse(text), case .object(let events)? = root["hooks"] else { return false }
        return events.contains { event in
            (event.value.arrayValue ?? []).contains { group in
                (group["hooks"]?.arrayValue ?? []).contains { isKerfHandler($0, agent: agent) }
            }
        }
    }

    /// The file with Kerf's hooks, replacing any it already had. Nil text means no file yet.
    public static func install(into text: String?, agent: AgentKind) throws -> String {
        var root = try removed(from: (text?.isEmpty == false) ? OrderedJSON.parse(text!) : .object([]), agent: agent)
        var events = root["hooks"] ?? .object([])
        for hook in hooks(for: agent) {
            var group: [OrderedJSON.Member] = []
            if let matcher = hook.matcher { group.append(.init("matcher", .string(matcher))) }
            group.append(.init("hooks", .array([.object([
                .init("type", .string("command")),
                .init("command", .string(command(for: agent))),
                .init("timeout", .number(String(hook.timeout))),
            ])])))
            var groups = events[hook.event]?.arrayValue ?? []
            groups.append(.object(group))
            events[hook.event] = .array(groups)
        }
        root["hooks"] = events
        return root.printed() + "\n"
    }

    public static func remove(from text: String, agent: AgentKind) throws -> String {
        try removed(from: OrderedJSON.parse(text), agent: agent).printed() + "\n"
    }

    private static func removed(from root: OrderedJSON, agent: AgentKind) throws -> OrderedJSON {
        guard case .object(let events)? = root["hooks"] else { return root }
        var kept: [OrderedJSON.Member] = []
        for event in events {
            guard let groups = event.value.arrayValue else {
                kept.append(event)
                continue
            }
            let cleaned = groups.compactMap { group -> OrderedJSON? in
                guard let handlers = group["hooks"]?.arrayValue else { return group }
                let left = handlers.filter { !isKerfHandler($0, agent: agent) }
                if left.count == handlers.count { return group }
                guard !left.isEmpty else { return nil }
                var copy = group
                copy["hooks"] = .array(left)
                return copy
            }
            if !cleaned.isEmpty { kept.append(.init(event.key, .array(cleaned))) }
        }
        var copy = root
        copy["hooks"] = kept.isEmpty ? nil : .object(kept)
        return copy
    }
}

/// A line diff for showing what an install changes: "+ " added, "- " removed, "  " context.
public enum LineDiff {
    public static func lines(from old: String, to new: String, context: Int = 2) -> [String] {
        let a = old.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let b = new.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        // Longest common subsequence, fine for settings files.
        var table = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in stride(from: a.count - 1, through: 0, by: -1) {
            for j in stride(from: b.count - 1, through: 0, by: -1) {
                table[i][j] = a[i] == b[j] ? table[i + 1][j + 1] + 1 : max(table[i + 1][j], table[i][j + 1])
            }
        }
        var all: [(Character, String)] = []
        var (i, j) = (0, 0)
        while i < a.count || j < b.count {
            if i < a.count, j < b.count, a[i] == b[j] {
                all.append((" ", a[i])); i += 1; j += 1
            } else if j < b.count, i == a.count || table[i][j + 1] >= table[i + 1][j] {
                all.append(("+", b[j])); j += 1
            } else {
                all.append(("-", a[i])); i += 1
            }
        }
        let changed = all.indices.filter { all[$0].0 != " " }
        guard !changed.isEmpty else { return [] }
        var show = Set<Int>()
        for index in changed { (max(0, index - context)...min(all.count - 1, index + context)).forEach { show.insert($0) } }
        var out: [String] = []
        var last = -1
        for index in show.sorted() {
            if last >= 0, index > last + 1 { out.append("…") }
            out.append("\(all[index].0) \(all[index].1)")
            last = index
        }
        return out
    }
}
