// Based on NotchBar (https://github.com/srisanthosh/NotchBar), GPLv3.
// Original copyright remains with the NotchBar authors. Notch DJ changes are under the same license.
import AppKit
import ApplicationServices
import Darwin

/// System Audio Recording (process taps) without a prompt.
///
/// macOS has no public call for this. The TCC preflight and request functions are private, so
/// they are looked up at run time; when they are missing the caller falls back to tap results.
/// Preflight is a synchronous call into tccd: never call it on the main thread.
enum AudioCaptureAccess {
    private typealias Preflight = @convention(c) (CFString, CFDictionary?) -> Int32
    private typealias Request = @convention(c) (CFString, CFDictionary?, @escaping @convention(block) (Bool) -> Void) -> Void

    private static let frameworkPath = "/System/Library/PrivateFrameworks/TCC.framework/Versions/A/TCC"
    private static let serviceName = "kTCCServiceAudioCapture"

    private static func symbol(_ name: String) -> UnsafeMutableRawPointer? {
        guard let handle = dlopen(frameworkPath, RTLD_NOW) else { return nil }
        return dlsym(handle, name)
    }

    /// Nil when the private function isn't there.
    static func preflight() -> CaptureStatus? {
        guard let pointer = symbol("TCCAccessPreflight") else { return nil }
        let function = unsafeBitCast(pointer, to: Preflight.self)
        switch function(serviceName as CFString, nil) {
        case 0: return .authorized
        case 1: return .denied
        default: return .notDetermined
        }
    }

    /// Shows the macOS prompt if the user hasn't answered yet. False when the function isn't there.
    static func request(_ completion: @escaping @Sendable (Bool) -> Void) -> Bool {
        guard let pointer = symbol("TCCAccessRequest") else { return false }
        let function = unsafeBitCast(pointer, to: Request.self)
        function(serviceName as CFString, nil) { granted in completion(granted) }
        return true
    }
}

/// Audio capture and Accessibility status for onboarding, Settings and the mixer.
///
/// Checked once at launch and again when a window that shows it opens. Checking never prompts.
@MainActor
final class PermissionCenter: ObservableObject {
    @Published private(set) var capture: CaptureStatus = .unknown
    /// Needed only to pass media keys through. The panel works without it.
    @Published private(set) var accessibility = false
    /// The private preflight call is missing, so `capture` is the last tap result.
    @Published private(set) var usesFallback = false

    var onCaptureChange: (@MainActor (CaptureStatus) -> Void)?
    var onAccessibilityChange: (@MainActor (Bool) -> Void)?

    private static let cacheKey = "captureStatusCache"
    private var checking = false
    private var lastCheck: TimeInterval = 0
    private var pollTimer: Timer?
    private var accessibilityObserver: NSObjectProtocol?
    private let isPreview: Bool

    init(preview: CaptureStatus? = nil) {
        if let preview {
            capture = preview
            accessibility = true
            isPreview = true
            return
        }
        isPreview = false
        accessibility = AXIsProcessTrusted()
        let center = self
        accessibilityObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.accessibility.api"), object: nil, queue: .main
        ) { _ in
            // The trust list is written after the notification, so read it a moment later.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                MainActor.assumeIsolated { center.refreshAccessibility() }
            }
        }
    }

    /// Reads both permissions without prompting. Calls closer than two seconds apart are skipped.
    func refresh(force: Bool = false) {
        guard !isPreview else { return }
        refreshAccessibility()
        let now = Date.timeIntervalSinceReferenceDate
        guard !checking, force || now - lastCheck > 2 else { return }
        checking = true
        lastCheck = now
        let center = self
        DispatchQueue.global(qos: .userInitiated).async {
            let status = AudioCaptureAccess.preflight()
            DispatchQueue.main.async {
                MainActor.assumeIsolated { center.finishCheck(status) }
            }
        }
    }

    /// Shows the macOS prompt the first time. After a "Don't Allow" macOS won't ask again,
    /// so this opens System Settings instead.
    func requestCapture() {
        guard !isPreview else { return }
        if capture == .denied {
            openCaptureSettings()
            return
        }
        let center = self
        let asked = AudioCaptureAccess.request { granted in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { center.requestFinished(granted) }
            }
        }
        if !asked { openCaptureSettings() }
    }

    func requestAccessibility() {
        guard !isPreview else { return }
        // The literal key, because the imported `kAXTrustedCheckOptionPrompt` global isn't concurrency-safe.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        setAccessibility(trusted)
        if !trusted { openAccessibilitySettings() }
    }

    /// A tap started or was refused. The only signal when preflight is unavailable.
    func noteTapResult(_ granted: Bool) {
        guard !isPreview else { return }
        set(granted ? .authorized : .denied)
    }

    /// Checks every second while onboarding or Settings shows the permission row.
    func startPolling() {
        guard !isPreview, pollTimer == nil else { return }
        refresh(force: true)
        let center = self
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            MainActor.assumeIsolated { center.refresh(force: true) }
        }
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    func openCaptureSettings() {
        open([
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AudioCapture",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture",
            "x-apple.systempreferences:com.apple.preference.security?Privacy",
        ])
    }

    func openAccessibilitySettings() {
        open([
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
        ])
    }

    private func open(_ candidates: [String]) {
        for text in candidates {
            guard let url = URL(string: text), NSWorkspace.shared.open(url) else { continue }
            return
        }
    }

    private func refreshAccessibility() {
        guard !isPreview else { return }
        setAccessibility(AXIsProcessTrusted())
    }

    private func setAccessibility(_ trusted: Bool) {
        guard trusted != accessibility else { return }
        accessibility = trusted
        onAccessibilityChange?(trusted)
    }

    private func finishCheck(_ status: CaptureStatus?) {
        checking = false
        if let status {
            usesFallback = false
            set(status)
            return
        }
        usesFallback = true
        let cached = DJDefaults.suite.string(forKey: Self.cacheKey).flatMap(CaptureStatus.init(rawValue:))
        set(cached ?? .notDetermined)
    }

    private func requestFinished(_ granted: Bool) {
        set(granted ? .authorized : .denied)
        refresh(force: true)
    }

    private func set(_ status: CaptureStatus) {
        if status == .authorized || status == .denied {
            DJDefaults.suite.set(status.rawValue, forKey: Self.cacheKey)
        }
        guard status != capture else { return }
        capture = status
        onCaptureChange?(status)
    }
}
