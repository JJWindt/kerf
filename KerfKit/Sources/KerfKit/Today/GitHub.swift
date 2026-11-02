import Foundation

/// What `gh --json` returns, for the GitHub page.
public enum GitHub {
    public struct Repo: Codable, Equatable, Sendable, Identifiable {
        public var nameWithOwner: String
        public var pushedAt: Date?
        public var isPrivate: Bool?
        public var id: String { nameWithOwner }
        public var name: String { nameWithOwner.split(separator: "/").last.map(String.init) ?? nameWithOwner }
    }

    public struct Item: Codable, Equatable, Sendable, Identifiable {
        public struct Repository: Codable, Equatable, Sendable {
            public var nameWithOwner: String
        }

        public var number: Int
        public var title: String
        public var repository: Repository
        public var url: String
        public var updatedAt: Date?
        public var isDraft: Bool?
        public var id: String { url }
    }

    public struct Run: Codable, Equatable, Sendable, Identifiable {
        public var status: String
        public var conclusion: String?
        public var name: String?
        public var headBranch: String?
        public var createdAt: Date?
        public var url: String
        public var displayTitle: String?
        public var repo: String?
        public var id: String { url }

        public enum State: Sendable {
            case running, passed, failed, other
        }

        public var state: State {
            if status != "completed" { return .running }
            switch conclusion {
            case "success": return .passed
            case "failure", "timed_out", "startup_failure": return .failed
            default: return .other
            }
        }
    }

    public struct TreeEntry: Codable, Equatable, Sendable, Identifiable {
        public var path: String
        public var type: String
        public var size: Int?
        public var id: String { path }
        public var isFolder: Bool { type == "tree" }
        public var name: String { (path as NSString).lastPathComponent }
    }

    struct Tree: Codable {
        var tree: [TreeEntry]
    }

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) -> T? {
        try? decoder.decode(type, from: data)
    }

    public static func tree(from data: Data) -> [TreeEntry] {
        (try? decoder.decode(Tree.self, from: data))?.tree ?? []
    }

    /// The direct children of a folder ("" is the root), folders first.
    public static func children(of folder: String, in tree: [TreeEntry]) -> [TreeEntry] {
        let prefix = folder.isEmpty ? "" : folder + "/"
        return tree
            .filter { $0.path.hasPrefix(prefix) && !$0.path.dropFirst(prefix.count).contains("/") && !$0.path.dropFirst(prefix.count).isEmpty }
            .sorted { ($0.isFolder ? 0 : 1, $0.name.lowercased()) < ($1.isFolder ? 0 : 1, $1.name.lowercased()) }
    }
}
