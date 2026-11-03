import Foundation
import Testing
@testable import KerfKit

struct GitHubTests {
    @Test func decodesPullRequests() throws {
        let data = Data(#"[{"number":12,"title":"Fix the hook","repository":{"nameWithOwner":"octocat/tempo"},"url":"https://github.com/octocat/tempo/pull/12","updatedAt":"2026-10-30T16:43:57Z","isDraft":true}]"#.utf8)
        let pulls = try #require(GitHub.decode([GitHub.Item].self, from: data))
        #expect(pulls.first?.number == 12)
        #expect(pulls.first?.isDraft == true)
        #expect(pulls.first?.updatedAt != nil)
    }
}
