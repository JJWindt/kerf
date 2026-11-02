import AVFoundation
import SwiftUI

/// The camera as a mirror before a call. Runs only while the page is open.
struct CameraPage: View {
    @State private var access = AVCaptureDevice.authorizationStatus(for: .video)

    var body: some View {
        Group {
            if access == .authorized {
                CameraView()
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: ui(18), style: .continuous))
            } else {
                VStack(spacing: ui(10)) {
                    Image(systemName: "web.camera").font(.page(24, weight: .semibold)).foregroundStyle(.white.opacity(0.6))
                    IslandButton(title: "Show Camera", role: .primary) {
                        AVCaptureDevice.requestAccess(for: .video) { _ in
                            Task { @MainActor in access = AVCaptureDevice.authorizationStatus(for: .video) }
                        }
                    }
                    .frame(width: ui(180))
                }
                .frame(maxWidth: .infinity, minHeight: ui(150))
            }
        }
        .padding(.horizontal, ui(20))
        .padding(.top, ui(6))
    }

    static var contentHeight: CGFloat { 250 }
}

struct CameraView: NSViewRepresentable {
    func makeNSView(context: Context) -> CameraPreview { CameraPreview() }
    func updateNSView(_ view: CameraPreview, context: Context) {}

    static func dismantleNSView(_ view: CameraPreview, coordinator: ()) {
        view.stop()
    }
}

/// AVCaptureSession is thread-safe but not marked Sendable; it starts and stops off the main thread.
nonisolated final class CaptureSession: @unchecked Sendable {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "nl.paulboerma.kerf.camera")

    func start() { queue.async { self.session.startRunning() } }
    func stop() { queue.async { self.session.stopRunning() } }
}

final class CameraPreview: NSView {
    private let capture = CaptureSession()
    private var session: AVCaptureSession { capture.session }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        guard let device = AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else { return }
        session.addInput(input)
        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.connection?.automaticallyAdjustsVideoMirroring = false
        preview.connection?.isVideoMirrored = true
        layer = preview
        capture.start()
    }

    required init?(coder: NSCoder) { nil }

    func stop() {
        capture.stop()
    }
}
