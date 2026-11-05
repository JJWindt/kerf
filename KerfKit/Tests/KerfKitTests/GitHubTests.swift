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

struct GitHubSearchTests {
    @Test func checksAndReviews() throws {
        let data = Data(#"""
        {"data":{"search":{"nodes":[
          {"number":42,"title":"Waiting dot","url":"https://github.com/o/kerf/pull/42","isDraft":false,"updatedAt":"2026-11-03T15:43:58Z",
           "reviewDecision":"CHANGES_REQUESTED","repository":{"nameWithOwner":"o/kerf"},
           "commits":{"nodes":[{"commit":{"statusCheckRollup":{"state":"FAILURE"}}}]}},
          {"number":7,"title":"No CI","url":"https://github.com/o/tempo/pull/7","isDraft":true,"updatedAt":"2026-11-02T10:00:00Z",
           "reviewDecision":null,"repository":{"nameWithOwner":"o/tempo"},"commits":{"nodes":[{"commit":{"statusCheckRollup":null}}]}},
          {}
        ]}}}
        """#.utf8)
        let pulls = try #require(GitHub.pulls(fromSearch: data))
        #expect(pulls.count == 2)
        #expect(pulls[0].checks == .failing)
        #expect(pulls[0].changesRequested == true)
        #expect(pulls[0].updatedAt != nil)
        #expect(pulls[1].checks == nil)
        #expect(pulls[1].isDraft == true)
        #expect(GitHub.searchQuery(login: "JJWindt").contains("author:JJWindt"))
        #expect(!GitHub.searchQuery(login: "JJWindt").contains("involves:"))
        #expect(GitHub.searchQuery(login: "JJWindt", reviews: true).contains("review-requested:JJWindt"))
        let merged = GitHub.searchQuery(login: "JJWindt", mergedSince: Date(timeIntervalSince1970: 0))
        #expect(merged.contains("is:merged author:JJWindt merged:>=1970-01-01T00:00:00Z") && merged.contains("mergedAt"))
        #expect(!merged.contains("is:open"))
    }
}
