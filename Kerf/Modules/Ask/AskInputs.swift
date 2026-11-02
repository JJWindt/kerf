import AppKit
import ApplicationServices
import AVFoundation
import Speech

/// The text selected in the app in front, through Accessibility; ⌘C as a fallback.
enum SelectionReader {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Asks once for Accessibility, from your own shortcut press.
    static func requestTrust() {
        // The value of kAXTrustedCheckOptionPrompt, which Swift 6 can't read as a global.
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    static func selectedText() -> String? {
        guard isTrusted else {
            requestTrust()
            return nil
        }
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        if AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success, let focused {
            var selected: CFTypeRef?
            // swiftlint:disable:next force_cast
            if AXUIElementCopyAttributeValue(focused as! AXUIElement, kAXSelectedTextAttribute as CFString, &selected) == .success,
               let text = selected as? String, !text.isEmpty {
                return text
            }
        }
        return copiedText()
    }

    /// Presses ⌘C in the app in front and puts the clipboard back afterwards.
    private static func copiedText() -> String? {
        let pasteboard = NSPasteboard.general
        let before = pasteboard.changeCount
        let saved = pasteboard.pasteboardItems?.map { item -> NSPasteboardItem in
            let copy = NSPasteboardItem()
            for type in item.types { if let data = item.data(forType: type) { copy.setData(data, forType: type) } }
            return copy
        }
        let source = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
        let deadline = Date().addingTimeInterval(0.4)
        while pasteboard.changeCount == before, Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
        guard pasteboard.changeCount != before else { return nil }
        let text = pasteboard.string(forType: .string)
        pasteboard.clearContents()
        if let saved, !saved.isEmpty { pasteboard.writeObjects(saved) }
        return text
    }
}

/// Speak instead of typing: on-device when the Mac can, into the ask field.
@Observable
final class Dictation {
    static let shared = Dictation()

    private(set) var isListening = false
    @ObservationIgnored private var engine: AVAudioEngine?
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var task: SFSpeechRecognitionTask?

    /// Starts or stops listening; what is heard goes into the ask field.
    func toggle() {
        if isListening {
            stop()
            return
        }
        SFSpeechRecognizer.requestAuthorization { status in
            Task { @MainActor in
                guard status == .authorized else { return }
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    Task { @MainActor in if granted { Dictation.shared.begin() } }
                }
            }
        }
    }

    private func begin() {
        guard let recognizer = SFSpeechRecognizer(locale: Locale.current) ?? SFSpeechRecognizer(), recognizer.isAvailable else { return }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
        let engine = AVAudioEngine()
        let input = engine.inputNode
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in
            request.append(buffer)
        }
        do {
            engine.prepare()
            try engine.start()
        } catch {
            return
        }
        self.engine = engine
        self.request = request
        isListening = true
        task = recognizer.recognitionTask(with: request) { result, error in
            let text = result?.bestTranscription.formattedString
            let done = error != nil || result?.isFinal == true
            Task { @MainActor in
                if let text { AskModule.shared.text = text }
                if done { Dictation.shared.stop() }
            }
        }
    }

    func stop() {
        engine?.stop()
        engine?.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        engine = nil
        request = nil
        task = nil
        isListening = false
    }
}

enum Screenshot {
    /// Lets you pick an area, then hands the image to Claude.
    static func take(into folder: URL, done: @escaping @MainActor (URL?) -> Void) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("Screenshot \(Date.now.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false)).replacingOccurrences(of: ":", with: ".")).png")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-i", "-x", url.path]
        process.terminationHandler = { _ in
            let exists = FileManager.default.fileExists(atPath: url.path)
            Task { @MainActor in done(exists ? url : nil) }
        }
        try? process.run()
    }
}
