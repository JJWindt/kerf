import AppKit
import KerfKit
import SwiftUI

/// Your open pull requests, through the GitHub CLI you are signed in to. Shown under the threads
/// on the AI page.
@Observable
final class PullRequests {
    static let shared = PullRequests()

    private(set) var pulls: [GitHub.Item] = []
    private(set) var isLoading = false
    @ObservationIgnored private var loadedAt = Date.distantPast
    /// Your GitHub login, for the search; asked once.
    @ObservationIgnored private var login: String?

    nonisolated static var executable: String? {
        ["/opt/homebrew/bin/gh", "/usr/local/bin/gh"].first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Runs `gh` off the main thread.
    nonisolated static func gh(_ arguments: [String]) async -> Data? {
        guard let executable else { return nil }
        return await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            let output = Pipe()
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            guard (try? process.run()) != nil else { return nil }
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return process.terminationStatus == 0 ? data : nil
        }.value
    }

    /// At most every two minutes, when the AI page opens.
    func refreshIfStale() {
        guard Date().timeIntervalSince(loadedAt) > 120, !isLoading, Self.executable != nil else { return }
        Task { await refresh() }
    }

    func refresh() async {
        isLoading = true
        if login == nil, let data = await Self.gh(["api", "user", "--jq", ".login"]) {
            login = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let login, !login.isEmpty {
            // One GraphQL search: the PRs with their checks and reviews, which `gh search prs` leaves out.
            let data = await Self.gh(["api", "graphql", "-f", "query=\(GitHub.searchQuery(login: login))"])
            pulls = data.flatMap(GitHub.pulls(fromSearch:)) ?? []
        } else {
            pulls = []
        }
        loadedAt = .now
        isLoading = false
        IslandManager.current?.refit()
    }

    /// Lab only.
    func preview(pulls: [GitHub.Item]) {
        self.pulls = pulls
        loadedAt = .now
    }

    func open(_ link: String) {
        if let url = URL(string: link) { NSWorkspace.shared.open(url) }
    }
}
