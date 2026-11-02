import Foundation
import Testing
@testable import KerfKit

struct CardScannerTests {
    func files(_ paths: [String]) -> [CardFile] { paths.map { CardFile(path: $0, size: 1000) } }

    @Test func sony() throws {
        let card = try #require(CardScanner.recognise(files([
            "PRIVATE/M4ROOT/CLIP/C0001.MP4", "PRIVATE/M4ROOT/CLIP/C0001M01.XML", "PRIVATE/M4ROOT/CLIP/C0002.MP4",
            "PRIVATE/M4ROOT/MEDIAPRO.XML", ".Spotlight-V100/Store", "DCIM/100MSDCF/DSC00001.ARW",
        ]), sonyModel: "FX3"))
        #expect(card.brand == "Sony")
        #expect(card.name == "Sony FX3")
        #expect(card.mediaCount == 3)
        #expect(card.files.count == 5)
        #expect(card.kind == .video)
    }

    @Test func otherBrands() {
        #expect(CardScanner.recognise(files(["DCIM/100GOPRO/GX010001.MP4", "DCIM/100GOPRO/GL010001.LRV"]))?.brand == "GoPro")
        #expect(CardScanner.recognise(files(["DCIM/DJI_001/DJI_20261031_0001_D.MP4"]))?.brand == "DJI")
        #expect(CardScanner.recognise(files(["DCIM/100CANON/IMG_0001.CR3"]))?.brand == "Canon")
        #expect(CardScanner.recognise(files(["A001_10311200_C001.braw"]))?.brand == "Blackmagic")
        let zoom = CardScanner.recognise(files(["ZOOM0001/ZOOM0001_LR.WAV"]))
        #expect(zoom?.brand == "Zoom")
        #expect(zoom?.kind == .audio)
        #expect(CardScanner.recognise(files(["DJI_01_20261031_120000.WAV"]))?.kind == .audio)
        #expect(CardScanner.recognise(files(["notes.txt", "docs/readme.pdf"])) == nil)
    }

    @Test func sonyModelFromXML() {
        #expect(CardScanner.sonyModel(fromXML: #"<Device manufacturer="Sony" modelName="ILME-FX3" serialNo="1"/>"#) == "FX3")
        #expect(CardScanner.sonyModel(fromXML: #"<Device modelName="ILCE-7SM3"/>"#) == "A7S III")
        #expect(CardScanner.sonyModel(fromXML: #"<Device modelName="ILME-NEW1"/>"#) == "ILME-NEW1")
    }
}

struct OffloadPlannerTests {
    @Test func cardNumbers() {
        #expect(OffloadPlanner.nextCardNumber(existing: [], prefix: "Kaart") == 1)
        #expect(OffloadPlanner.nextCardNumber(existing: ["Kaart 01", "Kaart 2", "kaart 12", "Notes"], prefix: "Kaart") == 13)
        #expect(OffloadPlanner.cardFolderName(prefix: "Kaart", number: 3) == "Kaart 03")
        #expect(OffloadPlanner.folderName("Bruiloft: Jansen/Pietersen ") == "Bruiloft- Jansen-Pietersen")
    }

    @Test func planKeepsTheCardStructure() throws {
        let drive = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("kerf-drive-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: drive) }
        let card = CameraCard(brand: "Sony", model: "FX3", kind: .video,
                              files: [CardFile(path: "PRIVATE/M4ROOT/CLIP/C0001.MP4", size: 10)], mediaCount: 1)
        let existing = drive.appendingPathComponent("Projecten/Bruiloft Jansen/Beelden/Sony FX3/Kaart 01")
        try FileManager.default.createDirectory(at: existing, withIntermediateDirectories: true)
        let plan = OffloadPlanner.plan(card: card, cardRoot: URL(fileURLWithPath: "/Volumes/CARD"), drive: drive,
                                       project: "Bruiloft Jansen", template: .dutch)
        #expect(plan.cardNumber == 2)
        #expect(plan.items.first?.destination.path.hasSuffix("Projecten/Bruiloft Jansen/Beelden/Sony FX3/Kaart 02/PRIVATE/M4ROOT/CLIP/C0001.MP4") == true)
        #expect(OffloadPlanner.projects(on: drive, template: .dutch) == ["Bruiloft Jansen"])
    }
}

struct OffloadCopierTests {
    @Test func copiesChecksAndSkipsTheSecondTime() throws {
        let base = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("kerf-copy-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: base) }
        let card = base.appendingPathComponent("CARD")
        let drive = base.appendingPathComponent("SSD")
        try FileManager.default.createDirectory(at: card.appendingPathComponent("PRIVATE/M4ROOT/CLIP"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: drive, withIntermediateDirectories: true)
        let clip = Data((0..<3_000_000).map { UInt8(truncatingIfNeeded: $0 &* 7) })
        try clip.write(to: card.appendingPathComponent("PRIVATE/M4ROOT/CLIP/C0001.MP4"))
        try Data("<x/>".utf8).write(to: card.appendingPathComponent("PRIVATE/M4ROOT/CLIP/C0001M01.XML"))

        let scanned = try #require(CardScanner.scan(volume: card))
        let plan = OffloadPlanner.plan(card: scanned, cardRoot: card, drive: drive, project: "Test", template: .dutch)
        guard case .finished(let report) = OffloadCopier().run(plan, template: .dutch, progress: { _ in }) else {
            Issue.record("copy failed")
            return
        }
        #expect(report.copied == 2)
        #expect(report.mismatches.isEmpty)
        let copy = plan.cardFolder.appendingPathComponent("PRIVATE/M4ROOT/CLIP/C0001.MP4")
        #expect(try Data(contentsOf: copy) == clip)
        #expect(FileManager.default.fileExists(atPath: drive.appendingPathComponent("Projecten/Test/Assets").path))

        // The same card again: a new card folder, but nothing copied twice.
        let again = OffloadPlanner.plan(card: scanned, cardRoot: card, drive: drive, project: "Test", template: .dutch)
        #expect(again.cardNumber == 2)
        guard case .finished(let second) = OffloadCopier().run(again, template: .dutch, progress: { _ in }) else {
            Issue.record("second copy failed")
            return
        }
        #expect(second.skipped == 2)
        #expect(second.copied == 0)
    }
}
