import AVFoundation
import AppKit
import SwiftUI

/// A quick look in the camera, like a mirror. The camera runs only while the preview is on
/// screen, so the green light goes off as soon as the notch closes.
@MainActor
final class CameraGlance: ObservableObject {
    enum State: Equatable {
        case off, starting, live, denied, unavailable
    }

    @Published private(set) var state: State = .off

    /// Shared with the preview layer. Only touched on `queue` once created.
    nonisolated let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "com.local.notchbar.camera")
    private var wanted = false
    private var configured = false

    /// Turns the camera on or off. Asking twice in a row does nothing.
    func setActive(_ active: Bool) {
        guard active != wanted, !Snapshotter.isRendering else { return }
        wanted = active
        active ? start() : stop()
    }

    private func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            run()
        case .notDetermined:
            state = .starting
            AVCaptureDevice.requestAccess(for: .video) { granted in
                Task { @MainActor [weak self] in
                    guard let self, self.wanted else { return }
                    granted ? self.run() : (self.state = .denied)
                }
            }
        default:
            state = .denied
        }
    }

    private func run() {
        state = .starting
        let needsSetup = !configured
        configured = true
        queue.async { [session] in
            if needsSetup {
                guard let device = Self.preferredCamera(), !device.isSuspended,
                      let input = try? AVCaptureDeviceInput(device: device) else {
                    Task { @MainActor [weak self] in self?.configured = false; self?.state = .unavailable }
                    return
                }
                session.beginConfiguration()
                session.sessionPreset = .high
                if session.canAddInput(input) { session.addInput(input) }
                session.commitConfiguration()
            }
            session.startRunning()
            let running = session.isRunning
            Task { @MainActor [weak self] in
                guard let self else { return }
                // Closed while it was starting up: turn it straight back off.
                guard self.wanted else { self.queue.async { session.stopRunning() }; return }
                self.state = running ? .live : .unavailable
            }
        }
    }

    private func stop() {
        state = .off
        queue.async { [session] in if session.isRunning { session.stopRunning() } }
    }

    /// The Mac's own camera first, so opening the notch doesn't wake an iPhone nearby
    /// through Continuity Camera. Then a plugged-in camera, then whatever the system offers.
    nonisolated private static func preferredCamera() -> AVCaptureDevice? {
        let builtIn = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera], mediaType: .video, position: .unspecified)
        if let camera = builtIn.devices.first(where: { !$0.isSuspended }) { return camera }
        let external = AVCaptureDevice.DiscoverySession(deviceTypes: [.external], mediaType: .video, position: .unspecified)
        if let camera = external.devices.first { return camera }
        return AVCaptureDevice.default(for: .video)
    }

    static func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// The open notch's camera view: the picture, mirrored, or why there isn't one.
struct CameraGlancePanel: View {
    @ObservedObject var camera: CameraGlance
    var close: () -> Void

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(white: 0.08))
            if Snapshotter.isRendering {
                placeholder
            } else {
                CameraPreview(session: camera.session, isLive: camera.state == .live)
                    .opacity(camera.state == .live ? 1 : 0)
                    .animation(.easeOut(duration: 0.25), value: camera.state)
                message
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(.white.opacity(0.08), lineWidth: 1))
        .overlay(alignment: .topTrailing) {
            CircleIconButton(systemName: "xmark", size: 22, iconSize: 9, help: "Close Camera", action: close)
                .padding(8)
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private var message: some View {
        switch camera.state {
        case .off, .live:
            EmptyView()
        case .starting:
            ProgressView().controlSize(.small).tint(.white)
        case .denied:
            VStack(spacing: 8) {
                Image(systemName: "video.slash.fill").font(.system(size: 20)).foregroundStyle(.white.opacity(0.6))
                Text("NotchBar can't use the camera").font(.system(size: 12, weight: .semibold))
                Text("Allow it in Privacy & Security > Camera.").font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
                WidgetButton(title: "Open Settings") { CameraGlance.openPrivacySettings() }
            }
        case .unavailable:
            VStack(spacing: 8) {
                Image(systemName: "video.slash.fill").font(.system(size: 20)).foregroundStyle(.white.opacity(0.6))
                Text("No camera available").font(.system(size: 12, weight: .semibold))
                Text("The lid may be closed, or another app is using it.").font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
            }
        }
    }

    /// Still images can't show a live layer, so renders get a stand-in.
    private var placeholder: some View {
        LinearGradient(colors: [Color(red: 0.32, green: 0.3, blue: 0.36), Color(red: 0.14, green: 0.13, blue: 0.17)],
                       startPoint: .top, endPoint: .bottom)
            .overlay {
                Image(systemName: "person.fill").font(.system(size: 64)).foregroundStyle(.white.opacity(0.25)).offset(y: 18)
            }
    }
}

/// Hosts the camera's preview layer, mirrored like a mirror and filling its frame.
private struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession
    /// The layer's connection only exists once the session has its camera, so mirroring
    /// is set again whenever the picture goes live.
    let isLive: Bool

    func makeNSView(context: Context) -> PreviewView { PreviewView(session: session) }
    func updateNSView(_ view: PreviewView, context: Context) { if isLive { view.mirror() } }

    final class PreviewView: NSView {
        private let preview: AVCaptureVideoPreviewLayer

        init(session: AVCaptureSession) {
            preview = AVCaptureVideoPreviewLayer(session: session)
            super.init(frame: .zero)
            wantsLayer = true
            preview.videoGravity = .resizeAspectFill
            layer?.addSublayer(preview)
            mirror()
        }

        func mirror() {
            guard let connection = preview.connection, connection.isVideoMirroringSupported,
                  !connection.isVideoMirrored else { return }
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func layout() {
            super.layout()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            preview.frame = bounds
            CATransaction.commit()
        }
    }
}
