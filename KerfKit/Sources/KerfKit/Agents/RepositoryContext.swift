import Foundation

public struct RepositoryContext: Equatable, Sendable {
    public var id: String
    public var branch: String?
    public var revision: String
    public var repositories: Set<String>

    public init(id: String, branch: String?, revision: String, repositories: Set<String>) {
        self.id = id
        self.branch = branch
        self.revision = revision
        self.repositories = repositories
    }

    public var label: String { branch ?? revision }

    public func matches(_ pull: GitHub.Item) -> Bool {
        guard let branch, let head = pull.headRepository else { return false }
        return pull.headRefName == branch && repositories.contains(head.nameWithOwner.lowercased())
    }

    public static func needsBranch(_ context: RepositoryContext, among contexts: [RepositoryContext]) -> Bool {
        contexts.lazy.filter { $0.id == context.id }.prefix(2).count > 1
    }

    public static func githubRepository(_ remote: String) -> String? {
        let path: String
        if remote.hasPrefix("git@github.com:") {
            path = String(remote.dropFirst("git@github.com:".count))
        } else if let url = URL(string: remote), url.host?.lowercased() == "github.com" {
            path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        } else {
            return nil
        }
        let name = path.hasSuffix(".git") ? String(path.dropLast(4)) : path
        guard name.split(separator: "/").count == 2 else { return nil }
        return name.lowercased()
    }

    public static func read(at directory: String) throws -> RepositoryContext? {
        var root = URL(fileURLWithPath: directory).standardizedFileURL
        while !FileManager.default.fileExists(atPath: root.appendingPathComponent(".git").path) {
            let parent = root.deletingLastPathComponent()
            guard parent != root else { return nil }
            root = parent
        }
        let common = try git(["rev-parse", "--path-format=absolute", "--git-common-dir"], at: directory)
        // An unborn branch has a name, but no commit yet.
        let head = try git(["symbolic-ref", "--quiet", "--short", "HEAD"], at: directory, allowedStatuses: [0, 1])
        let revision = head.isEmpty ? try git(["rev-parse", "--short", "HEAD"], at: directory) : ""
        let remotes = try git(["remote", "-v"], at: directory).split(separator: "\n")
        let repositories = Set(remotes.compactMap { line -> String? in
            let parts = line.split(whereSeparator: \.isWhitespace)
            guard parts.count >= 3, parts[2] == "(fetch)" else { return nil }
            return githubRepository(String(parts[1]))
        })
        return RepositoryContext(id: URL(fileURLWithPath: common).resolvingSymlinksInPath().path,
                                 branch: head.isEmpty ? nil : head, revision: revision, repositories: repositories)
    }

    private static func git(_ arguments: [String], at directory: String, allowedStatuses: Set<Int32> = [0]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", directory] + arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard allowedStatuses.contains(process.terminationStatus) else {
            throw NSError(domain: "Kerf.Git", code: Int(process.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: "Couldn't read repository context (\(arguments.first ?? "git"))."])
        }
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
