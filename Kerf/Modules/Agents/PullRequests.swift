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

    var attentionCount: Int { attention.unread.count + attention.unreadMerges.count }
    /// The most pressing news, for the closed notch.
    var tone: PullTone {
        if attention.unread.values.contains(where: \.checksFailed) { return .failed }
        return attention.unread.isEmpty ? .merged : .changes
    }

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
            // Yours merged in the last day stay in the list that long.
            let merged = try await Self.search(login: currentLogin, reviews: false, mergedSince: .now.addingTimeInterval(-86_400))
            let fetched = authored + reviews.filter { review in !authored.contains { $0.id == review.id } } + merged
            failure = nil
            observe(fetched)
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
    private static func search(login: String, reviews: Bool, mergedSince: Date? = nil) async throws -> [GitHub.Item] {
        var fetched: [GitHub.Item] = []
        var cursor: String?
        var visited: Set<String> = []
        repeat {
            let data = try await gh(["api", "graphql", "-f", "query=\(GitHub.searchQuery(login: login, cursor: cursor, reviews: reviews, mergedSince: mergedSince))"])
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

    /// Alerts for your open PRs, news for your merged ones; a review request shows in the list,
    /// it doesn't call.
    private func observe(_ pulls: [GitHub.Item]) {
        let own = pulls.filter { $0.reviewRequested != true }
        attention.update(own.filter { $0.mergedAt == nil })
        attention.updateMerged(own.filter { $0.mergedAt != nil })
    }

    /// The list was on screen: merges need nothing more.
    func sawMerges() {
        guard !attention.unreadMerges.isEmpty else { return }
        attention.sawMerges()
        saveAttention()
        Hub.shared.refresh()
    }

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
        observe(pulls)
        if let changed { observe(changed) }
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
