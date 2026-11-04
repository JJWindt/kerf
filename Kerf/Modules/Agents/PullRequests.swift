import AppKit
import KerfKit
import OSLog
import SwiftUI

/// Your open PRs and the ones asking you for a review, through the GitHub CLI you are signed in
/// to. Refreshed quietly even while the island is closed.
@Observable
final class PullRequests {
    static let shared = PullRequests()

    private(set) var pulls: [GitHub.Item] = []
    private(set) var isLoading = false
    private(set) var failure: String?
    private(set) var attention = GitHub.Attention()
    @ObservationIgnored private var loadedAt = Date.distantPast
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var login: String?
    private let logger = Logger(subsystem: "nl.jjwindt.kerf", category: "PullRequests")

    var attentionCount: Int { attention.unread.count }
    var hasFailedChecks: Bool { attention.unread.values.contains(where: \.checksFailed) }

    nonisolated static var executable: String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let paths = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map { "\($0)/gh" }
        return (["\(home)/.local/bin/gh", "/opt/homebrew/bin/gh", "/usr/local/bin/gh"] + paths)
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    nonisolated private static func gh(_ arguments: [String]) async throws -> Data {
        guard let executable else { throw FetchError.unavailable }
        return try await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            let output = Pipe()
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            try process.run()
            let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 30, execute: timeout)
            defer { timeout.cancel() }
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { throw FetchError.commandFailed }
            return data
        }.value
    }

    private enum FetchError: Error {
        case unavailable, commandFailed, invalidResponse
    }

    func start() {
        guard pollTask == nil else { return }
        pollTask = Task {
            while !Task.isCancelled {
                await refresh()
                do { try await Task.sleep(for: .seconds(120)) }
                catch { return }
            }
        }
    }

    func refreshIfStale() {
        guard Date().timeIntervalSince(loadedAt) > 120, !isLoading else { return }
        Task { await refresh() }
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer {
            loadedAt = .now
            isLoading = false
            Hub.shared.refresh()
            IslandManager.current?.refit()
        }
        do {
            // Recheck identity so a gh account switch never mixes authors or alert baselines.
            let user = try await Self.gh(["api", "user", "--jq", ".login"])
            let currentLogin = String(decoding: user, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !currentLogin.isEmpty else { throw FetchError.invalidResponse }
            if currentLogin != login {
                login = currentLogin
                pulls = []
                attention = GitHub.Attention()
                if let data = UserDefaults.standard.data(forKey: attentionKey) {
                    do { attention = try JSONDecoder().decode(GitHub.Attention.self, from: data) }
                    catch { logger.error("PR attention history: \(error.localizedDescription, privacy: .public)") }
                }
            }
            let authored = try await Self.search(login: currentLogin, reviews: false)
            let reviews = try await Self.search(login: currentLogin, reviews: true).map { pull in
                var pull = pull
                pull.reviewRequested = true
                return pull
            }
            let fetched = authored + reviews.filter { review in !authored.contains { $0.id == review.id } }
            failure = nil
            // Alerts are for your own PRs: a review request shows in the list, it doesn't call.
            attention.update(authored)
            saveAttention()
            pulls = fetched
            prioritize()
        } catch {
            logger.error("PR refresh: \(String(describing: error), privacy: .public)")
            failure = Self.executable == nil
                ? String(localized: "GitHub CLI isn't installed. Pull requests are unavailable.")
                : String(localized: "Couldn't refresh pull requests. Check GitHub CLI sign-in and connection.")
        }
    }

    /// Every page of one search.
    private static func search(login: String, reviews: Bool) async throws -> [GitHub.Item] {
        var fetched: [GitHub.Item] = []
        var cursor: String?
        var visited: Set<String> = []
        repeat {
            let data = try await gh(["api", "graphql", "-f", "query=\(GitHub.searchQuery(login: login, cursor: cursor, reviews: reviews))"])
            guard let page = GitHub.page(fromSearch: data) else { throw FetchError.invalidResponse }
            fetched += page.pulls
            cursor = page.nextCursor
            if let cursor, !visited.insert(cursor).inserted { throw FetchError.invalidResponse }
        } while cursor != nil
        return fetched
    }

    func prioritize() {
        pulls = GitHub.prioritized(pulls, contexts: AgentCenter.shared.visibleThreads.compactMap(\.repository))
    }

    func needsAttention(_ pull: GitHub.Item) -> Bool { attention.unread[pull.id] != nil }

    private var attentionKey: String { "agents.pullAttention.\(login ?? "")" }

    private func saveAttention() {
        do { UserDefaults.standard.set(try JSONEncoder().encode(attention), forKey: attentionKey) }
        catch {
            logger.error("Saving PR attention: \(error.localizedDescription, privacy: .public)")
            failure = String(localized: "Couldn't save pull request alerts.")
        }
    }

    /// Lab only; no gh calls or saved alert history.
    func preview(pulls: [GitHub.Item], changed: [GitHub.Item]? = nil) {
        attention = GitHub.Attention()
        attention.update(pulls.filter { $0.reviewRequested != true })
        if let changed { attention.update(changed.filter { $0.reviewRequested != true }) }
        self.pulls = changed ?? pulls
        prioritize()
        loadedAt = .now
        Hub.shared.refresh()
    }

    func open(_ link: String) {
        guard let url = URL(string: link) else {
            failure = String(localized: "Couldn't open the pull request.")
            return
        }
        guard NSWorkspace.shared.open(url) else {
            failure = String(localized: "Couldn't open the pull request.")
            return
        }
        attention.acknowledge(link)
        saveAttention()
        Hub.shared.refresh()
    }
}
