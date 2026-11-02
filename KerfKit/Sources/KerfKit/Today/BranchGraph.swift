import Foundation

/// A repo's recent commits over all its branches, laid out in lanes like `git log --graph`.
extension GitHub {
    public struct Commit: Equatable, Sendable, Identifiable {
        public var id: String
        public var headline: String
        public var date: Date
        public var parents: [String]
        /// Branches whose newest commit this is.
        public var branches: [String]

        public init(id: String, headline: String, date: Date, parents: [String], branches: [String] = []) {
            self.id = id
            self.headline = headline
            self.date = date
            self.parents = parents
            self.branches = branches
        }

        public var isMerge: Bool { parents.count > 1 }
    }

    /// One commit's row: its lane, and the lines that cross the row. Lanes never move, so a line
    /// leaving a row's bottom at lane i enters the next row's top at lane i.
    public struct GraphRow: Equatable, Sendable, Identifiable {
        public var commit: Commit
        public var lane: Int
        /// Lanes whose line comes down from the top edge into the commit: its children.
        public var incoming: [Int]
        /// Lanes the commit's line goes down to at the bottom edge: its parents.
        public var outgoing: [Int]
        /// Lanes that pass the row on their way to an older commit.
        public var through: [Int]
        public var id: String { commit.id }

        /// The widest lane this row touches, plus one.
        public var width: Int { ([lane] + incoming + outgoing + through).max().map { $0 + 1 } ?? 1 }
    }

    /// The newest commits of the ten most recent branches, for `gh api graphql`.
    public static let branchQuery = """
    query($owner: String!, $name: String!) {
      repository(owner: $owner, name: $name) {
        refs(refPrefix: "refs/heads/", first: 10, orderBy: {field: TAG_COMMIT_DATE, direction: DESC}) {
          nodes {
            name
            target {
              oid
              ... on Commit {
                history(first: 20) { nodes { oid messageHeadline committedDate parents(first: 3) { nodes { oid } } } }
              }
            }
          }
        }
      }
    }
    """

    struct BranchResponse: Decodable {
        struct Payload: Decodable { var repository: Repository? }
        struct Repository: Decodable { var refs: Nodes<Branch> }
        struct Nodes<T: Decodable>: Decodable { var nodes: [T] }
        struct Branch: Decodable { var name: String; var target: Target? }
        struct Target: Decodable { var oid: String; var history: Nodes<Node>? }
        struct Node: Decodable { var oid: String; var messageHeadline: String; var committedDate: Date; var parents: Nodes<Oid> }
        struct Oid: Decodable { var oid: String }
        var data: Payload
    }

    /// The commits from `branchQuery`'s answer: newest first, never a parent above its child.
    public static func commits(fromBranchQuery data: Data, limit: Int = 30) -> [Commit] {
        guard let branches = (try? decoder.decode(BranchResponse.self, from: data))?.data.repository?.refs.nodes else { return [] }
        var byID: [String: Commit] = [:]
        for branch in branches {
            for node in branch.target?.history?.nodes ?? [] where byID[node.oid] == nil {
                byID[node.oid] = Commit(id: node.oid, headline: node.messageHeadline, date: node.committedDate, parents: node.parents.nodes.map(\.oid))
            }
            if let head = branch.target?.oid { byID[head]?.branches.append(branch.name) }
        }
        return Array(ordered(Array(byID.values)).prefix(limit))
    }

    /// Newest first, but a child always above its parents, whatever the clocks said.
    public static func ordered(_ commits: [Commit]) -> [Commit] {
        let byID = Dictionary(commits.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var waitingChildren: [String: Int] = [:]
        for commit in byID.values {
            for parent in Set(commit.parents) where byID[parent] != nil { waitingChildren[parent, default: 0] += 1 }
        }
        var ready = byID.values.filter { waitingChildren[$0.id] == nil }
        var result: [Commit] = []
        while let index = ready.indices.max(by: { (ready[$0].date, ready[$0].id) < (ready[$1].date, ready[$1].id) }) {
            let next = ready.remove(at: index)
            result.append(next)
            for parent in Set(next.parents) where byID[parent] != nil {
                waitingChildren[parent, default: 1] -= 1
                if waitingChildren[parent] == 0, let commit = byID[parent] { ready.append(commit) }
            }
        }
        return result
    }

    /// Lanes for ordered commits. A first parent continues its child's lane; another parent takes
    /// the lane already waiting for it, or a free one. Parents outside the list end their line.
    public static func graph(_ commits: [Commit]) -> [GraphRow] {
        let shown = Set(commits.map(\.id))
        var lanes: [String?] = []
        var rows: [GraphRow] = []
        func freeLane() -> Int {
            if let free = lanes.firstIndex(of: nil) { return free }
            lanes.append(nil)
            return lanes.count - 1
        }
        for commit in commits {
            let above = lanes
            let incoming = lanes.indices.filter { lanes[$0] == commit.id }
            let lane = incoming.first ?? freeLane()
            for index in incoming { lanes[index] = nil }
            var outgoing: [Int] = []
            for (number, parent) in commit.parents.filter(shown.contains).enumerated() {
                if number == 0 {
                    lanes[lane] = parent
                    outgoing.append(lane)
                } else if let waiting = lanes.firstIndex(of: parent) {
                    outgoing.append(waiting)
                } else {
                    let free = freeLane()
                    lanes[free] = parent
                    outgoing.append(free)
                }
            }
            while let last = lanes.last, last == nil { lanes.removeLast() }
            let through = above.indices.filter { index in
                guard let waiting = above[index], waiting != commit.id else { return false }
                return index < lanes.count && lanes[index] == waiting
            }
            rows.append(GraphRow(commit: commit, lane: lane, incoming: incoming, outgoing: outgoing, through: through))
        }
        return rows
    }
}
