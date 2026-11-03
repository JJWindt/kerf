import Foundation

/// What `gh --json` returns for the open pull requests on the AI page.
public enum GitHub {
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

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) -> T? {
        try? decoder.decode(type, from: data)
    }
}
