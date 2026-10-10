import CoreAudio
import Foundation

/// Plays one app's sound at its own volume, on the device chosen for it. A process tap takes
/// the app's sound away from where it was going (macOS asks once for the System Audio Recording
/// permission), and a private device made of the tap and the chosen output plays it again,
/// scaled by the gain.
@available(macOS 14.4, *)
final class TapEngine {
    enum Failure: Error {
        case tap(OSStatus)
        case device(OSStatus)
        case start(OSStatus)
    }

    let objects: [AudioObjectID]
    let outputUID: String

    /// Read on the audio thread; one aligned float, written whole.
    private let gainValue = UnsafeMutablePointer<Float>.allocate(capacity: 1)
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var deviceID = AudioObjectID(kAudioObjectUnknown)
    private var ioProc: AudioDeviceIOProcID?
    /// Written by the audio thread, read for the logs only.
    private let stats = UnsafeMutablePointer<TapRender.Stats>.allocate(capacity: 1)
    private var tapFormat = AudioStreamBasicDescription()

    var gain: Float {
        get { gainValue.pointee }
        set { gainValue.pointee = min(max(newValue, 0), 2) }
    }

    init(objects: [AudioObjectID], outputUID: String, gain: Float) throws {
        self.objects = objects
        self.outputUID = outputUID
        gainValue.initialize(to: min(max(gain, 0), 2))
        stats.initialize(to: TapRender.Stats())

        let description = CATapDescription(stereoMixdownOfProcesses: objects)
        description.muteBehavior = .mutedWhenTapped
        description.isPrivate = true
        var status = AudioHardwareCreateProcessTap(description, &tapID)
        guard status == noErr, tapID != kAudioObjectUnknown else {
            stop()
            throw Failure.tap(status)
        }

        let device: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Estris Volume Mixer",
            kAudioAggregateDeviceUIDKey: AudioSystem.mixerUIDPrefix + UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapUIDKey: description.uuid.uuidString,
                kAudioSubTapDriftCompensationKey: true,
            ]],
            kAudioAggregateDeviceTapAutoStartKey: true,
        ]
        status = AudioHardwareCreateAggregateDevice(device as CFDictionary, &deviceID)
        guard status == noErr, deviceID != kAudioObjectUnknown else {
            stop()
            throw Failure.device(status)
        }

        var format = AudioStreamBasicDescription()
        let tapChannels = AudioSystem.read(tapID, kAudioTapPropertyFormat, into: &format) && format.mChannelsPerFrame > 0
            ? Int(format.mChannelsPerFrame) : 2
        tapFormat = format
        let gain = gainValue
        let stats = stats
        status = AudioDeviceCreateIOProcIDWithBlock(&ioProc, deviceID, nil) { _, input, _, output, _ in
            TapRender.render(input: input, output: output, tapChannels: tapChannels, gain: gain.pointee, stats: stats)
        }
        guard status == noErr else {
            ioProc = nil
            stop()
            throw Failure.start(status)
        }
        status = AudioDeviceStart(deviceID, ioProc)
        guard status == noErr else {
            stop()
            throw Failure.start(status)
        }
    }

    /// Gives the app its sound back at once; the rest is taken down off the main thread, as
    /// it can wait on the audio system.
    func stop() {
        let tapID = tapID
        let deviceID = deviceID
        let ioProc = ioProc
        guard tapID != kAudioObjectUnknown || deviceID != kAudioObjectUnknown else { return }
        self.tapID = AudioObjectID(kAudioObjectUnknown)
        self.deviceID = AudioObjectID(kAudioObjectUnknown)
        self.ioProc = nil
        if let ioProc, deviceID != kAudioObjectUnknown {
            AudioDeviceStop(deviceID, ioProc)
        }
        Self.teardown.async {
            if let ioProc, deviceID != kAudioObjectUnknown {
                AudioDeviceDestroyIOProcID(deviceID, ioProc)
            }
            if deviceID != kAudioObjectUnknown {
                AudioHardwareDestroyAggregateDevice(deviceID)
            }
            if tapID != kAudioObjectUnknown {
                AudioHardwareDestroyProcessTap(tapID)
            }
        }
    }

    private static let teardown = DispatchQueue(label: "Estris.VolumeMixer.teardown", qos: .utility)

    /// For the logs: the tap's format, the device's rate, and what the audio thread has seen.
    var diagnostics: String {
        var rate: Float64 = 0
        if deviceID != kAudioObjectUnknown {
            AudioSystem.read(deviceID, kAudioDevicePropertyNominalSampleRate, into: &rate)
        }
        let seen = stats.pointee
        return "tap \(Int(tapFormat.mSampleRate)) Hz \(tapFormat.mChannelsPerFrame) ch, device \(Int(rate)) Hz; "
            + "\(seen.cycles) render cycles, \(seen.tapCycles) with the tap's buffer, "
            + "inputs \(seen.inputs) (channels \(seen.inputChannels)), outputs \(seen.outputs) (channels \(seen.outputChannels)), "
            + "loudest sample \(String(format: "%.3f", seen.peak))"
    }

    deinit {
        stop()
        // Freed after the teardown queued above, once nothing can read them.
        let gain = gainValue
        let stats = stats
        Self.teardown.async {
            gain.deallocate()
            stats.deallocate()
        }
    }
}

/// Copies the tapped sound to the output, scaled. Runs on the audio thread: no allocation and
/// no locks.
enum TapRender {
    /// What the audio thread has seen, for the logs. Channel counts are written digit by digit,
    /// one digit per buffer ("12" is a 1-channel buffer then a 2-channel one).
    struct Stats {
        var cycles = 0
        var tapCycles = 0
        var inputs = 0
        var outputs = 0
        var inputChannels = 0
        var outputChannels = 0
        var peak: Float = 0
    }

    static func render(
        input: UnsafePointer<AudioBufferList>,
        output: UnsafeMutablePointer<AudioBufferList>,
        tapChannels: Int,
        gain: Float,
        stats: UnsafeMutablePointer<Stats>
    ) {
        let inputs = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        let outputs = UnsafeMutableAudioBufferListPointer(output)

        // The tap comes after any input of the output device itself, such as a headset's
        // microphone: the last buffer with the tap's channel count.
        var source: AudioBuffer?
        for index in stride(from: inputs.count - 1, through: 0, by: -1)
        where inputs[index].mData != nil && Int(inputs[index].mNumberChannels) == tapChannels {
            source = inputs[index]
            break
        }
        if source == nil, inputs.count == 1, inputs[0].mData != nil, inputs[0].mNumberChannels > 0 {
            source = inputs[0]
        }

        let sourceChannels = Int(source?.mNumberChannels ?? 0)
        let samples = source?.mData?.assumingMemoryBound(to: Float.self)
        let sourceFrames = sourceChannels > 0 ? Int(source?.mDataByteSize ?? 0) / (4 * sourceChannels) : 0

        stats.pointee.cycles += 1
        if source != nil { stats.pointee.tapCycles += 1 }
        stats.pointee.inputs = inputs.count
        stats.pointee.outputs = outputs.count
        stats.pointee.inputChannels = inputs.reduce(0) { $0 * 10 + Int($1.mNumberChannels) }
        stats.pointee.outputChannels = outputs.reduce(0) { $0 * 10 + Int($1.mNumberChannels) }
        if let samples {
            for index in 0..<(sourceFrames * sourceChannels) {
                stats.pointee.peak = max(stats.pointee.peak, abs(samples[index]))
            }
        }

        var firstChannel = 0
        for buffer in outputs {
            let channels = Int(buffer.mNumberChannels)
            guard channels > 0, let destination = buffer.mData?.assumingMemoryBound(to: Float.self) else {
                firstChannel += channels
                continue
            }
            let frames = Int(buffer.mDataByteSize) / (4 * channels)
            for frame in 0..<frames {
                for channel in 0..<channels {
                    var value: Float = 0
                    let outputChannel = firstChannel + channel
                    // A mono source plays on both sides; extra output channels stay silent.
                    let sourceChannel = outputChannel < sourceChannels ? outputChannel : (sourceChannels == 1 && outputChannel == 1 ? 0 : -1)
                    if let samples, frame < sourceFrames, sourceChannel >= 0 {
                        value = min(max(samples[frame * sourceChannels + sourceChannel] * gain, -1), 1)
                    }
                    destination[frame * channels + channel] = value
                }
            }
            firstChannel += channels
        }
    }
}
