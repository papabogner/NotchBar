// Based on NotchBar (https://github.com/srisanthosh/NotchBar), GPLv3.
// Original copyright remains with the NotchBar authors. Notch DJ changes are under the same license.
import CoreAudio
import Foundation

/// An audio output device, such as the built-in speakers or a pair of AirPods.
struct AudioOutput: Equatable {
    let id: AudioDeviceID
    let name: String
    let transport: UInt32

    init(device id: AudioDeviceID) {
        self.id = id
        name = Self.string(id, kAudioObjectPropertyName) ?? "Speakers"
        transport = Self.number(id, kAudioDevicePropertyTransportType) ?? 0
    }

    init(id: AudioDeviceID, name: String, transport: UInt32) {
        self.id = id
        self.name = name
        self.transport = transport
    }

    var isBluetooth: Bool {
        transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE
    }

    /// Headphones and speakers that come and go: Bluetooth and AirPlay.
    var isWireless: Bool { isBluetooth || transport == kAudioDeviceTransportTypeAirPlay }

    var symbol: String {
        let lower = name.lowercased()
        if lower.contains("airpods max") { return "airpodsmax" }
        if lower.contains("airpods pro") { return "airpodspro" }
        if lower.contains("airpods") { return "airpods" }
        if lower.contains("beats") || lower.contains("powerbeats") {
            if lower.contains("studio buds") { return "beats.studiobuds" }
            if lower.contains("fit pro") { return "beats.fitpro" }
            if lower.contains("powerbeats") { return "beats.powerbeatspro" }
            return "beats.headphones"
        }
        if Self.earbudWords.contains(where: lower.contains) { return "earbuds" }
        if lower.contains("homepod") { return "homepod.fill" }
        if transport == kAudioDeviceTransportTypeAirPlay { return "airplayaudio" }
        if lower.contains("speaker") || lower.contains("soundbar") { return "hifispeaker.fill" }
        return isBluetooth ? "headphones" : "speaker.wave.2.fill"
    }

    /// Words in the names of in-ear headphones from other makers: Galaxy Buds, Pixel Buds,
    /// FreeBuds, Sony WF-1000XM5, Jabra Elite, Nothing Ear (2), Soundcore Liberty and others.
    private static let earbudWords = ["buds", "earbud", "pods", "earphone", "in-ear", "wf-", "elite", "nothing ear",
                                      "ear (", "liberty", "tws", "freeclip"]

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }

    private static func string(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String? {
        var a = address(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &a, 0, nil, &size, &value) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }

    private static func number(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> UInt32? {
        var a = address(selector)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(id, &a, 0, nil, &size, &value) == noErr ? value : nil
    }
}
