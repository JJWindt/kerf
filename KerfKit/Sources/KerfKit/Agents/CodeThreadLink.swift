import Foundation
import SQLite3

/// A chat in P3 Code or T3 Code, found by the session id its agent reports to the hooks, as a
/// link that opens that chat. Both keep their threads in `statev2.sqlite` and open
/// `t3code://threads/<environment>/<thread>`.
public enum CodeThreadLink {
    /// The app's data folder, by the app's name; nil for apps that aren't P3 or T3 Code.
    public static func dataFolder(forApp name: String, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL? {
        if name.hasPrefix("P3 Code") { return home.appendingPathComponent(".p3code/userdata", isDirectory: true) }
        if name.hasPrefix("T3 Code") { return home.appendingPathComponent(".t3/userdata", isDirectory: true) }
        return nil
    }

    /// The link for the chat that runs `sessionID` in the app at `hostPath`, if it has one.
    public static func url(hostPath: String, sessionID: String, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL? {
        let name = URL(fileURLWithPath: hostPath).deletingPathExtension().lastPathComponent
        guard !sessionID.isEmpty, let folder = dataFolder(forApp: name, home: home),
              let environment = try? String(contentsOf: folder.appendingPathComponent("environment-id"), encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines), !environment.isEmpty,
              let thread = threadID(database: folder.appendingPathComponent("statev2.sqlite").path, sessionID: sessionID) else { return nil }
        return link(environment: environment, thread: thread)
    }

    public static func link(environment: String, thread: String) -> URL? {
        var components = URLComponents()
        components.scheme = "t3code"
        components.host = "threads"
        components.path = "/\(environment)/\(thread)"
        return components.url
    }

    /// The app's thread whose agent session is `sessionID`: Claude Code's session or Codex's thread.
    static func threadID(database path: String, sessionID: String) -> String? {
        var database: OpaquePointer?
        defer { sqlite3_close(database) }
        guard FileManager.default.fileExists(atPath: path),
              sqlite3_open_v2(path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return nil }
        sqlite3_busy_timeout(database, 250)
        let query = """
            SELECT thread_id FROM orchestration_v2_projection_provider_threads
            WHERE json_extract(payload_json, '$.nativeThreadRef.nativeId') = ?1 AND thread_id IS NOT NULL
            ORDER BY updated_at DESC LIMIT 1
            """
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK else { return nil }
        // SQLITE_TRANSIENT: SQLite copies the text.
        sqlite3_bind_text(statement, 1, sessionID, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        guard sqlite3_step(statement) == SQLITE_ROW, let text = sqlite3_column_text(statement, 0) else { return nil }
        return String(cString: text)
    }
}
