// Based on NotchBar (https://github.com/srisanthosh/NotchBar), GPLv3.
// Original copyright remains with the NotchBar authors. Notch DJ changes are under the same license.
import AppKit
import ApplicationServices

/// The keyboard's play, next and previous keys, for players that can't be scripted.
/// macOS delivers them to the app it shows in Now Playing. Posting needs Accessibility access.
@MainActor
enum MediaKey {
    /// NX_KEYTYPE_PLAY, NX_KEYTYPE_NEXT and NX_KEYTYPE_PREVIOUS from IOKit's ev_keymap.h.
    private static func code(_ command: PlayerScripts.Command) -> Int {
        switch command {
        case .toggle: return 16
        case .next: return 17
        case .previous: return 18
        }
    }

    static func post(_ command: PlayerScripts.Command) {
        guard AXIsProcessTrusted() else { return }
        let key = code(command)
        for down in [true, false] {
            let state = down ? 0xA : 0xB
            let event = NSEvent.otherEvent(
                with: .systemDefined,
                location: .zero,
                modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(state << 8)),
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                subtype: 8,
                data1: (key << 16) | (state << 8),
                data2: -1
            )
            event?.cgEvent?.post(tap: .cghidEventTap)
        }
    }
}
