import Foundation

/// The exact place a thread runs in, so a click brings up that tab, window or session and not
/// just the app.
public enum ThreadLink: Equatable, Sendable {
    /// Terminal or iTerm2: the tab on this tty, through AppleScript.
    case terminalTab(script: String)
    /// A Claude desktop session, through its own deep link.
    case url(URL)
    /// An editor (VS Code, Cursor, Xcode): its window whose title names the project.
    case window(project: String)
    /// Only the app.
    case app

    /// What to open for a thread in `host` (the .app bundle path).
    public static func of(host: String?, tty: String?, project: String?, desktopSessionID: String?) -> ThreadLink {
        let name = host.map { URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent }
        switch name {
        case "Terminal":
            if let tty, isTTY(tty) { return .terminalTab(script: terminalScript(tty)) }
        case "iTerm", "iTerm2":
            if let tty, isTTY(tty) { return .terminalTab(script: iTermScript(tty)) }
        case "Claude":
            if let id = desktopSessionID, let url = desktopURL(id) { return .url(url) }
        default:
            if let project, !project.isEmpty { return .window(project: project) }
        }
        return .app
    }

    /// `claude://code/continue?session=local_…` opens that session in the Claude desktop app.
    public static func desktopURL(_ sessionID: String) -> URL? {
        guard sessionID.range(of: #"^local_[A-Za-z0-9-]{1,64}$"#, options: .regularExpression) != nil else { return nil }
        var parts = URLComponents(string: "claude://code/continue")
        parts?.queryItems = [URLQueryItem(name: "session", value: sessionID)]
        return parts?.url
    }

    /// The desktop app's id for a Claude Code session, from its session files
    /// (`claude-code-sessions/<account>/<org>/local_….json`, each with the CLI's `cliSessionId`).
    public static func desktopSessionID(forCLI cliID: String, in folder: URL) -> String? {
        let files = FileManager.default
        guard let accounts = try? files.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { return nil }
        for account in accounts {
            for org in (try? files.contentsOfDirectory(at: account, includingPropertiesForKeys: nil)) ?? [] {
                for file in (try? files.contentsOfDirectory(at: org, includingPropertiesForKeys: nil)) ?? []
                where file.lastPathComponent.hasPrefix("local_") && file.pathExtension == "json" {
                    guard let data = try? Data(contentsOf: file), let json = JSONValue.parse(data),
                          json["cliSessionId"]?.string == cliID, let id = json["sessionId"]?.string else { continue }
                    return id
                }
            }
        }
        return nil
    }

    /// Whether a window title names the project as one of its parts: "Foo.swift — kerf — Visual
    /// Studio Code" names kerf, "kerf-upstream" doesn't.
    public static func title(_ title: String, names project: String) -> Bool {
        var parts = [title]
        for separator in [" — ", " – ", " - ", " | "] {
            parts = parts.flatMap { $0.components(separatedBy: separator) }
        }
        return parts.contains { $0.trimmingCharacters(in: .whitespaces) == project }
    }

    static func isTTY(_ tty: String) -> Bool {
        tty.range(of: #"^/dev/tty[A-Za-z0-9]+$"#, options: .regularExpression) != nil
    }

    static func terminalScript(_ tty: String) -> String {
        """
        tell application "Terminal"
            repeat with w in windows
                repeat with t in tabs of w
                    if tty of t is "\(tty)" then
                        set selected tab of w to t
                        set index of w to 1
                        activate
                        return
                    end if
                end repeat
            end repeat
            activate
        end tell
        """
    }

    static func iTermScript(_ tty: String) -> String {
        """
        tell application "iTerm2"
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        if tty of s is "\(tty)" then
                            select w
                            select t
                            select s
                            activate
                            return
                        end if
                    end repeat
                end repeat
            end repeat
            activate
        end tell
        """
    }
}
