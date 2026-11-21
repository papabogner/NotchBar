import AudioToolbox
import CoreAudio
import Darwin
import Foundation

/// Why a process tap was not installed. The app is left playing normally in either case.
enum TapStartError: Equatable {
    case permissionDenied
    case failed
}

/// Plays one app's output back through the current default device at a chosen gain.
///
/// The tap uses `mutedWhenTapped`, so the app's own stream goes silent only while this tap is
/// actually being read. If anything here fails, or the callback never runs, the tap is destroyed
/// and the app is audible again at full volume. At 100% the caller does not create a tap at all.
@available(macOS 14.4, *)
final class ProcessVolumeTap {
    let processObjects: [AudioObjectID]
    let createdAt = Date()
    /// Set on the main thread by the health check. The render callback never reads it.
    var healthChecked = false

    private var context: UnsafeMutablePointer<TapContext>?
    private var aggregate: AudioObjectID = 0
    private var tap: AudioObjectID = 0
    private var proc: AudioDeviceIOProcID?
    private var stopped = false

    private init(processObjects: [AudioObjectID], context: UnsafeMutablePointer<TapContext>,
                 aggregate: AudioObjectID, tap: AudioObjectID, proc: AudioDeviceIOProcID?) {
        self.processObjects = processObjects
        self.context = context
        self.aggregate = aggregate
        self.tap = tap
        self.proc = proc
    }

    deinit { stop() }

    func matches(_ objects: [AudioObjectID]) -> Bool { processObjects == objects }

    /// Lock-free. Safe to call while the render callback is running.
    func setGain(_ gain: Float) {
        guard let context else { return }
        let clamped = min(1, max(0, gain))
        let new = Int32(bitPattern: clamped.bitPattern)
        let ptr = int32Field(context, targetOffset)
        while true {
            let old = OSAtomicAdd32Barrier(0, ptr)
            if old == new || OSAtomicCompareAndSwap32Barrier(old, new, ptr) { return }
        }
    }

    var didRender: Bool {
        guard let context else { return false }
        return OSAtomicAdd32Barrier(0, int32Field(context, renderedOffset)) != 0
    }

    var hasFault: Bool {
        guard let context else { return true }
        return OSAtomicAdd32Barrier(0, int32Field(context, faultOffset)) != 0
    }

    /// Stops reading the tap first, so `mutedWhenTapped` releases the app, then destroys it.
    func stop() {
        guard !stopped else { return }
        stopped = true
        if let proc, aggregate != 0 {
            AudioDeviceStop(aggregate, proc)
            AudioDeviceDestroyIOProcID(aggregate, proc)
        }
        if aggregate != 0 { AudioHardwareDestroyAggregateDevice(aggregate) }
        if tap != 0 { AudioHardwareDestroyProcessTap(tap) }
        context?.deinitialize(count: 1)
        context?.deallocate()
        context = nil
        proc = nil
        aggregate = 0
        tap = 0
    }

    /// Installs the tap and starts reading it. On any failure nothing is left running.
    static func start(processObjects: [AudioObjectID], gain: Float) -> Result<ProcessVolumeTap, TapStartError> {
        let objects = processObjects.sorted()
        guard !objects.isEmpty, let output = defaultOutputRoute() else { return .failure(.failed) }

        let description = CATapDescription(stereoMixdownOfProcesses: objects)
        description.name = "NotchBar"
        description.isPrivate = true
        description.muteBehavior = .mutedWhenTapped

        var tapID = AudioObjectID(kAudioObjectUnknown)
        let created = AudioHardwareCreateProcessTap(description, &tapID)
        guard created == noErr, tapID != AudioObjectID(kAudioObjectUnknown) else {
            if tapID != AudioObjectID(kAudioObjectUnknown) { AudioHardwareDestroyProcessTap(tapID) }
            return .failure(created == kAudioDevicePermissionsError ? .permissionDenied : .failed)
        }

        let resources = TapResources()
        resources.tap = tapID
        // `defer` covers every failure below. Success clears the ids so they aren't destroyed twice.
        defer { resources.destroy() }

        let tapUID = readTapUID(tapID) ?? description.uuid.uuidString
        guard !tapUID.isEmpty else { return .failure(.failed) }

        // Drift compensation against a Bluetooth clock inserts and drops samples. Leave it off there.
        let drift = !output.bluetooth
        var aggregate = AudioObjectID(kAudioObjectUnknown)
        var status = AudioHardwareCreateAggregateDevice(aggregateDictionary(
            outputUID: output.uid, tapUID: tapUID, drift: drift, suppressHardwareInput: true) as CFDictionary, &aggregate)
        if status != noErr || aggregate == 0 {
            if aggregate != 0 { AudioHardwareDestroyAggregateDevice(aggregate) }
            aggregate = 0
            status = AudioHardwareCreateAggregateDevice(aggregateDictionary(
                outputUID: output.uid, tapUID: tapUID, drift: drift, suppressHardwareInput: false) as CFDictionary, &aggregate)
        }
        guard status == noErr, aggregate != 0 else { return .failure(.failed) }
        resources.aggregate = aggregate

        guard let inputFormat = streamFormat(aggregate, scope: kAudioObjectPropertyScopeInput),
              let outputFormat = streamFormat(aggregate, scope: kAudioObjectPropertyScopeOutput),
              isFloat32(inputFormat), isFloat32(outputFormat),
              inputFormat.mChannelsPerFrame > 0, outputFormat.mChannelsPerFrame > 0 else { return .failure(.failed) }

        let context = UnsafeMutablePointer<TapContext>.allocate(capacity: 1)
        let clamped = min(1, max(0, gain))
        var rate = inputFormat.mSampleRate
        if !(rate > 0) { rate = 48_000 }
        var step = Float(1.0 / (rate * 0.010))
        if !(step > 0) { step = 1 }
        context.initialize(to: TapContext(
            targetBits: Int32(bitPattern: clamped.bitPattern),
            fault: 0,
            rendered: 0,
            current: clamped,
            step: step,
            inputChannels: Int32(inputFormat.mChannelsPerFrame),
            outputChannels: Int32(outputFormat.mChannelsPerFrame),
            inputInterleaved: isInterleaved(inputFormat) ? 1 : 0,
            outputInterleaved: isInterleaved(outputFormat) ? 1 : 0))
        resources.context = context

        var proc: AudioDeviceIOProcID?
        let procStatus = AudioDeviceCreateIOProcID(aggregate, volumeTapIOProc, UnsafeMutableRawPointer(context), &proc)
        guard procStatus == noErr, let proc else { return .failure(.failed) }
        resources.proc = proc

        // Reading starts here. `mutedWhenTapped` silences the app only from this point, and the
        // callback is already installed so the silenced audio is what we play back.
        guard AudioDeviceStart(aggregate, proc) == noErr else { return .failure(.failed) }

        let tap = ProcessVolumeTap(processObjects: objects, context: context, aggregate: aggregate, tap: tapID, proc: proc)
        resources.abandon()
        return .success(tap)
    }
}

// MARK: - Render state

/// Shared with the real-time callback. No references, so the callback never retains anything.
/// `targetBits`, `fault` and `rendered` are only touched through OSAtomic.
private struct TapContext {
    var targetBits: Int32
    var fault: Int32
    var rendered: Int32
    var current: Float
    var step: Float
    var inputChannels: Int32
    var outputChannels: Int32
    var inputInterleaved: Int32
    var outputInterleaved: Int32
}

private let targetOffset = MemoryLayout<TapContext>.offset(of: \TapContext.targetBits) ?? 0
private let faultOffset = MemoryLayout<TapContext>.offset(of: \TapContext.fault) ?? 4
private let renderedOffset = MemoryLayout<TapContext>.offset(of: \TapContext.rendered) ?? 8
private let currentOffset = MemoryLayout<TapContext>.offset(of: \TapContext.current) ?? 12
private let stepOffset = MemoryLayout<TapContext>.offset(of: \TapContext.step) ?? 16
private let inputChannelsOffset = MemoryLayout<TapContext>.offset(of: \TapContext.inputChannels) ?? 20
private let outputChannelsOffset = MemoryLayout<TapContext>.offset(of: \TapContext.outputChannels) ?? 24
private let inputInterleavedOffset = MemoryLayout<TapContext>.offset(of: \TapContext.inputInterleaved) ?? 28
private let outputInterleavedOffset = MemoryLayout<TapContext>.offset(of: \TapContext.outputInterleaved) ?? 32

/// Owns half-built Core Audio objects so a failed start cannot leave a tap muting an app.
@available(macOS 14.4, *)
private final class TapResources {
    var tap: AudioObjectID = 0
    var aggregate: AudioObjectID = 0
    var proc: AudioDeviceIOProcID?
    var context: UnsafeMutablePointer<TapContext>?

    func abandon() {
        tap = 0
        aggregate = 0
        proc = nil
        context = nil
    }

    func destroy() {
        if let proc, aggregate != 0 {
            AudioDeviceStop(aggregate, proc)
            AudioDeviceDestroyIOProcID(aggregate, proc)
        }
        if aggregate != 0 { AudioHardwareDestroyAggregateDevice(aggregate) }
        if tap != 0 { AudioHardwareDestroyProcessTap(tap) }
        context?.deinitialize(count: 1)
        context?.deallocate()
        abandon()
    }
}

// MARK: - Real-time callback

/// No allocation, no locks, no Swift objects. Gain moves at most to the new level over about 10 ms.
private let volumeTapIOProc: AudioDeviceIOProc = { _, _, inputData, _, outputData, _, clientData in
    guard let clientData else { return noErr }
    let context = clientData.assumingMemoryBound(to: TapContext.self)
    if renderTap(context, input: inputData, output: outputData) {
        _ = OSAtomicCompareAndSwap32Barrier(0, 1, int32Field(context, renderedOffset))
    }
    return noErr
}

private func renderTap(_ context: UnsafeMutablePointer<TapContext>,
                       input: UnsafePointer<AudioBufferList>,
                       output: UnsafeMutablePointer<AudioBufferList>) -> Bool {
    // Field pointers, not `pointee`: assigning one field of the struct would write the whole
    // value and race with the atomic gain word.
    let inList = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
    let outList = UnsafeMutableAudioBufferListPointer(output)
    let inChannels = Int(int32Field(context, inputChannelsOffset).pointee)
    let outChannels = Int(int32Field(context, outputChannelsOffset).pointee)
    let inInterleaved = int32Field(context, inputInterleavedOffset).pointee != 0
    let outInterleaved = int32Field(context, outputInterleavedOffset).pointee != 0

    // The HAL does not promise to zero the output. Fill it ourselves. Skip that when the
    // buffers alias, or the silence pass would wipe the input before we read it.
    let aliases = inList.count > 0 && outList.count > 0 && inList[0].mData == outList[0].mData
    if !aliases { silence(outList) }

    if inChannels <= 0 || outChannels <= 0 || inList.count == 0 || outList.count == 0 { return false }
    if (inInterleaved && inList.count < 1) || (!inInterleaved && inList.count < inChannels)
        || (outInterleaved && outList.count < 1) || (!outInterleaved && outList.count < outChannels) {
        _ = OSAtomicCompareAndSwap32Barrier(0, 1, int32Field(context, faultOffset))
        return false
    }

    let inFrames = frameCount(inList[0], channelsInBuffer: inInterleaved ? inChannels : 1)
    let outFrames = frameCount(outList[0], channelsInBuffer: outInterleaved ? outChannels : 1)
    if inFrames <= 0 || outFrames <= 0 { return false }

    let target = Float(bitPattern: UInt32(bitPattern: OSAtomicAdd32Barrier(0, int32Field(context, targetOffset))))
    let gainSlot = floatField(context, currentOffset)
    var gain = gainSlot.pointee
    let step = floatField(context, stepOffset).pointee
    let frames = outFrames
    var frame = 0
    while frame < frames {
        if gain < target {
            gain += step
            if gain > target { gain = target }
        } else if gain > target {
            gain -= step
            if gain < target { gain = target }
        }
        var channel = 0
        while channel < outChannels {
            let sample: Float
            if frame < inFrames && channel < inChannels {
                guard let read = readSample(inList, interleaved: inInterleaved, channels: inChannels, frame: frame, channel: channel) else {
                    gainSlot.pointee = gain
                    _ = OSAtomicCompareAndSwap32Barrier(0, 1, int32Field(context, faultOffset))
                    return false
                }
                sample = read * gain
            } else {
                sample = 0
            }
            guard write(sample, to: outList, interleaved: outInterleaved, channels: outChannels, frame: frame, channel: channel) else {
                gainSlot.pointee = gain
                _ = OSAtomicCompareAndSwap32Barrier(0, 1, int32Field(context, faultOffset))
                return false
            }
            channel += 1
        }
        frame += 1
    }
    gainSlot.pointee = gain
    return true
}

private func floatField(_ context: UnsafeMutablePointer<TapContext>, _ offset: Int) -> UnsafeMutablePointer<Float> {
    UnsafeMutableRawPointer(context).advanced(by: offset).assumingMemoryBound(to: Float.self)
}

private func silence(_ list: UnsafeMutableAudioBufferListPointer) {
    var index = 0
    while index < list.count {
        let buffer = list[index]
        if let data = buffer.mData, buffer.mDataByteSize > 0 {
            memset(data, 0, Int(buffer.mDataByteSize))
        }
        index += 1
    }
}

private func frameCount(_ buffer: AudioBuffer, channelsInBuffer: Int) -> Int {
    let stride = MemoryLayout<Float>.size * max(channelsInBuffer, 1)
    return Int(buffer.mDataByteSize) / stride
}

private func readSample(_ list: UnsafeMutableAudioBufferListPointer, interleaved: Bool, channels: Int,
                    frame: Int, channel: Int) -> Float? {
    if interleaved {
        let buffer = list[0]
        let index = frame * channels + channel
        let count = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
        guard let data = buffer.mData, index >= 0, index < count else { return nil }
        return data.assumingMemoryBound(to: Float.self)[index]
    }
    guard channel >= 0, channel < list.count else { return nil }
    let buffer = list[channel]
    let count = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
    guard let data = buffer.mData, frame >= 0, frame < count else { return nil }
    return data.assumingMemoryBound(to: Float.self)[frame]
}

private func write(_ value: Float, to list: UnsafeMutableAudioBufferListPointer, interleaved: Bool,
                   channels: Int, frame: Int, channel: Int) -> Bool {
    if interleaved {
        let buffer = list[0]
        let index = frame * channels + channel
        let count = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
        guard let data = buffer.mData, index >= 0, index < count else { return false }
        data.assumingMemoryBound(to: Float.self)[index] = value
        return true
    }
    guard channel >= 0, channel < list.count else { return false }
    let buffer = list[channel]
    let count = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
    guard let data = buffer.mData, frame >= 0, frame < count else { return false }
    data.assumingMemoryBound(to: Float.self)[frame] = value
    return true
}

private func int32Field(_ context: UnsafeMutablePointer<TapContext>, _ offset: Int) -> UnsafeMutablePointer<Int32> {
    UnsafeMutableRawPointer(context).advanced(by: offset).assumingMemoryBound(to: Int32.self)
}

// MARK: - Aggregate device

private struct OutputRoute {
    var uid: String
    var bluetooth: Bool
}

private func defaultOutputRoute() -> OutputRoute? {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var device = AudioDeviceID(0)
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    let system = AudioObjectID(kAudioObjectSystemObject)
    guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &device) == noErr, device != 0 else { return nil }

    var uidAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyDeviceUID,
        mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var uidValue: Unmanaged<CFString>?
    var uidSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    guard AudioObjectGetPropertyData(device, &uidAddress, 0, nil, &uidSize, &uidValue) == noErr,
          let uid = uidValue?.takeRetainedValue() as String?, !uid.isEmpty else { return nil }

    var transportAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyTransportType,
        mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var transport: UInt32 = 0
    var transportSize = UInt32(MemoryLayout<UInt32>.size)
    _ = AudioObjectGetPropertyData(device, &transportAddress, 0, nil, &transportSize, &transport)
    let bluetooth = transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE
    return OutputRoute(uid: uid, bluetooth: bluetooth)
}

@available(macOS 14.4, *)
private func readTapUID(_ tap: AudioObjectID) -> String? {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioTapPropertyUID,
        mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    guard AudioObjectHasProperty(tap, &address) else { return nil }
    var value: Unmanaged<CFString>?
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    guard AudioObjectGetPropertyData(tap, &address, 0, nil, &size, &value) == noErr else { return nil }
    return value?.takeRetainedValue() as String?
}

/// Private aggregate: the tap is the input, the current default output is what we play into.
/// `TapAutoStart` starts the tap when the device's IO starts, which is the read `mutedWhenTapped` waits for.
@available(macOS 14.4, *)
private func aggregateDictionary(outputUID: String, tapUID: String, drift: Bool, suppressHardwareInput: Bool) -> [String: Any] {
    var subdevice: [String: Any] = [
        kAudioSubDeviceUIDKey: outputUID,
        kAudioSubDeviceDriftCompensationKey: false,
    ]
    if suppressHardwareInput {
        // Keeps a headset microphone out of the callback so it isn't played back out the speakers.
        subdevice[kAudioSubDeviceInputChannelsKey] = [] as [NSNumber]
    }
    return [
        kAudioAggregateDeviceNameKey: "NotchBar Mixer",
        kAudioAggregateDeviceUIDKey: UUID().uuidString,
        kAudioAggregateDeviceMainSubDeviceKey: outputUID,
        kAudioAggregateDeviceClockDeviceKey: outputUID,
        kAudioAggregateDeviceIsPrivateKey: true,
        kAudioAggregateDeviceIsStackedKey: false,
        kAudioAggregateDeviceTapAutoStartKey: true,
        kAudioAggregateDeviceSubDeviceListKey: [subdevice],
        kAudioAggregateDeviceTapListKey: [[
            kAudioSubTapUIDKey: tapUID,
            kAudioSubTapDriftCompensationKey: drift,
        ]],
    ]
}

private func streamFormat(_ device: AudioObjectID, scope: AudioObjectPropertyScope) -> AudioStreamBasicDescription? {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyStreamFormat, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    var format = AudioStreamBasicDescription()
    var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
    guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &format) == noErr else { return nil }
    return format
}

private func isFloat32(_ format: AudioStreamBasicDescription) -> Bool {
    format.mFormatID == kAudioFormatLinearPCM && format.mBitsPerChannel == 32
        && (format.mFormatFlags & kAudioFormatFlagIsFloat) != 0
}

private func isInterleaved(_ format: AudioStreamBasicDescription) -> Bool {
    (format.mFormatFlags & kAudioFormatFlagIsNonInterleaved) == 0
}
