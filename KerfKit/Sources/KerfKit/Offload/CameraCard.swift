import Foundation

public struct CardFile: Equatable, Sendable {
    /// Relative to the card's root.
    public var path: String
    public var size: Int64
    public var modified: Date

    public init(path: String, size: Int64, modified: Date = .distantPast) {
        self.path = path
        self.size = size
        self.modified = modified
    }
}

/// A camera or recorder card, recognised by the folders its maker writes.
public struct CameraCard: Equatable, Sendable {
    public enum Kind: Sendable {
        case video, audio
    }

    public var brand: String
    public var model: String?
    public var kind: Kind
    /// Everything to copy, system clutter left out.
    public var files: [CardFile]
    /// Clips, photos or recordings, without sidecars and proxies.
    public var mediaCount: Int

    public init(brand: String, model: String?, kind: Kind, files: [CardFile], mediaCount: Int) {
        self.brand = brand
        self.model = model
        self.kind = kind
        self.files = files
        self.mediaCount = mediaCount
    }

    public var totalBytes: Int64 { files.reduce(0) { $0 + $1.size } }

    /// "Sony FX3", "GoPro", "Zoom".
    public var name: String {
        guard let model else { return brand }
        return model.localizedCaseInsensitiveContains(brand) ? model : "\(brand) \(model)"
    }
}

public enum CardScanner {
    static let video: Set<String> = ["MP4", "MOV", "MXF", "BRAW", "R3D", "CRM", "MTS", "M2TS", "AVI", "INSV", "INSP", "360"]
    static let photo: Set<String> = ["JPG", "JPEG", "HEIC", "HIF", "ARW", "CR2", "CR3", "NEF", "RAF", "RW2", "DNG", "ORF", "GPR"]
    static let audio: Set<String> = ["WAV", "BWF", "MP3", "M4A", "AAC", "FLAC"]

    /// Folders and files a copy should never take along.
    public static func isClutter(_ path: String) -> Bool {
        path.split(separator: "/").contains { $0.hasPrefix(".") || $0 == "System Volume Information" || $0 == "$RECYCLE.BIN" }
    }

    /// Recognises a card from its files (paths relative to the card's root). Nil when it holds no media.
    public static func recognise(_ files: [CardFile], sonyModel: String? = nil) -> CameraCard? {
        let files = files.filter { !isClutter($0.path) }
        let upper = files.map { $0.path.uppercased() }
        func ext(_ path: String) -> String { (path as NSString).pathExtension }
        let videos = upper.filter { video.contains(ext($0)) }
        let photos = upper.filter { photo.contains(ext($0)) }
        let sounds = upper.filter { audio.contains(ext($0)) }
        let media = videos.count + photos.count + sounds.count
        guard media > 0 else { return nil }
        let has = { (needle: String) in upper.contains { $0.contains(needle) } }
        let dcim = upper.filter { $0.hasPrefix("DCIM/") }.compactMap { $0.split(separator: "/").dropFirst().first.map(String.init) }

        var brand = "Camera"
        var kind = CameraCard.Kind.video
        if has("PRIVATE/M4ROOT/") || has("PRIVATE/XDROOT/") || has("PRIVATE/AVCHD/") || dcim.contains(where: { $0.hasSuffix("MSDCF") }) {
            brand = "Sony"
        } else if dcim.contains(where: { $0.hasSuffix("GOPRO") }) {
            brand = "GoPro"
        } else if upper.contains(where: { ($0 as NSString).lastPathComponent.hasPrefix("DJI_") }) || dcim.contains(where: { $0.hasPrefix("DJI_") }) {
            brand = "DJI"
            if videos.isEmpty, photos.isEmpty { brand = "DJI Mic"; kind = .audio }
        } else if dcim.contains(where: { $0.hasSuffix("CANON") }) || has("CONTENTS/CLIPS0") {
            brand = "Canon"
        } else if upper.contains(where: { $0.hasSuffix(".BRAW") }) {
            brand = "Blackmagic"
        } else if has("PRIVATE/PANA_GRP") || dcim.contains(where: { $0.hasSuffix("_PANA") }) {
            brand = "Panasonic"
        } else if dcim.contains(where: { $0.hasSuffix("_FUJI") }) {
            brand = "Fujifilm"
        } else if dcim.contains(where: { $0.hasSuffix("NIKON") || $0.hasSuffix("NCZ_6") }) {
            brand = "Nikon"
        } else if videos.isEmpty, photos.isEmpty {
            kind = .audio
            brand = upper.contains(where: { $0.contains("ZOOM") || $0.hasPrefix("FOLDER0") }) ? "Zoom"
                : upper.contains(where: { $0.hasPrefix("SOUND/") || $0.hasPrefix("MUSIC/") }) ? "Tascam"
                : "Audio"
        }
        return CameraCard(brand: brand, model: brand == "Sony" ? sonyModel : nil, kind: kind, files: files, mediaCount: media)
    }

    /// Sony writes the camera in every clip's XML sidecar: `modelName="ILME-FX3"`.
    public static func sonyModel(fromXML xml: String) -> String? {
        guard let range = xml.range(of: #"modelName="([^"]+)""#, options: .regularExpression) else { return nil }
        let code = String(xml[range]).replacingOccurrences(of: "modelName=", with: "").replacingOccurrences(of: "\"", with: "")
        let names = [
            "ILME-FX3": "FX3", "ILME-FX30": "FX30", "ILME-FX6": "FX6", "ILME-FX6V": "FX6", "ILME-FX9": "FX9", "ILME-FX2": "FX2",
            "ILCE-7SM3": "A7S III", "ILCE-7M4": "A7 IV", "ILCE-7M5": "A7 V", "ILCE-7CM2": "A7C II", "ILCE-7RM5": "A7R V",
            "ILCE-1": "A1", "ILCE-1M2": "A1 II", "ILCE-9M3": "A9 III", "ILCE-6700": "A6700", "ZV-E1": "ZV-E1", "ZV-E10M2": "ZV-E10 II",
        ]
        return names[code] ?? code
    }

    /// Walks a mounted card and recognises it. Reads one Sony XML for the model.
    public static func scan(volume: URL) -> CameraCard? {
        guard let enumerator = FileManager.default.enumerator(
            at: volume, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return nil }
        let root = volume.standardizedFileURL.path
        var files: [CardFile] = []
        var sonyXML: URL?
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]),
                  values.isRegularFile == true else { continue }
            let path = String(url.standardizedFileURL.path.dropFirst(root.count + 1))
            files.append(CardFile(path: path, size: Int64(values.fileSize ?? 0), modified: values.contentModificationDate ?? .distantPast))
            if sonyXML == nil, path.uppercased().hasSuffix("M01.XML") { sonyXML = url }
            if files.count > 100_000 { break }
        }
        let model = sonyXML.flatMap { try? String(contentsOf: $0, encoding: .utf8) }.flatMap(sonyModel(fromXML:))
        return recognise(files, sonyModel: model)
    }
}
