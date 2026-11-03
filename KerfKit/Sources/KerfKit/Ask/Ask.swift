import Foundation

/// Where a line typed in the island goes: a question to Claude, a search term to Google.
public enum AskRoute: String, Codable, Sendable {
    case claude, google

    private static let questionWords: Set<String> = [
        // English
        "what", "why", "how", "who", "when", "where", "which", "can", "could", "should", "would", "is", "are", "do", "does",
        "explain", "write", "make", "give", "tell", "summarize", "summarise", "translate", "help", "fix", "rewrite", "compare",
        // Dutch
        "wat", "waarom", "hoe", "wie", "wanneer", "waar", "welke", "welk", "kan", "kun", "kunnen", "moet", "moeten", "zou", "zijn",
        "leg", "schrijf", "maak", "geef", "vertel", "vat", "vertaal", "help", "verbeter", "herschrijf", "vergelijk",
    ]

    /// A question, an instruction or a long line goes to Claude. Two or three words go to Google.
    public static func guess(_ text: String) -> AskRoute {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasSuffix("?") { return .claude }
        let words = trimmed.lowercased().split(whereSeparator: { $0.isWhitespace || $0 == "," })
        guard let first = words.first else { return .claude }
        if questionWords.contains(String(first)) { return .claude }
        return words.count > 5 ? .claude : .google
    }

    public static func googleURL(_ text: String) -> URL? {
        var components = URLComponents(string: "https://www.google.com/search")
        components?.queryItems = [URLQueryItem(name: "q", value: text)]
        return components?.url
    }
}

/// One line of `claude -p --output-format stream-json --include-partial-messages`.
public enum ClaudeStreamEvent: Equatable, Sendable {
    case started(session: String)
    case text(String)
    case tool(String)
    case finished(answer: String, session: String?, isError: Bool)
    case other

    public static func parse(_ line: Data) -> ClaudeStreamEvent {
        guard let json = JSONValue.parse(line) else { return .other }
        switch json["type"]?.string {
        case "system" where json["subtype"]?.string == "init":
            return json["session_id"]?.string.map { .started(session: $0) } ?? .other
        case "stream_event":
            let event = json["event"]
            if event?["type"]?.string == "content_block_delta", let text = event?["delta"]?["text"]?.string { return .text(text) }
            if event?["type"]?.string == "content_block_start", event?["content_block"]?["type"]?.string == "tool_use",
               let name = event?["content_block"]?["name"]?.string { return .tool(name) }
            return .other
        case "result":
            return .finished(answer: json["result"]?.string ?? "", session: json["session_id"]?.string,
                             isError: json["is_error"]?.bool ?? (json["subtype"]?.string != "success"))
        default:
            return .other
        }
    }
}

/// A question and its answer, kept for the history (the last 20).
public struct Conversation: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var question: String
    public var answer: String
    public var session: String?
    public var date: Date

    /// Older histories also have `attachments`; decoding skips it.
    public init(id: UUID = UUID(), question: String, answer: String, session: String?, date: Date = .now) {
        self.id = id
        self.question = question
        self.answer = answer
        self.session = session
        self.date = date
    }

    /// Newest first, at most `limit`, a conversation updated in place.
    public static func keeping(_ conversation: Conversation, in history: [Conversation], limit: Int = 20) -> [Conversation] {
        Array(([conversation] + history.filter { $0.id != conversation.id }).prefix(limit))
    }
}
