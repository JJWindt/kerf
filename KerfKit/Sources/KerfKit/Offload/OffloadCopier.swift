import Darwin
import Foundation

/// Copies a card, checks every file against its checksum by reading the copy back, and skips
/// what the project already has. Never writes to the card.
public final class OffloadCopier: @unchecked Sendable {
    public struct Progress: Sendable {
        public var copiedBytes: Int64
        public var totalBytes: Int64
        public var filesDone: Int
        public var filesTotal: Int
        public var skipped: Int
        public var currentFile: String
        public var bytesPerSecond: Double

        public init(copiedBytes: Int64, totalBytes: Int64, filesDone: Int, filesTotal: Int, skipped: Int, currentFile: String, bytesPerSecond: Double) {
            self.copiedBytes = copiedBytes
            self.totalBytes = totalBytes
            self.filesDone = filesDone
            self.filesTotal = filesTotal
            self.skipped = skipped
            self.currentFile = currentFile
            self.bytesPerSecond = bytesPerSecond
        }

        public var fraction: Double { totalBytes > 0 ? min(Double(copiedBytes) / Double(totalBytes), 1) : 0 }

        public var secondsLeft: Double? {
            bytesPerSecond > 1 ? Double(totalBytes - copiedBytes) / bytesPerSecond : nil
        }
    }

    public struct Report: Sendable {
        public var copied: Int
        public var skipped: Int
        public var bytes: Int64
        public var cardFolder: URL
        /// Files whose copy didn't match the card. Should always be empty.
        public var mismatches: [String]

        public init(copied: Int, skipped: Int, bytes: Int64, cardFolder: URL, mismatches: [String]) {
            self.copied = copied
            self.skipped = skipped
            self.bytes = bytes
            self.cardFolder = cardFolder
            self.mismatches = mismatches
        }
    }

    public enum Outcome: Sendable {
        case finished(Report)
        case cancelled
        case failed(String)
    }

    private let lock = NSLock()
    private var cancelled = false
    private static let chunk = 8 << 20

    public init() {}

    public func cancel() {
        lock.withLock { cancelled = true }
    }

    private var isCancelled: Bool { lock.withLock { cancelled } }

    public func run(_ plan: OffloadPlan, template: OffloadTemplate, progress: @Sendable (Progress) -> Void) -> Outcome {
        let files = FileManager.default
        do {
            for folder in [plan.cardFolder] + template.extraFolders.map({ plan.projectFolder.appendingPathComponent($0) }) {
                try files.createDirectory(at: folder, withIntermediateDirectories: true)
            }
        } catch {
            return .failed(error.localizedDescription)
        }
        var index = IngestIndex.load(project: plan.projectFolder)
        var state = Progress(copiedBytes: 0, totalBytes: plan.totalBytes, filesDone: 0, filesTotal: plan.items.count, skipped: 0,
                             currentFile: "", bytesPerSecond: 0)
        var manifest = ["source,destination,size,xxhash64,copied"]
        var mismatches: [String] = []
        let started = Date()
        var buffer = [UInt8](repeating: 0, count: Self.chunk)

        for item in plan.items {
            if isCancelled { return .cancelled }
            state.currentFile = (item.file.path as NSString).lastPathComponent
            progress(state)
            let relative = String(item.destination.path.dropFirst(plan.projectFolder.path.count + 1))
            // Same file from the same camera already in the project, and still there: skip it.
            if let earlier = index.candidate(camera: plan.camera, file: item.file),
               files.fileExists(atPath: plan.projectFolder.appendingPathComponent(earlier.destination).path),
               let hash = Self.hash(of: item.source, buffer: &buffer), XXHash64.hex(hash) == earlier.hash {
                state.skipped += 1
                state.filesDone += 1
                state.copiedBytes += item.file.size
                continue
            }
            do {
                try files.createDirectory(at: item.destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                let sourceHash = try Self.copy(item.source, to: item.destination, buffer: &buffer) { bytes in
                    state.copiedBytes += bytes
                    let elapsed = Date().timeIntervalSince(started)
                    state.bytesPerSecond = elapsed > 0.5 ? Double(state.copiedBytes) / elapsed : 0
                    progress(state)
                    return !self.isCancelled
                }
                guard let sourceHash else { return .cancelled }
                let copyHash = Self.hash(of: item.destination, buffer: &buffer)
                if copyHash != sourceHash { mismatches.append(item.file.path) }
                try? files.setAttributes([.modificationDate: item.file.modified, .creationDate: item.file.modified], ofItemAtPath: item.destination.path)
                let hex = XXHash64.hex(sourceHash)
                index.entries.append(.init(camera: plan.camera, name: (item.file.path as NSString).lastPathComponent, size: item.file.size,
                                           modified: item.file.modified, hash: hex, destination: relative))
                manifest.append([item.file.path, relative, String(item.file.size), hex, Date().formatted(.iso8601)].map(Self.csv).joined(separator: ","))
            } catch {
                return .failed("\(item.file.path): \(error.localizedDescription)")
            }
            state.filesDone += 1
        }
        try? index.save(project: plan.projectFolder)
        // A card that was all in the project already leaves no empty card folder behind.
        if state.filesDone == state.skipped, (try? files.contentsOfDirectory(atPath: plan.cardFolder.path))?.isEmpty == true {
            try? files.removeItem(at: plan.cardFolder)
        }
        let manifestURL = plan.projectFolder.appendingPathComponent(".kerf/\(plan.camera) \(plan.cardFolder.lastPathComponent).csv")
        try? manifest.joined(separator: "\n").write(to: manifestURL, atomically: true, encoding: .utf8)
        progress(state)
        return .finished(Report(copied: state.filesDone - state.skipped, skipped: state.skipped, bytes: state.copiedBytes,
                                cardFolder: plan.cardFolder, mismatches: mismatches))
    }

    private static func csv(_ field: String) -> String {
        field.contains(",") || field.contains("\"") ? "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : field
    }

    /// Streams a file to its copy, hashing the source on the way. Nil when cancelled.
    static func copy(_ source: URL, to destination: URL, buffer: inout [UInt8], advanced: (Int64) -> Bool) throws -> UInt64? {
        let input = open(source.path, O_RDONLY)
        guard input >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(input) }
        let output = open(destination.path, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
        guard output >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(output) }
        _ = fcntl(input, F_NOCACHE, 1)
        _ = fcntl(output, F_NOCACHE, 1)
        var hasher = XXHash64()
        while true {
            let count = buffer.withUnsafeMutableBytes { read(input, $0.baseAddress, $0.count) }
            if count < 0 { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
            if count == 0 { break }
            buffer.withUnsafeBytes { hasher.update(UnsafeRawBufferPointer(rebasing: $0[0..<count])) }
            var offset = 0
            while offset < count {
                let written = buffer.withUnsafeBytes { write(output, $0.baseAddress! + offset, count - offset) }
                if written <= 0 { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
                offset += written
            }
            if !advanced(Int64(count)) {
                try? FileManager.default.removeItem(at: destination)
                return nil
            }
        }
        guard fsync(output) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        return hasher.finalize()
    }

    /// Reads a file past the cache, so a copy is checked as it sits on the disk.
    static func hash(of url: URL, buffer: inout [UInt8]) -> UInt64? {
        let fd = open(url.path, O_RDONLY)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        _ = fcntl(fd, F_NOCACHE, 1)
        var hasher = XXHash64()
        while true {
            let count = buffer.withUnsafeMutableBytes { read(fd, $0.baseAddress, $0.count) }
            if count < 0 { return nil }
            if count == 0 { return hasher.finalize() }
            buffer.withUnsafeBytes { hasher.update(UnsafeRawBufferPointer(rebasing: $0[0..<count])) }
        }
    }
}
