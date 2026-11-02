import Foundation
import Testing
@testable import KerfKit

struct JoinLinkTests {
    @Test func findsCallLinks() {
        #expect(JoinLink.find(in: [nil, "Kantoor", "Join: https://us02web.zoom.us/j/123456?pwd=abc"])?.host == "us02web.zoom.us")
        #expect(JoinLink.find(in: ["https://meet.google.com/abc-defg-hij"])?.absoluteString == "https://meet.google.com/abc-defg-hij")
        #expect(JoinLink.find(in: ["Notulen op https://example.com/doc"]) == nil)
        #expect(JoinLink.find(in: []) == nil)
    }
}
