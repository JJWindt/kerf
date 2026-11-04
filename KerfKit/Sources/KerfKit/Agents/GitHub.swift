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
        public var headRefName: String?
        public var headRepository: Repository?
        /// Someone else's PR that asks you for a review; nil or false for your own.
        public var reviewRequested: Bool?
        public var id: String { url }
    }

    public struct Page: Sendable {
        public var pulls: [Item]
        public var nextCursor: String?
    }

    /// Your open PRs, or with `reviews` the ones asking you for a review: one page of a GraphQL
    /// search for `gh api graphql -f query=…`, paginated so session-linked work is not lost
    /// behind newer unrelated PRs.
    public static func searchQuery(login: String, cursor: String? = nil, reviews: Bool = false) -> String {
        let filter = reviews ? "review-requested:\(login)" : "author:\(login)"
        let query = String(decoding: JSONValue.string("is:pr is:open archived:false \(filter) sort:updated-desc").encoded(), as: UTF8.self)
        let after = cursor.map { ", after: " + String(decoding: JSONValue.string($0).encoded(), as: UTF8.self) } ?? ""
        return """
        query { search(query: \(query), type: ISSUE, first: 100\(after)) { pageInfo { hasNextPage endCursor } nodes { \
        ... on PullRequest { number title url isDraft updatedAt reviewDecision repository { nameWithOwner } \
        headRefName headRepository { nameWithOwner } \
        commits(last: 1) { nodes { commit { statusCheckRollup { state } } } } } } } }
        """
    }

    public static func page(fromSearch data: Data) -> Page? {
        guard let json = JSONValue.parse(data),
              (json["errors"]?.array ?? []).isEmpty,
              let search = json["data"]?["search"],
              let nodes = search["nodes"]?.array,
              let hasNext = search["pageInfo"]?["hasNextPage"]?.bool,
              let pulls = pulls(fromSearch: data), pulls.count == nodes.count else { return nil }
        let cursor = search["pageInfo"]?["endCursor"]?.string
        guard !hasNext || cursor?.isEmpty == false else { return nil }
        return Page(pulls: pulls, nextCursor: hasNext ? cursor : nil)
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
                        checks: Item.Checks(rollup: rollup), changesRequested: node["reviewDecision"]?.string == "CHANGES_REQUESTED",
                        headRefName: node["headRefName"]?.string,
                        headRepository: node["headRepository"]?["nameWithOwner"]?.string.map { .init(nameWithOwner: $0) })
        }
    }

    public static func prioritized(_ pulls: [Item], contexts: [RepositoryContext]) -> [Item] {
        pulls.sorted { left, right in
            let leftLinked = contexts.contains { $0.matches(left) }
            let rightLinked = contexts.contains { $0.matches(right) }
            if leftLinked != rightLinked { return leftLinked }
            if left.updatedAt != right.updatedAt { return (left.updatedAt ?? .distantPast) > (right.updatedAt ?? .distantPast) }
            return left.id < right.id
        }
    }

    public struct Attention: Codable, Equatable, Sendable {
        public struct Status: Codable, Equatable, Sendable {
            public var checksFailed: Bool
            public var changesRequested: Bool
            public var isEmpty: Bool { !checksFailed && !changesRequested }
        }

        private var previous: [String: Status] = [:]
        private var initialized = false
        public private(set) var unread: [String: Status] = [:]

        public init() {}

        public mutating func update(_ pulls: [Item]) {
            var next: [String: Status] = [:]
            var notices: [String: Status] = [:]
            for pull in pulls {
                let old = previous[pull.id]
                let state = Status(checksFailed: pull.checks.map { $0 == .failing } ?? old?.checksFailed ?? false,
                                   changesRequested: pull.changesRequested ?? old?.changesRequested ?? false)
                next[pull.id] = state
                let notice = Status(
                    checksFailed: state.checksFailed && (unread[pull.id]?.checksFailed == true || initialized && old?.checksFailed != true),
                    changesRequested: state.changesRequested && (unread[pull.id]?.changesRequested == true || initialized && old?.changesRequested != true)
                )
                if !notice.isEmpty { notices[pull.id] = notice }
            }
            previous = next
            unread = notices
            initialized = true
        }

        public mutating func acknowledge(_ id: String) { unread.removeValue(forKey: id) }
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
