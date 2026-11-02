import Foundation
import Testing
@testable import KerfKit

struct AskTests {
    @Test func routes() {
        #expect(AskRoute.guess("fx3 firmware") == .google)
        #expect(AskRoute.guess("weer amsterdam") == .google)
        #expect(AskRoute.guess("hoe werkt een backyard ultra") == .claude)
        #expect(AskRoute.guess("Why is the sky blue") == .claude)
        #expect(AskRoute.guess("fx3 firmware?") == .claude)
        #expect(AskRoute.guess("beste kleurprofiel voor trouwfilms bij weinig licht") == .claude)
        #expect(AskRoute.guess("logo", hasAttachments: true) == .claude)
        #expect(AskRoute.googleURL("a b&c")?.absoluteString == "https://www.google.com/search?q=a%20b%26c")
    }

    @Test func readsTheStream() {
        #expect(ClaudeStreamEvent.parse(Data(#"{"type":"system","subtype":"init","session_id":"s1","model":"claude-opus-5-5"}"#.utf8)) == .started(session: "s1"))
        #expect(ClaudeStreamEvent.parse(Data(#"{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"text_delta","text":"Hal"}}}"#.utf8)) == .text("Hal"))
        #expect(ClaudeStreamEvent.parse(Data(#"{"type":"stream_event","event":{"type":"content_block_start","content_block":{"type":"tool_use","name":"Read"}}}"#.utf8)) == .tool("Read"))
        #expect(ClaudeStreamEvent.parse(Data(#"{"type":"result","subtype":"success","is_error":false,"result":"Hallo","session_id":"s1"}"#.utf8))
            == .finished(answer: "Hallo", session: "s1", isError: false))
        #expect(ClaudeStreamEvent.parse(Data("nonsense".utf8)) == .other)
    }

    @Test func historyKeepsTwenty() {
        var history: [Conversation] = []
        for index in 0..<25 { history = Conversation.keeping(Conversation(question: "\(index)", answer: "", session: nil), in: history) }
        #expect(history.count == 20)
        #expect(history.first?.question == "24")
        var updated = history[3]
        updated.answer = "new"
        history = Conversation.keeping(updated, in: history)
        #expect(history.first?.answer == "new")
        #expect(history.count == 20)
    }
}
