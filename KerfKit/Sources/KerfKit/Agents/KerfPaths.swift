import Darwin
import Foundation

/// Where the app and the `kerf` command meet.
public enum KerfPaths {
    public static var support: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Kerf", isDirectory: true)
    }

    public static var socket: String { support.appendingPathComponent("kerf.sock").path }

    /// Points at the app's own binary; hooks call this path so they survive the app moving.
    public static var commandLink: URL { support.appendingPathComponent("bin/kerf") }

    /// While this file exists, `kerf hook` keeps every payload in `hookLog`: `kerf log on`.
    public static var hookLogSwitch: URL { support.appendingPathComponent("log-hooks") }
    public static var hookLog: URL { support.appendingPathComponent("hooks.jsonl") }
}

/// Which app a hook runs in, from the process tree: T3 Code, Terminal, Visual Studio Code.
public enum ProcessTree {
    public struct App: Equatable, Sendable {
        public var name: String
        /// The .app bundle, for its icon.
        public var bundlePath: String
    }

    public static func hostApp(of pid: pid_t = getpid()) -> App? {
        var current = parent(of: pid)
        var steps = 0
        while let pid = current, pid > 1, steps < 40 {
            if let path = executablePath(pid), let app = app(containing: path) {
                return app
            }
            current = parent(of: pid)
            steps += 1
        }
        return nil
    }

    /// The outermost .app in an executable's path: a helper inside an app (Electron, Xcode)
    /// counts as that app.
    public static func app(containing path: String) -> App? {
        guard let range = path.range(of: ".app/") else { return nil }
        let bundle = String(path[..<range.lowerBound]) + ".app"
        return App(name: URL(fileURLWithPath: bundle).deletingPathExtension().lastPathComponent, bundlePath: bundle)
    }

    static func parent(of pid: pid_t) -> pid_t? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return pid_t(info.pbi_ppid)
    }

    static func executablePath(_ pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(cString: buffer)
    }
}
