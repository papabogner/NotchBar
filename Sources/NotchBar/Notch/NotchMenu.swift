import AppKit
import ServiceManagement

/// The "…" menu in the open notch.
@MainActor
enum NotchMenu {
    /// A menu item that runs a closure.
    private final class Item: NSMenuItem {
        private var handler: (() -> Void)?

        convenience init(_ title: String, checked: Bool = false, enabled: Bool = true, handler: @escaping () -> Void) {
            self.init(title: title, action: #selector(fire), keyEquivalent: "")
            self.handler = handler
            target = self
            state = checked ? .on : .off
            isEnabled = enabled
        }

        @objc private func fire() { handler?() }
    }

    static func show(vm: NotchViewModel) {
        let menu = NSMenu()
        menu.autoenablesItems = false
        addQuickItems(to: menu, vm: vm)
        menu.addItem(.separator())
        menu.addItem(Item("Beenden") { NSApp.terminate(nil) })

        vm.isMenuOpen = true
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        vm.isMenuOpen = false
    }

    private static func addClaudeItems(to menu: NSMenu, vm: NotchViewModel) {
        let usage = vm.usage
        menu.addItem(submenu("Estimated Session Limit", items: SessionLimit.allCases.map { option in
            Item(option.label, checked: usage.sessionLimit == option) { usage.sessionLimit = option }
        }))
        menu.addItem(Item("Match Claude's Usage…") { UsageMatchPrompt.run(usage: usage, vm: vm) })
        if usage.hasHooks {
            menu.addItem(Item("Disconnect Claude Code") { usage.disconnect() })
        } else {
            menu.addItem(Item("Connect Claude Code…") {
                switch usage.connect() {
                case .connected: vm.showToast("Connected. Claude's activity now shows the moment it starts and stops.")
                case .connectedKeepingStatusLine: vm.showToast("Connected. Your own status line was kept, so limits stay estimated.")
                case .failed(let reason): vm.showToast("Couldn't connect: \(reason)")
                }
            })
        }
    }

    private static func addSystemItems(to menu: NSMenu, vm: NotchViewModel) {
        let hud = vm.hudService
        addQuickItems(to: menu, vm: vm)
        let hotkeys = Item("Global Hotkeys", checked: vm.hotkeys.isEnabled) { vm.hotkeys.setEnabled(!vm.hotkeys.isEnabled) }
        hotkeys.toolTip = "⌃⌥N opens or closes the notch. ⌃⌥M mutes the system output."
        menu.addItem(hotkeys)
        let awake = Item("Keep Awake", checked: vm.awake.isOn) { vm.awake.toggle() }
        awake.toolTip = "Stops this Mac from idle-sleeping. The display can still dim. A cup shows in the notch while it is on."
        menu.addItem(awake)
        let shelf = Item("File Shelf", checked: vm.shelf.isEnabled) { vm.shelf.setEnabled(!vm.shelf.isEnabled) }
        shelf.toolTip = "Drop files on the open notch to park them, then drag them back out."
        menu.addItem(shelf)
        let connect = Item("Spotify Connect", checked: vm.spotify.isEnabled) {
            let turningOn = !vm.spotify.isEnabled
            vm.spotify.setEnabled(turningOn)
            if turningOn && (vm.spotify.clientID.isEmpty || !vm.spotify.isSignedIn) {
                vm.showsSpotify = true
                vm.open(.home)
            }
        }
        connect.toolTip = "Lists Spotify Connect devices on the Spotify strip and Now Playing. Off until you turn it on."
        menu.addItem(connect)
        let mini = Item("Mac mini Status", checked: vm.mini.isEnabled) { vm.mini.setEnabled(!vm.mini.isEnabled) }
        mini.toolTip = "Reads uptime, load, and free disk from an SSH alias. Default host is mini. Never asks for a password."
        menu.addItem(mini)
        let book = Item("Show Portfolio", checked: vm.portfolio.isEnabled) { vm.portfolio.setEnabled(!vm.portfolio.isEnabled) }
        book.toolTip = "Totals the holdings in portfolio.json. Edit Holdings creates a placeholder file if you don't have one."
        menu.addItem(book)
        menu.addItem(Item("Portfolio › Edit Holdings…") { vm.portfolio.editHoldings() })
        menu.addItem(Item("Mac mini…") {
            vm.showsAppearance = false
            vm.showsTickerSettings = false
            vm.showsSpotify = false
            vm.showsMini = true
            vm.open(.home)
        })
        menu.addItem(Item("Spotify Connect…") {
            vm.showsAppearance = false
            vm.showsTickerSettings = false
            vm.showsSpotify = true
            vm.open(.home)
        })
        if NotchViewModel.Tab.offered.contains(.mixer) {
            let duck = Item("Duck Other Apps", checked: vm.volumes.ducking) { vm.volumes.setDucking(!vm.volumes.ducking) }
            duck.toolTip = "While Zoom, Teams, FaceTime, Webex, or the chosen app is playing, other apps drop to a quarter. They return when the call stops."
            menu.addItem(duck)
            menu.addItem(Item("Duck for Browser Meet", checked: vm.volumes.duckBrowserMeet) { vm.volumes.setDuckMeet(!vm.volumes.duckBrowserMeet) })
            let apps = vm.volumes.rows.prefix(8).map { row in
                Item(row.name, checked: vm.volumes.duckAppID == row.id) { vm.volumes.setDuckApp(row.id) }
            }
            menu.addItem(submenu("Duck When This App Plays", items: [Item("None", checked: vm.volumes.duckAppID == nil) { vm.volumes.setDuckApp(nil) }] + apps))
            let rules = Item("Apply Saved Volumes", checked: vm.volumes.autoApply) { vm.volumes.setAutoApply(!vm.volumes.autoApply) }
            rules.toolTip = "When an app starts playing, use the volume, mute, and output saved for it. Off: a saved level waits until you move that fader."
            menu.addItem(rules)
        }
        menu.addItem(Item("Appearance…") {
            vm.showsAppearance = true
            vm.open(.home)
        })
        menu.addItem(Item("Show Volume & Brightness", checked: hud.showHUDs) { hud.showHUDs.toggle() })
        menu.addItem(Item("Show Headphone Connections", checked: hud.showDevices) { hud.showDevices.toggle() })
        let dictation = vm.dictation
        menu.addItem(Item("Show Dictation (Handy and Others)", checked: dictation.isEnabled) { dictation.isEnabled.toggle() })
        if NotchViewModel.Tab.offered.contains(.mixer) {
            menu.addItem(Item("Customize Home…") {
                vm.homeLayout.isCustomizing = true
                vm.open(.home)
            })
            let mixerCard = Item("Mixer on Home", checked: vm.homeLayout.isEnabled(.mixer)) {
                vm.homeLayout.setEnabled(.mixer, !vm.homeLayout.isEnabled(.mixer))
                vm.refreshMixerSurfaces()
            }
            mixerCard.toolTip = "Master and the apps that are playing, on Home. The Mixer tab has every app."
            menu.addItem(mixerCard)
            menu.addItem(Item("Open on Hover", checked: vm.openOnHover) { vm.openOnHover.toggle() })
            let mixerHover = Item("Mixer on Hover", checked: vm.mixerOnHover) { vm.mixerOnHover.toggle() }
            mixerHover.toolTip = "Off: hovering opens Home. On: hovering opens the Mixer. Click still follows what you tapped."
            menu.addItem(mixerHover)
        }
        let peek = Item("Expand on New Audio", checked: vm.expandOnNewAudio) { vm.expandOnNewAudio.toggle() }
        peek.toolTip = "Off: a new song or app does not drop a banner or widen the notch. Agent alerts are unchanged."
        menu.addItem(peek)
        let replace = Item(hud.waitingForAccess ? "Replace System HUD (waiting for Accessibility)" : "Replace System HUD",
                           checked: hud.replaceSystemHUD) {
            hud.setReplaceSystemHUD(!hud.replaceSystemHUD)
            if hud.replaceSystemHUD && !MediaKeyTap.isTrusted {
                vm.showToast("Allow NotchBar in Privacy & Security > Accessibility.")
            }
        }
        replace.toolTip = "Handles the volume and brightness keys so only the notch HUD appears. Needs Accessibility access."
        menu.addItem(replace)

        let screenshots = Item("Hide from Screenshots", checked: vm.hideFromScreenshots) { vm.hideFromScreenshots.toggle() }
        screenshots.toolTip = "Leaves the notch out of screenshots, screen recordings and shared screens."
        menu.addItem(screenshots)

        let clipboard = vm.clipboard
        if vm.isEnabled(.clipboard) {
            menu.addItem(Item("Pause Clipboard History", checked: clipboard.isPaused) { clipboard.isPaused.toggle() })
            menu.addItem(Item("Clear Clipboard History") { clipboard.clearUnpinned() })
        }

        let login = SMAppService.mainApp
        menu.addItem(Item("Launch at Login", checked: login.status == .enabled) {
            do {
                if login.status == .enabled { try login.unregister() } else { try login.register() }
            } catch {
                vm.showToast("Launch at Login needs the app in /Applications.")
            }
        })
    }

    private static func addQuickItems(to menu: NSMenu, vm: NotchViewModel) {
        menu.addItem(Item("Einstellungen…") { vm.showSettings() })
        menu.addItem(.separator())
        menu.addItem(Item("Mixer on Hover", checked: vm.mixerOnHover) { vm.mixerOnHover.toggle() })
        menu.addItem(Item("Keep Awake", checked: vm.awake.isOn) { vm.awake.toggle() })
    }

    private static func addTickerItems(to menu: NSMenu, vm: NotchViewModel) {
        let ticker = vm.ticker
        menu.addItem(Item("Show Ticker", checked: ticker.isEnabled) { ticker.isEnabled.toggle() })
        menu.addItem(submenu("Ticker Sources", items: TickerStore.Source.allCases.map { source in
            Item(source.title, checked: ticker.sources.contains(source)) { ticker.toggle(source) }
        }))
        menu.addItem(Item("Ticker Settings…") {
            vm.showsAppearance = false
            vm.showsTickerSettings = true
            vm.open(.home)
        })
    }

    private static func submenu(_ title: String, items: [NSMenuItem]) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let sub = NSMenu()
        sub.autoenablesItems = false
        items.forEach(sub.addItem)
        item.submenu = sub
        return item
    }
}
