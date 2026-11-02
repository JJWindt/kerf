import AudioToolbox
import CoreAudio
import KerfKit
import SwiftUI

/// The waveform's bar heights from the sound itself: a Core Audio tap on the app that plays
/// (Spotify, Music, podcasts). Only levels come out; nothing is recorded or kept.
/// macOS asks once for "System Audio Recording".
@Observable
final class AudioLevels {
    static let shared = AudioLevels()

    /// The bars on screen. The audio thread moves them itself, so neither SwiftUI nor the main
    /// thread does anything 30 times a second.
    @ObservationIgnored let board = BarBoard()
    /// The heights about once a second, for bars that appear.
    @ObservationIgnored private(set) var levels = LevelMeter.Levels()
    /// True once real sound came through; until then the waveform uses the SF Symbol.
    private(set) var isLive = false
    @ObservationIgnored private var engine: TapEngine?
    @ObservationIgnored private var listening: Int32?
    @ObservationIgnored private var silentSince: Date?
    @ObservationIgnored private var global = false
    @ObservationIgnored private var paused = false
    @ObservationIgnored private var wanted: (processID: Int32?, playing: Bool) = (nil, false)
    /// Off in the lab: a process that exits with a tap running can leave the audio daemon spinning.
    @ObservationIgnored var tapsAllowed = true

    /// Listens while something plays, to that app; stops when it pauses.
    func follow(processID: Int32?, playing: Bool) {
        wanted = (processID, playing)
        guard playing, !paused, tapsAllowed else {
            stop()
            return
        }
        guard engine == nil || listening != processID else { return }
        start(processID: processID, global: false)
    }

    /// Nobody sees the waveform (every island hidden): no tap then.
    func setPaused(_ paused: Bool) {
        guard paused != self.paused else { return }
        self.paused = paused
        follow(processID: wanted.processID, playing: wanted.playing)
    }

    private func start(processID: Int32?, global: Bool) {
        engine?.stop()
        listening = processID
        self.global = global
        silentSince = .now
        let board = board
        let engine = TapEngine(processID: global ? nil : processID, draw: { board.draw($0) }) { levels in
            Task { @MainActor in AudioLevels.shared.update(levels) }
        }
        do {
            try engine.start()
            self.engine = engine
        } catch {
            engine.stop()
            self.engine = nil
            if isLive { isLive = false }
        }
    }

    func stop() {
        engine?.stop()
        engine = nil
        listening = nil
        levels = LevelMeter.Levels()
        if isLive { isLive = false }
        board.draw(levels)
    }

    /// Lab only.
    func preview(_ bars: [Float]) {
        var levels = LevelMeter.Levels()
        for (index, bar) in bars.prefix(LevelMeter.bars).enumerated() { levels[index] = bar }
        self.levels = levels
        if !isLive { isLive = true }
        board.draw(levels)
    }

    /// About once a second, and when sound starts or stops: the bars themselves don't come here.
    private func update(_ levels: LevelMeter.Levels) {
        guard engine != nil else { return }
        self.levels = levels
        if levels.max() > 0.03 {
            // Observed by the waveform: set it once, not 30 times a second.
            if !isLive { isLive = true }
            silentSince = nil
        } else if let since = silentSince, Date.now.timeIntervalSince(since) > 3, !global {
            // That process stayed silent: some apps play through a helper. Listen to everything else.
            start(processID: listening, global: true)
        } else if silentSince == nil {
            silentSince = .now
        }
    }
}

/// A private process tap plus an aggregate device to read it, as Apple's tapping API wants.
nonisolated final class TapEngine: @unchecked Sendable {
    enum Failure: Error {
        case status(OSStatus)
    }

    private let processID: Int32?
    /// On the audio thread, when the bars moved.
    private let draw: @Sendable (LevelMeter.Levels) -> Void
    /// On the audio thread, about once a second and when sound starts or stops.
    private let report: @Sendable (LevelMeter.Levels) -> Void
    private let queue = DispatchQueue(label: "nl.paulboerma.kerf.audiotap", qos: .userInteractive)
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private var meter = LevelMeter(sampleRate: 48_000)
    private var mono: [Float] = []
    private var labBuffer: [Float] = []
    private var drawn = LevelMeter.Levels(repeating: -1)
    private var lastDrawn: CFTimeInterval = 0
    private var lastReport: CFTimeInterval = 0
    private var reportedSound = false

    /// Lab only: replaces what the tap hears with a test signal, so the whole path runs and nobody
    /// hears a thing.
    nonisolated(unsafe) static var labSignal: LabSignal?
    nonisolated(unsafe) static var labCycles = 0

    init(processID: Int32?, draw: @escaping @Sendable (LevelMeter.Levels) -> Void, report: @escaping @Sendable (LevelMeter.Levels) -> Void) {
        self.processID = processID
        self.draw = draw
        self.report = report
    }

    private func check(_ status: OSStatus) throws {
        guard status == noErr else { throw Failure.status(status) }
    }

    func start() throws {
        let description: CATapDescription
        // Only the playing app's own sound, helpers included (some apps play through a helper
        // process): mixing every app on the Mac cost the audio daemon more.
        if let processID, case let objects = AudioProcess.objects(playingFor: processID), !objects.isEmpty {
            description = CATapDescription(stereoMixdownOfProcesses: objects)
        } else {
            description = CATapDescription(stereoGlobalTapButExcludeProcesses: Self.processObject(getpid()).map { [$0] } ?? [])
        }
        description.uuid = UUID()
        description.muteBehavior = .unmuted
        description.isPrivate = true
        description.name = "Kerf waveform"
        try check(AudioHardwareCreateProcessTap(description, &tapID))

        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyFormat, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        try check(AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &format))
        meter = LevelMeter(sampleRate: format.mSampleRate > 0 ? format.mSampleRate : 48_000)

        let output = try Self.defaultOutputUID()
        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Kerf Waveform",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: output,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: output]],
            // No drift compensation: the tap runs on the output's own clock, and resampling it
            // doubled what macOS's audio daemon spent on Kerf.
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapDriftCompensationKey: false, kAudioSubTapUIDKey: description.uuid.uuidString]],
        ]
        try check(AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateID))
        Self.setCycles(aggregateID, sampleRate: format.mSampleRate > 0 ? format.mSampleRate : 48_000)
        try check(AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, queue) { [weak self] _, input, _, _, _ in
            self?.consume(input)
        })
        try check(AudioDeviceStart(aggregateID, procID))
    }

    /// Runs on the tap's audio thread, 24 times a second: measures, moves the bars itself,
    /// and tells the main thread only about once a second. Nothing is allocated here.
    private func consume(_ input: UnsafePointer<AudioBufferList>) {
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        guard let first = buffers.first, let data = first.mData else { return }
        let channels = max(Int(first.mNumberChannels), 1)
        let count = Int(first.mDataByteSize) / MemoryLayout<Float>.size
        guard count >= channels else { return }
        let levels: LevelMeter.Levels
        if let signal = Self.labSignal {
            Self.labCycles += 1
            let frames = count / channels
            if labBuffer.count < frames { labBuffer = [Float](repeating: 0, count: frames) }
            levels = labBuffer.withUnsafeMutableBufferPointer { buffer in
                let part = UnsafeMutableBufferPointer(rebasing: buffer[0..<frames])
                signal.fill(part)
                return meter.process(UnsafeBufferPointer(part))
            }
        } else if buffers.count == 1 {
            levels = meter.process(interleaved: UnsafeBufferPointer(start: data.assumingMemoryBound(to: Float.self), count: count), channels: channels)
        } else {
            levels = mixedLevels(buffers, frames: count / channels)
        }
        // A little slack: each cycle may draw, whatever the timing jitter.
        let now = CACurrentMediaTime()
        let change = levels - drawn
        if now - lastDrawn >= 0.75 / Self.cyclesPerSecond, (change * change).max() > 0.000_016 {
            lastDrawn = now
            drawn = levels
            draw(levels)
        }
        let sound = levels.max() > 0.03
        if sound != reportedSound || now - lastReport >= 1 {
            reportedSound = sound
            lastReport = now
            report(levels)
        }
    }

    /// One buffer per channel: mixed into mono first.
    private func mixedLevels(_ buffers: UnsafeMutableAudioBufferListPointer, frames: Int) -> LevelMeter.Levels {
        if mono.count < frames { mono = [Float](repeating: 0, count: frames) }
        return mono.withUnsafeMutableBufferPointer { out in
            for index in 0..<frames { out[index] = 0 }
            for buffer in buffers {
                guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                let bufferChannels = max(Int(buffer.mNumberChannels), 1)
                let scale = 1 / Float(bufferChannels * buffers.count)
                for frame in 0..<min(frames, Int(buffer.mDataByteSize) / MemoryLayout<Float>.size / bufferChannels) {
                    var sum: Float = 0
                    for channel in 0..<bufferChannels { sum += data[frame * bufferChannels + channel] }
                    out[frame] += sum * scale
                }
            }
            return meter.process(UnsafeBufferPointer(rebasing: out[0..<frames]))
        }
    }

    /// Bar updates a second. Bars only redraw when one moves two pixels, about 22 times a second
    /// with music, so 24 cycles lose nothing you'd see.
    static let cyclesPerSecond = 24.0

    /// One IO cycle per bar update instead of one every 10 ms: Kerf and the audio daemon wake a
    /// quarter as often.
    private static func setCycles(_ device: AudioObjectID, sampleRate: Double) {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyBufferFrameSizeRange, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var range = AudioValueRange()
        var size = UInt32(MemoryLayout<AudioValueRange>.size)
        var frames = UInt32(sampleRate / cyclesPerSecond)
        if AudioObjectGetPropertyData(device, &address, 0, nil, &size, &range) == noErr, range.mMaximum > 0 {
            frames = UInt32(min(max(Double(frames), range.mMinimum), range.mMaximum))
        }
        address.mSelector = kAudioDevicePropertyBufferFrameSize
        AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &frames)
    }

    func stop() {
        if aggregateID != kAudioObjectUnknown {
            AudioDeviceStop(aggregateID, procID)
            if let procID { AudioDeviceDestroyIOProcID(aggregateID, procID) }
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = AudioObjectID(kAudioObjectUnknown)
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
    }

    private static func processObject(_ pid: Int32) -> AudioObjectID? {
        var pid = pid
        var object = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
                                                 mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, UInt32(MemoryLayout<pid_t>.size), &pid, &size, &object)
        return status == noErr && object != kAudioObjectUnknown ? object : nil
    }

    static func defaultOutputUID() throws -> String {
        var device = AudioDeviceID()
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        guard status == noErr else { throw Failure.status(status) }
        var uid: Unmanaged<CFString>?
        size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        address.mSelector = kAudioDevicePropertyDeviceUID
        status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &uid)
        guard status == noErr, let uid else { throw Failure.status(status) }
        return uid.takeRetainedValue() as String
    }
}
