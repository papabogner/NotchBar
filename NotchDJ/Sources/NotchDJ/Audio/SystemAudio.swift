// Based on NotchBar (https://github.com/srisanthosh/NotchBar), GPLv3.
// Original copyright remains with the NotchBar authors. Notch DJ changes are under the same license.
import AppKit
import CoreAudio
import AudioToolbox

/// Default output device volume via CoreAudio. Listens for changes from any source, and
/// reports when the output switches to another device, such as headphones connecting.
@MainActor
final class SystemAudio {
    var onChange: ((Float, Bool) -> Void)?
    /// Called with the previous and the new output device.
    var onOutputChange: ((AudioOutput?, AudioOutput) -> Void)?
    /// More listeners for the same change. Empty unless the volume mixer is actually adjusting apps.
    private var outputHandlers: [UUID: (AudioOutput?, AudioOutput) -> Void] = [:]
    /// Volume listeners besides the HUD. Empty unless the mixer strip is on screen.
    private var volumeHandlers: [UUID: (Float, Bool) -> Void] = [:]
    private var device = AudioDeviceID(0)
    private var listening: AudioDeviceID?
    private var output: AudioOutput?

    private static var volumeAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
        mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
    private static var muteAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute,
        mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
    private static var defaultDeviceAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)

    private lazy var changeBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
        DispatchQueue.main.async { MainActor.assumeIsolated { self?.emit() } }
    }

    func start() {
        bind()
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &Self.defaultDeviceAddress, .main) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.bind() }
        }
    }

    private func bind() {
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &Self.defaultDeviceAddress, 0, nil, &size, &id)
        if let old = listening {
            AudioObjectRemovePropertyListenerBlock(old, &Self.volumeAddress, .main, changeBlock)
            AudioObjectRemovePropertyListenerBlock(old, &Self.muteAddress, .main, changeBlock)
        }
        device = id
        AudioObjectAddPropertyListenerBlock(id, &Self.volumeAddress, .main, changeBlock)
        AudioObjectAddPropertyListenerBlock(id, &Self.muteAddress, .main, changeBlock)
        listening = id

        let previous = output
        let current = AudioOutput(device: id)
        output = current
        // The first reading happens at launch, which isn't a change.
        if let previous, previous.id != current.id {
            onOutputChange?(previous, current)
            if !outputHandlers.isEmpty {
                let handlers = outputHandlers
                handlers.values.forEach { $0(previous, current) }
            }
        }
    }

    func addOutputHandler(_ handler: @escaping (AudioOutput?, AudioOutput) -> Void) -> UUID {
        let id = UUID()
        outputHandlers[id] = handler
        return id
    }

    func removeOutputHandler(_ id: UUID) {
        outputHandlers.removeValue(forKey: id)
    }

    func addVolumeHandler(_ handler: @escaping (Float, Bool) -> Void) -> UUID {
        let id = UUID()
        volumeHandlers[id] = handler
        return id
    }

    func removeVolumeHandler(_ id: UUID) {
        volumeHandlers.removeValue(forKey: id)
    }

    /// Name of the current default output. "System" until the first device is known.
    var outputName: String { output?.name ?? "System" }

    private func emit() {
        onChange?(volume, isMuted)
        guard !volumeHandlers.isEmpty else { return }
        let handlers = volumeHandlers
        let value = volume
        let muted = isMuted
        handlers.values.forEach { $0(value, muted) }
    }

    var volume: Float {
        var v = Float32(0)
        var size = UInt32(4)
        AudioObjectGetPropertyData(device, &Self.volumeAddress, 0, nil, &size, &v)
        return v
    }

    var isMuted: Bool {
        guard AudioObjectHasProperty(device, &Self.muteAddress) else { return false }
        var m = UInt32(0)
        var size = UInt32(4)
        AudioObjectGetPropertyData(device, &Self.muteAddress, 0, nil, &size, &m)
        return m != 0
    }

    var canSetVolume: Bool {
        var settable = DarwinBoolean(false)
        return AudioObjectIsPropertySettable(device, &Self.volumeAddress, &settable) == noErr && settable.boolValue
    }

    func setVolume(_ value: Float) {
        var v = Float32(min(1, max(0, value)))
        AudioObjectSetPropertyData(device, &Self.volumeAddress, 0, nil, 4, &v)
        if v > 0 && isMuted { setMuted(false) }
    }

    func setMuted(_ muted: Bool) {
        guard AudioObjectHasProperty(device, &Self.muteAddress) else { return }
        var m = UInt32(muted ? 1 : 0)
        AudioObjectSetPropertyData(device, &Self.muteAddress, 0, nil, 4, &m)
    }

    /// Output devices Core Audio is exposing right now, including AirPlay.
    func outputDevices() -> [AudioDeviceChoice] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap { id in
            guard Self.hasOutputStreams(id), let uid = Self.deviceUID(id), !uid.isEmpty else { return nil }
            return AudioDeviceChoice(uid: uid, name: AudioOutput(device: id).name, objectID: id)
        }
    }

    func currentOutputUID() -> String { Self.deviceUID(device) ?? "" }

    /// Makes one of `outputDevices()` the system default. The mixer hears it through the existing listener.
    func setDefaultOutput(uid: String) {
        guard let match = outputDevices().first(where: { $0.uid == uid }) else { return }
        var id = match.objectID
        let size = UInt32(MemoryLayout<AudioDeviceID>.size)
        AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &Self.defaultDeviceAddress, 0, nil, size, &id)
    }

    private static func deviceUID(_ id: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }

    private static func hasOutputStreams(_ id: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr else { return false }
        return size >= UInt32(MemoryLayout<AudioStreamID>.size)
    }
}

/// One output the mixer can route to. `uid` is what gets saved.
struct AudioDeviceChoice: Identifiable, Equatable {
    var uid: String
    var name: String
    var objectID: AudioDeviceID
    var id: String { uid }
}

