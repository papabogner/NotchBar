import AppKit
import ServiceManagement
import SwiftUI

/// A normal window, so text fields take the keyboard without the notch becoming key.
@MainActor
enum SettingsWindow {
    private static var window: NSWindow?

    static func show(vm: NotchViewModel) {
        NSApp.activate(ignoringOtherApps: true)
        if window == nil {
            let host = NSHostingController(rootView: SettingsRoot(vm: vm))
            let window = NSWindow(contentViewController: host)
            window.title = "Einstellungen"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 780, height: 540))
            window.isReleasedWhenClosed = false
            self.window = window
        }
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }
}

private struct SettingsRoot: View {
    @ObservedObject var vm: NotchViewModel
    @State private var section: Pane = .general

    private enum Pane: String, CaseIterable, Identifiable {
        case general, audio, look, ticker, integrations, shortcuts, about
        var id: String { rawValue }
        var title: String {
            switch self {
            case .general: return "Allgemein"
            case .audio: return "Audio & Mixer"
            case .look: return "Darstellung"
            case .ticker: return "Ticker"
            case .integrations: return "Integrationen"
            case .shortcuts: return "Kurzbefehle"
            case .about: return "Über"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(panes, selection: $section) { item in
                Text(item.title).tag(item)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 168, ideal: 190)
        } detail: {
            ScrollView {
                pane.padding(24).frame(maxWidth: 560, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: 760, minHeight: 500)
    }

    /// Ticker and integrations stay out of the sidebar until their switch is on.
    private var panes: [Pane] {
        var items: [Pane] = [.general, .audio, .look]
        if vm.ticker.isEnabled { items.append(.ticker) }
        if vm.spotify.isEnabled || vm.mini.isEnabled || vm.portfolio.isEnabled { items.append(.integrations) }
        items.append(contentsOf: [.shortcuts, .about])
        return items
    }

    @ViewBuilder private var pane: some View {
        switch section {
        case .general: general
        case .audio: audio
        case .look: look
        case .ticker: ticker
        case .integrations: integrations
        case .shortcuts: shortcuts
        case .about: about
        }
    }

    private var general: some View {
        Form {
            Section("Notch") {
                Toggle("Beim Darüberfahren öffnen", isOn: $vm.openOnHover)
                Text("Die geschlossene Notch öffnet sich, wenn der Zeiger kurz bleibt.").font(.caption).foregroundStyle(.secondary)
                Toggle("Bei neuem Ton aufklappen", isOn: $vm.expandOnNewAudio)
                Text("Aus: ein neues Lied ändert die geschlossene Notch nicht.").font(.caption).foregroundStyle(.secondary)
                Toggle("Aus Bildschirmaufnahmen ausblenden", isOn: $vm.hideFromScreenshots)
            }
            Section("Mitteilungen") {
                Toggle("Lautstärke und Helligkeit", isOn: Binding(get: { vm.hudService.showHUDs }, set: { vm.hudService.showHUDs = $0 }))
                Toggle("Kopfhörer", isOn: Binding(get: { vm.hudService.showDevices }, set: { vm.hudService.showDevices = $0 }))
                Toggle("Diktat", isOn: Binding(get: { vm.dictation.isEnabled }, set: { vm.dictation.isEnabled = $0 }))
                Toggle("System-HUD ersetzen", isOn: Binding(get: { vm.hudService.replaceSystemHUD }, set: { vm.hudService.setReplaceSystemHUD($0) }))
            }
            Section("Extras (Leistung)") {
                Text("Aus, bis du sie einschaltest. Dateien, Feeds und Abfragen starten erst dann.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Claude-Nutzung", isOn: Binding(get: { vm.usage.isMonitoring }, set: { on in
                    vm.usage.setMonitoring(on)
                    if !on, vm.tab == .claude { vm.tab = vm.preferredTab }
                }))
                Toggle("Agentenstatus", isOn: $vm.agentsExtra)
                Toggle("Ticker", isOn: Binding(get: { vm.ticker.isEnabled }, set: { vm.ticker.isEnabled = $0 }))
                Toggle("Mac mini", isOn: Binding(get: { vm.mini.isEnabled }, set: { vm.mini.setEnabled($0) }))
                Toggle("Portfolio", isOn: Binding(get: { vm.portfolio.isEnabled }, set: { vm.portfolio.setEnabled($0) }))
                Toggle("Spotify Connect", isOn: Binding(get: { vm.spotify.isEnabled }, set: { vm.spotify.setEnabled($0) }))
            }
            Section("Menüleiste") {
                Toggle("Seltene Symbole einklappen", isOn: Binding(get: { MenuBarOrganizer.shared.isEnabled }, set: { MenuBarOrganizer.shared.setEnabled($0) }))
                Toggle("Beim Anmelden öffnen", isOn: Binding(get: { SMAppService.mainApp.status == .enabled }, set: { value in
                    if value { try? SMAppService.mainApp.register() } else { try? SMAppService.mainApp.unregister() }
                }))
            }
        }
        .formStyle(.grouped)
    }

    private var audio: some View {
        Form {
            Section("Mixer") {
                Toggle("Mixer beim Darüberfahren", isOn: $vm.mixerOnHover)
                Text("Aus: Hover öffnet Home. An: Hover öffnet den Mixer.").font(.caption).foregroundStyle(.secondary)
                Toggle("Fader auf Home", isOn: Binding(get: { vm.homeLayout.isEnabled(.mixer) }, set: { vm.homeLayout.setEnabled(.mixer, $0); vm.refreshMixerSurfaces() }))
                Toggle("Gespeicherte Lautstärke anwenden", isOn: Binding(get: { vm.volumes.autoApply }, set: { vm.volumes.setAutoApply($0) }))
                Toggle("Wach bleiben", isOn: Binding(get: { vm.awake.isOn }, set: { vm.awake.setOn($0) }))
            }
            Section("Ducking") {
                Toggle("Andere Apps leiser bei Anrufen", isOn: Binding(get: { vm.volumes.ducking }, set: { vm.volumes.setDucking($0) }))
                Text("Zoom, Teams, FaceTime und Webex senken den Rest auf ein Viertel.").font(.caption).foregroundStyle(.secondary)
                Toggle("Auch Google Meet im Browser", isOn: Binding(get: { vm.volumes.duckBrowserMeet }, set: { vm.volumes.setDuckMeet($0) }))
            }
        }
        .formStyle(.grouped)
    }

    private var look: some View {
        VStack(alignment: .leading, spacing: 16) {
            NotchPreview(theme: vm.appearance.displayed(album: nil))
            AppearancePanel(appearance: vm.appearance, close: {}, embedded: true)
        }
    }

    private var ticker: some View {
        TickerSettingsForm(vm: vm)
    }

    private var integrations: some View {
        Form {
            Section("Spotify") {
                Toggle("Connect anzeigen", isOn: Binding(get: { vm.spotify.isEnabled }, set: { vm.spotify.setEnabled($0) }))
                TextField("Client-ID", text: Binding(get: { vm.spotify.clientID }, set: { vm.spotify.clientID = $0 }))
                Text("Redirect-URI: \(SpotifyConnect.redirectURI)").font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Aus Zwischenablage") { vm.spotify.pasteClientID() }
                    Button(vm.spotify.isSignedIn ? "Erneut anmelden" : "Anmelden") { vm.spotify.signIn() }
                    if vm.spotify.isSignedIn { Button("Abmelden") { vm.spotify.signOut() } }
                }
            }
            Section("Mac mini") {
                Toggle("Status anzeigen", isOn: Binding(get: { vm.mini.isEnabled }, set: { vm.mini.setEnabled($0) }))
                TextField("SSH-Alias", text: Binding(get: { vm.mini.host }, set: { vm.mini.setHost($0) }))
                Text("ssh -o BatchMode=yes, kein Passwortdialog.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Portfolio") {
                Toggle("Summe anzeigen", isOn: Binding(get: { vm.portfolio.isEnabled }, set: { vm.portfolio.setEnabled($0) }))
                Button("Bestände bearbeiten…") { vm.portfolio.editHoldings() }
                Text("Die Vorlage enthält Beispielmengen, nicht deine.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Agents") {
                Text("Statusdateien liegen in ~/Library/Application Support/NotchBar/agents. Die Agents-Karte auf Home und die Ticker-Quelle schalten die Überwachung ein.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var shortcuts: some View {
        Form {
            Toggle("Globale Kurzbefehle", isOn: Binding(get: { vm.hotkeys.isEnabled }, set: { vm.hotkeys.setEnabled($0) }))
            LabeledContent("Notch öffnen", value: "⌃⌥N")
            LabeledContent("Stumm", value: "⌃⌥M")
            LabeledContent("Nächste Szene", value: "⌃⌥S")
            LabeledContent("Einstellungen", value: "⌘,")
        }
        .formStyle(.grouped)
    }

    private var about: some View {
        Form {
            LabeledContent("NotchBar", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
            Text("Lautstärke, Medien und ein kurzer Blick. Alles bleibt auf diesem Mac.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}

private struct NotchPreview: View {
    var theme: NotchAppearance.Theme

    var body: some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.black).frame(width: 120, height: 18)
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: theme.cornerRadius / 3, style: .continuous)
                    .fill(theme.usesGlass ? Color.white.opacity(0.12) : theme.background)
                if theme.backgroundStyle == .gradient {
                    RoundedRectangle(cornerRadius: theme.cornerRadius / 3, style: .continuous)
                        .fill(LinearGradient(colors: [theme.background, theme.backgroundEnd], startPoint: .top, endPoint: .bottom))
                }
                Capsule().fill(theme.accent).frame(width: theme.faderStyle == .line ? 4 : 8, height: 36).padding(.leading, 16)
            }
            .frame(width: 220, height: 64)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16).fill(.black.opacity(0.2)))
    }
}

private struct TickerSettingsForm: View {
    @ObservedObject var vm: NotchViewModel
    @State private var feeds = ""
    @State private var token = ""

    var body: some View {
        Form {
            Toggle("Ticker anzeigen", isOn: Binding(get: { vm.ticker.isEnabled }, set: { vm.ticker.isEnabled = $0 }))
            Text("Langsam rotierende Zeile neben der geschlossenen Notch. Aus, bis du ihn einschaltest.")
                .font(.caption).foregroundStyle(.secondary)
            LabeledContent("Breite") { Slider(value: Binding(get: { vm.ticker.width }, set: { vm.ticker.width = $0 }), in: 120...280, step: 20) }
            LabeledContent("Wechsel") { Slider(value: Binding(get: { vm.ticker.interval }, set: { vm.ticker.interval = $0 }), in: 4...30, step: 1) }
            Section("Quellen") {
                ForEach(TickerStore.Source.allCases.filter { $0 != .x || vm.newsTicker.hasToken }) { source in
                    Toggle(sourceTitle(source), isOn: Binding(get: { vm.ticker.sources.contains(source) }, set: { _ in vm.ticker.toggle(source) }))
                }
            }
            Section("Dieser Mac") {
                Text("Deutsche Kurzsätze: Agents, Fokus-App, Downloads, Mac mini, Akku, laufender Titel. Zusätzliche Zeilen als JSON in ~/Library/Application Support/NotchBar/ticker/.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Nachrichten") {
                TextEditor(text: $feeds).frame(height: 88)
                Button("Feeds sichern") {
                    vm.newsTicker.feeds = feeds.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                    vm.newsTicker.refresh()
                }
            }
            Section("X") {
                SecureField("Bearer-Token", text: $token)
                TextField("Suchanfrage", text: Binding(get: { vm.newsTicker.xQuery }, set: { vm.newsTicker.xQuery = $0 }))
                Button("Token sichern") { vm.newsTicker.setToken(token); token = "" }
                Text("Ohne Token bleibt die X-Quelle aus. Schlagzeilen können auch über den ticker-Ordner kommen.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            TextField("Eigene Zeile", text: Binding(get: { vm.ticker.customText }, set: { vm.ticker.customText = $0 }))
        }
        .formStyle(.grouped)
        .onAppear { feeds = vm.newsTicker.feeds.joined(separator: "\n") }
    }

    private func sourceTitle(_ source: TickerStore.Source) -> String {
        switch source {
        case .nowPlaying: return "Jetzt läuft"
        case .calendar: return "Als Nächstes"
        case .claude: return "Claude"
        case .agents: return "Agents"
        case .custom: return "Eigene Zeile"
        case .feed: return "Eigener Feed"
        case .crypto: return "Krypto"
        case .mini: return "Mac mini"
        case .portfolio: return "Portfolio"
        case .thisMac: return "Dieser Mac"
        case .news: return "Nachrichten"
        case .x: return "X"
        }
    }
}
