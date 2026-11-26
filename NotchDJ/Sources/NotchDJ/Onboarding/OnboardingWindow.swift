import AppKit
import Combine
import SwiftUI

/// Hosts the onboarding. Shown on first launch and from Settings or the notch menu.
@MainActor
final class OnboardingWindow: NSObject, NSWindowDelegate {
    static let size = CGSize(width: 680, height: 500)

    private let model: DJModel
    private var window: NSWindow?
    private var appearanceObserver: AnyCancellable?
    /// The permission step updates live while the window is open.
    private var polling = false

    init(model: DJModel) {
        self.model = model
        super.init()
    }

    func show() {
        let window = window ?? makeWindow()
        self.window = window
        applyAppearance()
        NSApp.activate()
        window.center()
        window.makeKeyAndOrderFront(nil)
        if !polling {
            polling = true
            model.permissions.startPolling()
        }
    }

    private func makeWindow() -> NSWindow {
        let controller = self
        let root = OnboardingView(finish: { controller.finish() })
            .environmentObject(model)
            .environmentObject(model.mixer)
            .environmentObject(model.now)
            .environmentObject(model.prefs)
            .environmentObject(model.permissions)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: Self.size),
                              styleMask: [.titled, .closable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = String(localized: "Welcome to Notch DJ")
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: root)
        window.delegate = self
        appearanceObserver = model.prefs.objectWillChange.sink { _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { controller.applyAppearance() } }
        }
        return window
    }

    /// The title bar buttons follow the template's light or dark look.
    private func applyAppearance() {
        let name: NSAppearance.Name = model.prefs.isDark ? .darkAqua : .aqua
        if window?.appearance?.name != name { window?.appearance = NSAppearance(named: name) }
    }

    private func finish() {
        model.prefs.onboardingCompleted = true
        window?.close()
        model.open(.home)
    }

    func windowWillClose(_ notification: Notification) {
        // Closing early counts as seen, so it doesn't come back at every launch.
        model.prefs.onboardingCompleted = true
        if polling {
            polling = false
            model.permissions.stopPolling()
        }
        // Let AppKit finish closing before the window and its view are released. The next
        // showing starts again at the welcome step.
        let controller = self
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                controller.window = nil
                controller.appearanceObserver = nil
            }
        }
    }
}
