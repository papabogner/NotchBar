// Based on NotchBar (https://github.com/srisanthosh/NotchBar), GPLv3.
// Original copyright remains with the NotchBar authors. Notch DJ changes are under the same license.
import Carbon
import Foundation

/// Global shortcuts ⌃⌥N and ⌃⌥M. On by default; Settings and onboarding can turn them off.
/// Carbon hot keys, so there is no Accessibility prompt.
@MainActor
final class HotkeyController: ObservableObject {
    static weak var current: HotkeyController?

    @Published private(set) var isEnabled: Bool
    var onToggle: (@MainActor () -> Void)?
    /// ⌃⌥M. Opens the mixer, or switches MIXER / DJ when it is already open.
    var onMixer: (@MainActor () -> Void)?

    private var keys: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    private static let signature: OSType = 0x4E74484B

    init() {
        isEnabled = DJDefaults.suite.object(forKey: "globalHotkeys") as? Bool ?? true
    }

    /// Call once the callbacks exist. Registers nothing while the feature is off.
    func installIfNeeded() {
        Self.current = self
        if isEnabled { registerKeys() }
    }

    func setEnabled(_ on: Bool) {
        guard on != isEnabled else { return }
        isEnabled = on
        DJDefaults.suite.set(on, forKey: "globalHotkeys")
        if on { registerKeys() } else { unregisterKeys() }
    }

    fileprivate func handle(_ id: UInt32) {
        guard isEnabled else { return }
        switch id {
        case 1: onToggle?()
        case 2: onMixer?()
        default: break
        }
    }

    private func registerKeys() {
        unregisterKeys()
        Self.current = self
        if handler == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), notchHotKeyHandler, 1, &spec, nil, &handler)
        }
        let mods = UInt32(controlKey | optionKey)
        addKey(UInt32(kVK_ANSI_N), mods, 1)
        addKey(UInt32(kVK_ANSI_M), mods, 2)
    }

    private func addKey(_ code: UInt32, _ mods: UInt32, _ id: UInt32) {
        var ref: EventHotKeyRef?
        let hotID = EventHotKeyID(signature: Self.signature, id: id)
        let status = RegisterEventHotKey(code, mods, hotID, GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref { keys.append(ref) }
    }

    private func unregisterKeys() {
        for key in keys { UnregisterEventHotKey(key) }
        keys.removeAll()
    }
}

/// The process-wide hotkey owner. Settings and onboarding read it without holding the app delegate.
@MainActor
enum DJHotkeys {
    static let shared = HotkeyController()
}

private func notchHotKeyHandler(_ next: EventHandlerCallRef?, _ event: EventRef?, _ user: UnsafeMutableRawPointer?) -> OSStatus {
    guard let event else { return noErr }
    var hotKeyID = EventHotKeyID(signature: 0, id: 0)
    let status = withUnsafeMutableBytes(of: &hotKeyID) { raw in
        GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                          nil, raw.count, nil, raw.baseAddress)
    }
    guard status == noErr else { return status }
    let identifier = hotKeyID.id
    DispatchQueue.main.async {
        MainActor.assumeIsolated { HotkeyController.current?.handle(identifier) }
    }
    return noErr
}
