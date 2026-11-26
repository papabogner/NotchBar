import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var router: SettingsRouter
    @EnvironmentObject private var prefs: DJPreferences

    var body: some View {
        TabView(selection: $router.tab) {
            GeneralSettings()
                .tabItem { SwiftUI.Label("General", systemImage: "gearshape") }
                .tag(SettingsTab.general)
            AppearanceSettings()
                .tabItem { SwiftUI.Label("Appearance", systemImage: "paintpalette") }
                .tag(SettingsTab.appearance)
            AudioSettings()
                .tabItem { SwiftUI.Label("Audio", systemImage: "waveform") }
                .tag(SettingsTab.audio)
            ExtrasSettings()
                .tabItem { SwiftUI.Label("Extras", systemImage: "sparkles") }
                .tag(SettingsTab.extras)
            AboutSettings()
                .tabItem { SwiftUI.Label("About", systemImage: "info.circle") }
                .tag(SettingsTab.about)
        }
        .frame(width: 620, height: 540)
        // Settings use the system look. The template only shows in previews.
        .environment(\.djTokens, TemplateID.studio.template.tokens(dark: prefs.systemIsDark))
    }
}

// MARK: General

private struct GeneralSettings: View {
    @EnvironmentObject private var model: DJModel
    @EnvironmentObject private var prefs: DJPreferences
    @ObservedObject private var hotkeys = DJHotkeys.shared
    @State private var login = LoginItem.isEnabled
    @State private var needsApproval = LoginItem.needsApproval

    var body: some View {
        Form {
            Section {
                Toggle("Open the panel when the pointer rests on the notch", isOn: $prefs.openOnHover)
                Toggle("Open Notch DJ at login", isOn: Binding(get: { login }, set: { setLogin($0) }))
                if needsApproval {
                    HStack {
                        Text("macOS needs your OK in Login Items.")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Open Login Items") { LoginItem.openSettings() }
                    }
                }
            }
            Section("Keyboard") {
                Toggle("Use global shortcuts", isOn: Binding(get: { hotkeys.isEnabled }, set: { hotkeys.setEnabled($0) }))
                LabeledContent {
                    Text(verbatim: "⌃⌥N")
                } label: {
                    Text("Open or close the panel")
                }
                LabeledContent {
                    Text(verbatim: "⌃⌥M")
                } label: {
                    Text("Open MIXER, then switch between MIXER and DJ")
                }
            }
            Section {
                Button("Show Onboarding…") { model.showOnboarding() }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            login = LoginItem.isEnabled
            needsApproval = LoginItem.needsApproval
        }
    }

    private func setLogin(_ on: Bool) {
        LoginItem.set(on)
        login = LoginItem.isEnabled
        needsApproval = LoginItem.needsApproval
    }
}

// MARK: Appearance

private struct AppearanceSettings: View {
    @EnvironmentObject private var prefs: DJPreferences

    var body: some View {
        let current = prefs.template.template
        Form {
            Section("Template") {
                HStack(alignment: .top, spacing: 16) {
                    TemplateGrid()
                        .frame(width: 236)
                    VStack(alignment: .leading, spacing: 8) {
                        TemplatePreview(id: prefs.template, width: 300)
                        Text("The DJ tab with sample audio.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
            Section {
                Picker("Appearance", selection: $prefs.appearance) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Text(verbatim: mode.title).tag(mode)
                    }
                }
                .disabled(!(current.supportsLight && current.supportsDark))
                Picker("Panel size", selection: $prefs.panelSize) {
                    ForEach(PanelSize.allCases) { size in
                        Text(verbatim: size.title).tag(size)
                    }
                }
            } footer: {
                if !(current.supportsLight && current.supportsDark) {
                    Text("\(current.name) has a dark look only.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: Audio

private struct AudioSettings: View {
    @EnvironmentObject private var mixer: AppVolumeMixer

    var body: some View {
        Form {
            Section {
                PermissionStatusRow(boxed: false)
            } header: {
                Text("System Audio Recording")
            } footer: {
                Text("Notch DJ taps an app's audio only to change its volume, tone or meter. It is processed live on this Mac and never recorded, stored or sent anywhere.")
                    .foregroundStyle(.secondary)
            }
            Section("Mixer") {
                Toggle("Live meters while the panel is open",
                       isOn: Binding(get: { mixer.liveMeters }, set: { mixer.setLiveMeters($0) }))
                Toggle("Show silent apps in MIXER",
                       isOn: Binding(get: { mixer.showSilentApps }, set: { mixer.setShowSilent($0) }))
                Picker("Crossfader curve", selection: $mixer.crossCurve) {
                    ForEach(CrossCurve.allCases) { curve in
                        Text(verbatim: curve.title).tag(curve)
                    }
                }
                HStack {
                    Text("Every app back to normal volume, unmuted, on the system output.")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Reset All Apps") { mixer.resetAll() }
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: Extras

private struct ExtrasSettings: View {
    @EnvironmentObject private var mixer: AppVolumeMixer
    @EnvironmentObject private var prefs: DJPreferences
    @EnvironmentObject private var permissions: PermissionCenter

    var body: some View {
        Form {
            Section {
                Toggle("Remember each app's volume",
                       isOn: Binding(get: { mixer.autoApply }, set: { mixer.setAutoApply($0) }))
            } header: {
                Text("Volume memory")
            } footer: {
                Text("Levels, mutes and outputs are kept per app. When an app starts playing, its level comes back. Off: saved levels wait until you move a fader.")
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle("Lower other apps during calls",
                       isOn: Binding(get: { mixer.ducking }, set: { mixer.setDucking($0) }))
                Group {
                    LabeledContent {
                        HStack(spacing: 10) {
                            Slider(value: Binding(get: { mixer.duckLevel }, set: { mixer.setDuckLevel($0) }), in: 0...0.8)
                                .frame(width: 180)
                            Text(verbatim: "\(Int((mixer.duckLevel * 100).rounded())) %")
                                .monospacedDigit()
                                .frame(width: 44, alignment: .trailing)
                        }
                    } label: {
                        Text("Lower to")
                    }
                    Toggle("Count calls in the browser, such as Meet",
                           isOn: Binding(get: { mixer.duckBrowserMeet }, set: { mixer.setDuckMeet($0) }))
                    Picker("Also count as a call", selection: Binding(get: { mixer.duckAppID }, set: { mixer.setDuckApp($0) })) {
                        Text("None").tag(String?.none)
                        if let saved = mixer.duckAppID, !mixer.rows.contains(where: { $0.id == saved }) {
                            Text(verbatim: MixerDisplayName.short(bundleID: saved, fallback: saved)).tag(String?.some(saved))
                        }
                        ForEach(mixer.rows) { row in
                            Text(verbatim: row.name).tag(String?.some(row.id))
                        }
                    }
                }
                .disabled(!mixer.ducking)
            } header: {
                Text("Auto-ducking")
            } footer: {
                Text("A call is on while Zoom, FaceTime, Teams, Slack, Discord or a similar app uses the microphone. Needs audio access.")
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle("Control other apps with the media keys", isOn: Binding(get: { prefs.mediaKeys }, set: { setMediaKeys($0) }))
                if prefs.mediaKeys {
                    HStack {
                        Image(systemName: permissions.accessibility ? "checkmark.circle.fill" : "exclamationmark.circle")
                            .foregroundStyle(permissions.accessibility ? Color.green : Color.orange)
                        Text(verbatim: permissions.accessibility ? String(localized: "Accessibility is on")
                                                                 : String(localized: "Accessibility is off"))
                        Spacer()
                        if !permissions.accessibility {
                            Button("Allow…") { permissions.requestAccessibility() }
                        }
                    }
                }
            } header: {
                Text("Media keys")
            } footer: {
                Text("Music and Spotify are controlled directly. For other apps, such as a browser, the transport buttons send the play, next and previous keys. macOS asks for Accessibility for that.")
                    .foregroundStyle(.secondary)
            }
            Section {
                Picker("Menu bar icon", selection: $prefs.menuBarMode) {
                    ForEach(MenuBarMode.allCases) { mode in
                        Text(verbatim: mode.title).tag(mode)
                    }
                }
            } header: {
                Text("Menu bar")
            } footer: {
                Text("On a screen without a notch the icon opens the panel, and the pill at the top of the screen is hidden.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func setMediaKeys(_ on: Bool) {
        prefs.mediaKeys = on
        if on && !permissions.accessibility { permissions.requestAccessibility() }
    }
}

// MARK: About

private struct AboutSettings: View {
    @Environment(\.djTokens) private var tokens

    private static let upstream = URL(string: "https://github.com/srisanthosh/NotchBar")
    private static let license = URL(string: "https://www.gnu.org/licenses/gpl-3.0.html")

    var body: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 0)
            HStack(spacing: 2) {
                Text(verbatim: "NOTCH ")
                Text(verbatim: "DJ").foregroundStyle(tokens.accent)
            }
            .font(.system(size: 34, weight: .heavy))
            Text("Version \(Self.version) (\(Self.build))")
                .foregroundStyle(.secondary)
            Text("Per-app volume, a mixer and two decks in your Mac's notch.")
            Text("Audio is processed on this Mac and never leaves it.")
                .foregroundStyle(.secondary)
            Divider().frame(width: 300)
            Text("Based on NotchBar by srisanthosh. Notch DJ is free software under the GNU GPL, version 3.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            HStack(spacing: 16) {
                if let upstream = Self.upstream { Link("NotchBar on GitHub", destination: upstream) }
                if let license = Self.license { Link("GPLv3", destination: license) }
            }
            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–"
    }

    private static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "–"
    }
}
