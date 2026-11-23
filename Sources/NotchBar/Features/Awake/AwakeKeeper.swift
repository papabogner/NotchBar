import Foundation
import Combine
import IOKit.pwr_mgt

/// Stops the Mac from idle-sleeping while the menu item is on. The display can still dim.
@MainActor
final class AwakeKeeper: ObservableObject {
    @Published private(set) var isOn: Bool
    private var assertion: IOPMAssertionID = 0

    init() {
        isOn = false
        if UserDefaults.standard.bool(forKey: "keepAwake") { setOn(true) }
    }

    func toggle() { setOn(!isOn) }

    func setOn(_ on: Bool) {
        if on {
            guard assertion == 0 else { isOn = true; return }
            guard acquire() else { return }
        } else {
            release()
        }
        isOn = on
        UserDefaults.standard.set(on, forKey: "keepAwake")
    }

    private func acquire() -> Bool {
        var id: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypeNoIdleSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "NotchBar" as CFString,
            &id)
        guard result == kIOReturnSuccess, id != 0 else { return false }
        assertion = id
        return true
    }

    private func release() {
        if assertion != 0 {
            IOPMAssertionRelease(assertion)
            assertion = 0
        }
    }
}
