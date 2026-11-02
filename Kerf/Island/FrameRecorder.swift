import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Saves frames of its own window. Capturing your own window needs no Screen Recording permission.
final class FrameRecorder: NSObject {
    private typealias CaptureFunction = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
    // Unavailable to Swift since macOS 15, but still there, and fine for your own windows.
    private static let capture: CaptureFunction = {
        let handle = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_NOW)
        return unsafeBitCast(dlsym(handle, "CGWindowListCreateImage"), to: CaptureFunction.self)
    }()

    private let window: NSWindow
    private let directory: URL
    private let queue = DispatchQueue(label: "nl.paulboerma.kerf.recorder")
    private var link: CADisplayLink?
    private var start: CFTimeInterval = 0
    private var last: CFTimeInterval = -1
    private var times: [String] = []
    private var events: [String] = []

    init(window: NSWindow, directory: URL) {
        self.window = window
        self.directory = directory
    }

    /// One frame of a window: kCGWindowListOptionIncludingWindow, kCGWindowImageBoundsIgnoreFraming.
    static func snapshot(of window: NSWindow) -> CGImage? {
        capture(.null, 8, UInt32(window.windowNumber), 1)?.takeRetainedValue()
    }

    func begin() {
        start = CACurrentMediaTime()
        let link = window.displayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func mark(_ event: String) {
        events.append("\(String(format: "%.4f", CACurrentMediaTime() - start)) \(event)")
    }

    @objc private func tick(_ link: CADisplayLink) {
        let now = CACurrentMediaTime() - start
        guard now - last >= 1.0 / 60.0 - 0.002 else { return }
        last = now
        guard let image = Self.snapshot(of: window) else { return }
        let name = String(format: "%05d.png", times.count + 1)
        times.append("\(name) \(String(format: "%.4f", now))")
        let url = directory.appendingPathComponent(name)
        queue.async { writePNG(image, to: url) }
    }

    func finish() {
        link?.invalidate()
        try? times.joined(separator: "\n").write(to: directory.appendingPathComponent("times.txt"), atomically: true, encoding: .utf8)
        try? events.joined(separator: "\n").write(to: directory.appendingPathComponent("events.txt"), atomically: true, encoding: .utf8)
        queue.sync {}
    }
}

nonisolated func writePNG(_ image: CGImage, to url: URL) {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
    CGImageDestinationAddImage(destination, image, nil)
    CGImageDestinationFinalize(destination)
}
