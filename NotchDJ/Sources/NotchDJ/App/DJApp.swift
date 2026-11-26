import AppKit
import ServiceManagement

// Based on NotchBar (https://github.com/srisanthosh/NotchBar), GPLv3.
@main
enum NotchDJMain {
    @MainActor
    static func main() {
        _ = DJDefaults.supportDirectory
        let app = NSApplication.shared
        let delegate = DJDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.mainMenu = DJMenu.make(delegate: delegate)
        app.run()
    }
}

@MainActor
final class DJDelegate: NSObject, NSApplicationDelegate {
    private let audio = SystemAudio()
    private let now = NowPlayingMonitor()
    private let prefs = DJPreferences()
    private let permissions = PermissionCenter()
    private var model: DJModel?
    private var window: DJWindow?
    private var statusItem: StatusItemController?
    private var settings: SettingsWindow?
    private var onboarding: OnboardingWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let permissions = self.permissions
        let prefs = self.prefs
        audio.start()
        let mixer = AppVolumeMixer(systemAudio: audio)
        let model = DJModel(mixer: mixer, now: now, prefs: prefs, permissions: permissions)
        let settings = SettingsWindow(model: model)
        let onboarding = OnboardingWindow(model: model)
        self.model = model
        self.settings = settings
        self.onboarding = onboarding

        // Taps start only after the launch check says they are allowed, so launching never prompts.
        permissions.onCaptureChange = { [weak mixer] status in mixer?.setCaptureStatus(status) }
        mixer.onCaptureResult = { [weak permissions] granted in permissions?.noteTapResult(granted) }
        now.mediaKeysAllowed = { [weak prefs, weak permissions] in
            (prefs?.mediaKeys ?? false) && (permissions?.accessibility ?? false)
        }
        model.onShowSettings = { [weak settings] in settings?.show() }
        model.onShowOnboarding = { [weak onboarding] in onboarding?.show() }

        window = DJWindow(model: model)
        statusItem = StatusItemController(model: model)
        now.start()

        let keys = DJHotkeys.shared
        keys.onToggle = { [weak model] in model?.toggle() }
        keys.onMixer = { [weak model] in model?.mixerKey() }
        keys.installIfNeeded()

        permissions.refresh(force: true)
        if !prefs.onboardingCompleted { onboarding.show() }
    }

    /// Opening the app again from Finder or Spotlight opens the panel.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { model?.open() }
        return false
    }

    @objc func showSettings() { settings?.show() }

    @objc func showOnboarding() { onboarding?.show() }

    @objc func toggleLogin() {
        LoginItem.set(!LoginItem.isEnabled)
    }
}

final class DJMenuDelegate: NSObject, NSMenuDelegate {
    @MainActor static let shared = DJMenuDelegate()

    func menuWillOpen(_ menu: NSMenu) {
        MainActor.assumeIsolated {
            guard let login = menu.items.first(where: { $0.action == #selector(DJDelegate.toggleLogin) }) else { return }
            login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        }
    }
}

@MainActor
enum DJMenu {
    static func make(delegate: DJDelegate) -> NSMenu {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "Notch DJ")
        let settings = appMenu.addItem(withTitle: String(localized: "Settings…"), action: #selector(DJDelegate.showSettings),
                                       keyEquivalent: ",")
        settings.target = delegate
        let onboarding = appMenu.addItem(withTitle: String(localized: "Show Onboarding…"),
                                         action: #selector(DJDelegate.showOnboarding), keyEquivalent: "")
        onboarding.target = delegate
        let login = appMenu.addItem(withTitle: String(localized: "Launch at Login"), action: #selector(DJDelegate.toggleLogin),
                                    keyEquivalent: "")
        login.target = delegate
        appMenu.delegate = DJMenuDelegate.shared
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: String(localized: "Quit Notch DJ"), action: #selector(NSApplication.terminate(_:)),
                        keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: String(localized: "Edit"))
        edit.addItem(withTitle: String(localized: "Cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: String(localized: "Copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: String(localized: "Paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: String(localized: "Select All"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)

        let windowItem = NSMenuItem()
        let windows = NSMenu(title: String(localized: "Window"))
        windows.addItem(withTitle: String(localized: "Close"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowItem.submenu = windows
        main.addItem(windowItem)
        return main
    }
}
