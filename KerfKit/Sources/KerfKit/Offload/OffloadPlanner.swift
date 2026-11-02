import Foundation

/// Folder names for a project, editable in Settings. The default: short, no numbers.
public struct OffloadTemplate: Codable, Equatable, Sendable {
    public var projectsFolder: String
    public var footage: String
    public var audio: String
    public var cardPrefix: String
    public var extraFolders: [String]

    public static let dutch = OffloadTemplate(projectsFolder: "Projecten", footage: "Beelden", audio: "Geluid", cardPrefix: "Kaart",
                                              extraFolders: ["Assets", "Export", "Temp"])
    public static let english = OffloadTemplate(projectsFolder: "Projects", footage: "Footage", audio: "Audio", cardPrefix: "Card",
                                                extraFolders: ["Assets", "Export", "Temp"])
}

/// Where a card goes: `<drive>/Projecten/<project>/Beelden/<camera>/Kaart 01/`, card structure kept.
public struct OffloadPlan: Sendable {
    public struct Item: Sendable {
        public var source: URL
        public var destination: URL
        public var file: CardFile
    }

    public var projectFolder: URL
    public var cardFolder: URL
    public var camera: String
    public var cardNumber: Int
    public var items: [Item]

    public var totalBytes: Int64 { items.reduce(0) { $0 + $1.file.size } }
}

public enum OffloadPlanner {
    /// A project name that is safe as a folder name.
    public static func folderName(_ name: String) -> String {
        let cleaned = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
        return cleaned.isEmpty ? "Project" : cleaned
    }

    /// "Kaart 01", "Kaart 2", "kaart 12" → the next free number.
    public static func nextCardNumber(existing: [String], prefix: String) -> Int {
        let numbers = existing.compactMap { name -> Int? in
            guard name.lowercased().hasPrefix(prefix.lowercased()) else { return nil }
            return Int(name.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces))
        }
        return (numbers.max() ?? 0) + 1
    }

    public static func cardFolderName(prefix: String, number: Int) -> String {
        "\(prefix) \(String(format: "%02d", number))"
    }

    /// Projects on a drive, most recently changed first.
    public static func projects(on drive: URL, template: OffloadTemplate) -> [String] {
        let folder = drive.appendingPathComponent(template.projectsFolder, isDirectory: true)
        let keys: [URLResourceKey] = [.isDirectoryKey, .contentModificationDateKey]
        let items = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])) ?? []
        return items
            .compactMap { url -> (String, Date)? in
                let values = try? url.resourceValues(forKeys: Set(keys))
                guard values?.isDirectory == true else { return nil }
                return (url.lastPathComponent, values?.contentModificationDate ?? .distantPast)
            }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }

    public static func plan(card: CameraCard, cardRoot: URL, drive: URL, project: String, template: OffloadTemplate) -> OffloadPlan {
        let projectFolder = drive.appendingPathComponent(template.projectsFolder, isDirectory: true)
            .appendingPathComponent(folderName(project), isDirectory: true)
        let cameraFolder = projectFolder.appendingPathComponent(card.kind == .audio ? template.audio : template.footage, isDirectory: true)
            .appendingPathComponent(folderName(card.name), isDirectory: true)
        let existing = (try? FileManager.default.contentsOfDirectory(atPath: cameraFolder.path)) ?? []
        let number = nextCardNumber(existing: existing, prefix: template.cardPrefix)
        let cardFolder = cameraFolder.appendingPathComponent(cardFolderName(prefix: template.cardPrefix, number: number), isDirectory: true)
        let items = card.files.map {
            OffloadPlan.Item(source: cardRoot.appendingPathComponent($0.path), destination: cardFolder.appendingPathComponent($0.path), file: $0)
        }
        return OffloadPlan(projectFolder: projectFolder, cardFolder: cardFolder, camera: card.name, cardNumber: number, items: items)
    }
}

/// What is already in a project, so a card put in twice copies nothing twice. Kept in the
/// project's hidden `.kerf` folder.
public struct IngestIndex: Codable, Sendable {
    public struct Entry: Codable, Equatable, Sendable {
        public var camera: String
        public var name: String
        public var size: Int64
        public var modified: Date
        public var hash: String
        public var destination: String
    }

    public var entries: [Entry] = []

    public init() {}

    public static func url(in project: URL) -> URL {
        project.appendingPathComponent(".kerf/ingest.json")
    }

    public static func load(project: URL) -> IngestIndex {
        guard let data = try? Data(contentsOf: url(in: project)) else { return IngestIndex() }
        return (try? JSONDecoder().decode(IngestIndex.self, from: data)) ?? IngestIndex()
    }

    public func save(project: URL) throws {
        let url = Self.url(in: project)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }

    /// An earlier copy of the same file from the same camera: same name, size and date.
    public func candidate(camera: String, file: CardFile) -> Entry? {
        let name = (file.path as NSString).lastPathComponent
        return entries.first {
            $0.camera == camera && $0.name == name && $0.size == file.size && abs($0.modified.timeIntervalSince(file.modified)) < 2
        }
    }
}
