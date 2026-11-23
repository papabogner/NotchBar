import AppKit

/// Entry point. `--snapshot <folder>`, `--usage` and `--make-icon <folder>` are developer tools; see README.
@main
enum NotchBarMain {
    @MainActor
    static func main() {
        let arguments = CommandLine.arguments
        if let i = arguments.firstIndex(of: "--snapshot") {
            Snapshotter.run(outDir: i + 1 < arguments.count ? arguments[i + 1] : "snapshots")
            return
        }
        if let i = arguments.firstIndex(of: "--make-icon") {
            AppIconArt.writeIconset(to: i + 1 < arguments.count ? arguments[i + 1] : "AppIcon.iconset")
            return
        }
        if arguments.contains("--usage") {
            Snapshotter.printUsage()
            return
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.mainMenu = EditMenu.make()
        app.run()
    }
}

/// Creates each feature, starts it, and hands everything to the notch.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let media = MediaController()
    private let usage = ClaudeUsageStore()
    private let timer = TimerModel()
    private let hud = HUDService()
    private let clipboard = ClipboardStore()
    private let calendar = CalendarStore()
    private let weather = WeatherStore()
    private let dictation = DictationMonitor()
    private let activity = ActivityMonitor()
    private var controller: NotchController?
    private var clipboardShortcut: HotKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let volumes = AppVolumeMixer(systemAudio: hud.audio)
        let vm = NotchViewModel(media: media, usage: usage, timer: timer, hudService: hud, clipboard: clipboard, calendar: calendar,
                                weather: weather, dictation: dictation, activity: activity, volumes: volumes)
        let controller = NotchController(vm: vm)
        self.controller = controller
        DebugCommands.install(vm: vm, panel: controller.panel, controller: controller)

        media.start()
        usage.start()
        hud.start()
        clipboard.start()
        calendar.start()
        weather.start()
        dictation.start()
        MenuBarOrganizer.shared.start()

        // ⌃⌘V. ⌘⇧V is avoided because many apps use it for Paste and Match Style.
        clipboardShortcut = HotKey(keyCode: 9, modifiers: 0x0100 | 0x1000, id: 1) { [weak vm] in
            MainActor.assumeIsolated { vm?.toggleClipboard() }
        }
    }
}

/// A menu-bar-less app has no Edit menu, so ⌘C, ⌘V, and ⌘A never reach a text field.
enum EditMenu {
    static func make() -> NSMenu {
        let main = NSMenu()
        let top = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        top.submenu = edit
        main.addItem(top)
        return main
    }
}
