import Foundation

/// The open pull requests on the AI page, from `gh`, with their CI and review state.
public enum GitHub {
    public struct Item: Codable, Equatable, Sendable, Identifiable {
        /// The latest commit's checks, all together.
        public enum Checks: String, Codable, Sendable {
            case passing, failing, pending

            init?(rollup: String?) {
                switch rollup {
                case "SUCCESS": self = .passing
                case "FAILURE", "ERROR": self = .failing
                case "PENDING", "EXPECTED": self = .pending
                default: return nil
                }
            }
        }

        public struct Repository: Codable, Equatable, Sendable {
            public var nameWithOwner: String
        }

        public var number: Int
        public var title: String
        public var repository: Repository
        public var url: String
        public var updatedAt: Date?
        public var isDraft: Bool?
        public var checks: Checks?
        /// A reviewer asked for changes.
        public var changesRequested: Bool?
        public var id: String { url }
    }

    /// Open pull requests you're involved in, newest first, with checks and reviews: one GraphQL
    /// search for `gh api graphql -f query=…`.
    public static func searchQuery(login: String) -> String {
        """
        query { search(query: "is:pr is:open archived:false involves:\(login) sort:updated-desc", type: ISSUE, first: 20) { nodes { \
        ... on PullRequest { number title url isDraft updatedAt reviewDecision repository { nameWithOwner } \
        commits(last: 1) { nodes { commit { statusCheckRollup { state } } } } } } } }
        """
    }

    /// The pull requests in a `searchQuery` answer.
    public static func pulls(fromSearch data: Data) -> [Item]? {
        guard let nodes = JSONValue.parse(data)?["data"]?["search"]?["nodes"]?.array else { return nil }
        let dates = ISO8601DateFormatter()
        return nodes.compactMap { node -> Item? in
            guard let number = node["number"]?.number, let title = node["title"]?.string, let url = node["url"]?.string,
                  let repository = node["repository"]?["nameWithOwner"]?.string else { return nil }
            let rollup = node["commits"]?["nodes"]?.array?.first?["commit"]?["statusCheckRollup"]?["state"]?.string
            return Item(number: Int(number), title: title, repository: .init(nameWithOwner: repository), url: url,
                        updatedAt: node["updatedAt"]?.string.flatMap(dates.date(from:)), isDraft: node["isDraft"]?.bool,
                        checks: Item.Checks(rollup: rollup), changesRequested: node["reviewDecision"]?.string == "CHANGES_REQUESTED")
        }
    }

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) -> T? {
        try? decoder.decode(type, from: data)
    }
}
