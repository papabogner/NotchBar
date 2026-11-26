import AppKit
import Combine

/// The menu bar icon. By default it shows only when the screen has no notch, and then the pill
/// at the top of the screen is hidden: the icon opens the panel instead.
@MainActor
final class StatusItemController: NSObject {
    private let model: DJModel
    private var item: NSStatusItem?
    private var observers: Set<AnyCancellable> = []

    init(model: DJModel) {
        self.model = model
        super.init()
        let controller = self
        model.prefs.$menuBarMode
            .removeDuplicates()
            .sink { _ in DispatchQueue.main.async { MainActor.assumeIsolated { controller.update() } } }
            .store(in: &observers)
        model.$geometry
            .map(\.hasNotch)
            .removeDuplicates()
            .sink { _ in DispatchQueue.main.async { MainActor.assumeIsolated { controller.update() } } }
            .store(in: &observers)
        update()
    }

    private func update() {
        let hasNotch = model.geometry.hasNotch
        let show: Bool
        switch model.prefs.menuBarMode {
        case .automatic: show = !hasNotch
        case .always: show = true
        case .never: show = false
        }
        if show { install() } else { remove() }
        let hidesPill = show && !hasNotch
        if model.hidesPill != hidesPill { model.hidesPill = hidesPill }
    }

    private func install() {
        guard item == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            let image = NSImage(systemSymbolName: "slider.vertical.3", accessibilityDescription: "Notch DJ")
            image?.isTemplate = true
            button.image = image
            button.target = self
            button.action = #selector(clicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "Notch DJ"
        }
        self.item = item
    }

    private func remove() {
        guard let item else { return }
        NSStatusBar.system.removeStatusItem(item)
        self.item = nil
    }

    @objc private func clicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showMenu(from: sender)
        } else {
            model.toggle()
        }
    }

    private func showMenu(from button: NSStatusBarButton) {
        let menu = NSMenu()
        add(menu, String(localized: "Open Notch DJ"), #selector(openPanel))
        menu.addItem(.separator())
        add(menu, String(localized: "Settings…"), #selector(openSettings))
        add(menu, String(localized: "Show Onboarding…"), #selector(openOnboarding))
        menu.addItem(.separator())
        let quit = NSMenuItem(title: String(localized: "Quit Notch DJ"), action: #selector(NSApplication.terminate(_:)),
                              keyEquivalent: "")
        menu.addItem(quit)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
    }

    private func add(_ menu: NSMenu, _ title: String, _ action: Selector) {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: "")
        entry.target = self
        menu.addItem(entry)
    }

    @objc private func openPanel() { model.open() }
    @objc private func openSettings() { model.showSettings() }
    @objc private func openOnboarding() { model.showOnboarding() }
}
