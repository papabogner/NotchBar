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
    private var mixer: AppVolumeMixer!
    private var model: DJModel!
    private var window: DJWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        audio.start()
        mixer = AppVolumeMixer(systemAudio: audio)
        model = DJModel(mixer: mixer, now: now)
        window = DJWindow(model: model)
        now.start()
        mixer.applySavedRoutesIfNeeded()
        mixer.activateAutoApplyIfNeeded()
        mixer.activateDuckingIfNeeded()
        let keys = DJHotkeys.shared
        keys.onToggle = { [weak model] in model?.toggle() }
        keys.onMixer = { [weak model] in model?.mixerKey() }
        keys.installIfNeeded()
    }

    @objc func showSettings() { DJSettings.show(model: model) }

    @objc func toggleLogin() {
        if SMAppService.mainApp.status == .enabled {
            try? SMAppService.mainApp.unregister()
        } else {
            try? SMAppService.mainApp.register()
        }
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
        let settings = appMenu.addItem(withTitle: "Settings…", action: #selector(DJDelegate.showSettings), keyEquivalent: ",")
        settings.target = delegate
        let login = appMenu.addItem(withTitle: "Launch at Login", action: #selector(DJDelegate.toggleLogin), keyEquivalent: "")
        login.target = delegate
        appMenu.delegate = DJMenuDelegate.shared
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Notch DJ", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)
        return main
    }
}
