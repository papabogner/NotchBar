import AppKit
import ServiceManagement
import SwiftUI

@MainActor
enum DJSettings {
    private static var window: NSWindow?

    static func show(model: DJModel) {
        NSApp.activate(ignoringOtherApps: true)
        model.mixer.refreshDevices()
        if window == nil {
            let host = NSHostingController(rootView: DJSettingsView(model: model))
            let window = NSWindow(contentViewController: host)
            window.title = "Notch DJ Settings"
            window.styleMask = [.titled, .closable]
            window.setContentSize(NSSize(width: 420, height: 460))
            window.isReleasedWhenClosed = false
            self.window = window
        }
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }
}

private struct DJSettingsView: View {
    @ObservedObject var model: DJModel
    @ObservedObject private var keys = DJHotkeys.shared
    @State private var launch = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section("Output") {
                Picker("Device", selection: outputBinding) {
                    let devices = model.mixer.outputDevices()
                    let current = model.mixer.currentOutputUID()
                    if !devices.contains(where: { $0.uid == current }) {
                        Text("Current").tag(current)
                    }
                    ForEach(devices) { device in
                        Text(device.name).tag(device.uid)
                    }
                }
            }
            Section("Mixer") {
                Toggle("Show silent apps", isOn: Binding(get: { model.mixer.showSilentApps }, set: { model.mixer.setShowSilent($0) }))
                Picker("Crossfader", selection: Binding(get: { model.mixer.crossCurve }, set: { model.mixer.crossCurve = $0 })) {
                    ForEach(CrossCurve.allCases) { curve in
                        Text(curve.title).tag(curve)
                    }
                }
                Toggle("Open when the pointer rests", isOn: Binding(get: { model.openOnHover }, set: { model.setOpenOnHover($0) }))
            }
            Section("Shortcuts") {
                Toggle("Hotkeys", isOn: Binding(get: { keys.isEnabled }, set: { keys.setEnabled($0) }))
                LabeledContent("Toggle notch", value: "⌃⌥N")
                LabeledContent("Mixer", value: "⌃⌥M")
                Text("Animations follow the system Reduce Motion setting.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle("Launch at login", isOn: $launch)
                    .onChange(of: launch) { _, on in
                        if on { try? SMAppService.mainApp.register() } else { try? SMAppService.mainApp.unregister() }
                    }
            }
        }
        .formStyle(.grouped)
        .padding(12)
    }

    private var outputBinding: Binding<String> {
        Binding(get: { model.mixer.currentOutputUID() }, set: { model.mixer.setSystemOutput(uid: $0) })
    }
}

/// The process-wide hotkey owner. Settings reads it without holding the app delegate.
@MainActor
enum DJHotkeys {
    static let shared = HotkeyController()
}
