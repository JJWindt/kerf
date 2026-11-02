import Foundation

/// What the system says is playing, as the MediaRemote adapter reports it: Music, Spotify,
/// podcasts, and a YouTube tab in Safari or Chrome, which the island leaves out (`parseMusic`).
public struct NowPlayingState: Equatable, Sendable {
    public var title: String
    public var artist: String
    public var album: String
    /// Seconds; nil for live streams.
    public var duration: Double?
    /// Seconds into the track at `timestamp`.
    public var elapsed: Double
    public var timestamp: Date
    public var isPlaying: Bool
    public var rate: Double
    /// The app to show and open: Safari rather than WebKit's GPU process.
    public var sourceBundleID: String
    public var artwork: Data?
    /// The process that makes the sound, for listening to just that app.
    public var processID: Int32?

    public init(title: String, artist: String = "", album: String = "", duration: Double? = nil, elapsed: Double = 0,
                timestamp: Date = .now, isPlaying: Bool = false, rate: Double = 1, sourceBundleID: String = "", artwork: Data? = nil,
                processID: Int32? = nil) {
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.elapsed = elapsed
        self.timestamp = timestamp
        self.isPlaying = isPlaying
        self.rate = rate
        self.sourceBundleID = sourceBundleID
        self.artwork = artwork
        self.processID = processID
    }

    /// Reads one line of `stream --no-diff`, or the output of `get`. Nil when nothing plays.
    public static func parse(_ line: Data) -> NowPlayingState? {
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { return nil }
        let payload = (object["payload"] as? [String: Any]) ?? object
        guard let title = payload["title"] as? String, !title.isEmpty else { return nil }
        let parent = payload["parentApplicationBundleIdentifier"] as? String
        let bundle = payload["bundleIdentifier"] as? String ?? ""
        let rate = payload["playbackRate"] as? Double ?? 1
        let timestamp = (payload["timestamp"] as? String).flatMap { try? Date($0, strategy: .iso8601) } ?? .now
        return NowPlayingState(
            title: title,
            artist: payload["artist"] as? String ?? "",
            album: payload["album"] as? String ?? "",
            duration: (payload["duration"] as? Double).flatMap { $0 > 0 ? $0 : nil },
            elapsed: payload["elapsedTime"] as? Double ?? 0,
            timestamp: timestamp,
            isPlaying: payload["playing"] as? Bool ?? false,
            rate: rate,
            sourceBundleID: parent ?? bundle,
            artwork: (payload["artworkData"] as? String).flatMap { Data(base64Encoded: $0) },
            processID: (payload["processIdentifier"] as? Int).map(Int32.init)
        )
    }

    /// `parse`, without what a browser plays: a video in Safari isn't music, and in the notch it
    /// distracts.
    public static func parseMusic(_ line: Data) -> NowPlayingState? {
        parse(line).flatMap { $0.playsInBrowser ? nil : $0 }
    }

    public var playsInBrowser: Bool {
        Self.browsers.contains { sourceBundleID == $0 || sourceBundleID.hasPrefix($0 + ".") }
    }

    /// With their betas, web apps and helpers (`com.apple.Safari.WebApp.…`, `com.google.Chrome.canary`),
    /// and WebKit itself when no app is named.
    static let browsers = [
        "com.apple.Safari", "com.apple.SafariTechnologyPreview", "com.apple.WebKit", "com.google.Chrome",
        "org.chromium.Chromium", "com.microsoft.edgemac", "company.thebrowser.Browser", "company.thebrowser.dia",
        "org.mozilla.firefox", "org.mozilla.firefoxdeveloperedition", "org.mozilla.nightly", "com.brave.Browser",
        "com.operasoftware.Opera", "com.operasoftware.OperaGX", "com.vivaldi.Vivaldi", "com.kagi.kagimacOS",
        "app.zen-browser.zen", "com.duckduckgo.macos.browser",
    ]

    /// The track itself, apart from where it is and whether it plays.
    public var track: String { [sourceBundleID, title, artist, album].joined(separator: "\u{1F}") }

    /// Whether this is a new track still carrying the last one's cover: Spotify sometimes sends
    /// the new title before the new artwork. Tracks of one album share their cover, so that stays.
    public func hasStaleArtwork(after previous: NowPlayingState?) -> Bool {
        guard let artwork, let previous, previous.track != track, previous.artwork == artwork else { return false }
        return album.isEmpty && previous.album.isEmpty ? artist != previous.artist : album != previous.album
    }

    /// Where the track is at a moment, running on while it plays and never past its end.
    public func elapsed(at date: Date) -> Double {
        var value = elapsed
        if isPlaying { value += date.timeIntervalSince(timestamp) * max(rate, 0) }
        if let duration { value = min(value, duration) }
        return max(value, 0)
    }

    /// "1:05", "12:40" or "1:02:03".
    public static func clock(_ seconds: Double) -> String {
        let total = Int(seconds.rounded(.down))
        let (h, m, s) = (total / 3600, (total % 3600) / 60, total % 60)
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}
