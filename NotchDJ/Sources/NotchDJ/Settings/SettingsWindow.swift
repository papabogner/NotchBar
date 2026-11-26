import AppKit
import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case general, appearance, audio, extras, about
    var id: String { rawValue }
}

/// Which Settings tab shows. Lets the panel open Settings on a given tab.
@MainActor
final class SettingsRouter: ObservableObject {
    @Published var tab: SettingsTab = .general
}

/// Hosts Settings in a normal window, in the system's light or dark look.
@MainActor
final class SettingsWindow: NSObject, NSWindowDelegate {
    private let model: DJModel
    private let router = SettingsRouter()
    private var window: NSWindow?
    /// Permission rows update live while Settings is open.
    private var polling = false

    init(model: DJModel) {
        self.model = model
        super.init()
    }

    func show(_ tab: SettingsTab? = nil) {
        if let tab { router.tab = tab }
        let window = window ?? makeWindow()
        self.window = window
        NSApp.activate()
        if !window.isVisible { window.center() }
        window.makeKeyAndOrderFront(nil)
        if !polling {
            polling = true
            model.permissions.startPolling()
        }
    }

    private func makeWindow() -> NSWindow {
        let root = SettingsView()
            .environmentObject(router)
            .environmentObject(model)
            .environmentObject(model.mixer)
            .environmentObject(model.now)
            .environmentObject(model.prefs)
            .environmentObject(model.permissions)
        let controller = NSHostingController(rootView: root)
        let window = NSWindow(contentViewController: controller)
        window.title = String(localized: "Notch DJ Settings")
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        return window
    }

    func windowWillClose(_ notification: Notification) {
        guard polling else { return }
        polling = false
        model.permissions.stopPolling()
    }
}
