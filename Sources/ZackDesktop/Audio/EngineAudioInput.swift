@preconcurrency import AVFoundation
import CoreAudio
import ZackCore
import os

/// An input device through `AVAudioEngine`, converted to 16 kHz mono Float32: the device `device` names before each
/// start, or the system default if the unit does not take it. The audio tap runs on a background thread. `start` and
/// `stop` come one after the other from `MicrophoneCapture`; the lock guards the state the configuration-change
/// handler and the loss watch touch and the selection result, which any thread may read.
public final class EngineAudioInput: AudioInput, @unchecked Sendable {
    private static let logger = Logger(subsystem: "com.netclusive.zack", category: "audio")
    private let lock = NSLock()
    /// Asked before every start; nil when there is no input device.
    private let device: @Sendable () -> AudioObjectID?
    private var engine = AVAudioEngine()
    /// The engine stays on the device it started with, so another device needs a new engine. Nil before the first
    /// start: the initial engine creates its input only when first touched, on whatever is the default by then.
    private var engineDevice: AudioObjectID?
    /// Set after a configuration change; the next start builds a new engine.
    private var stale = false
    /// The requested device could not be set; the engine records from the system default.
    private var failedSelection = false
    private var observer: (any NSObjectProtocol)?
    /// Reports when the device the engine started on goes away; replaced by every start, cancelled by `stop`.
    private var lossWatch: DeviceLossWatch?
    /// Runs the loss watch's device listener: neither the capture nor the bench serves the main queue.
    private let watchQueue = DispatchQueue(label: "com.netclusive.zack.audio.device")

    public init(device: @escaping @Sendable () -> AudioObjectID? = { AudioDevices.defaultInputID() }) {
        self.device = device
    }

    /// Whether the last start could not set the requested device and records from the system default instead.
    public var selectionFailed: Bool { lock.withLock { failedSelection } }

    public func start(
        onChunk: @escaping @Sendable ([Float]) -> Void, onEvent: @escaping @Sendable (AudioInputEvent) -> Void
    ) throws {
        try start(requested: device(), keepFallback: false, restart: false, onChunk: onChunk, onEvent: onEvent)
    }

    /// `keepFallback` keeps a failed selection marked: a restart stays on the default the engine fell back to.
    /// `restart` refuses an engine that is not on `requested`, the device the recording ran on, instead of falling
    /// back to the default.
    private func start(
        requested: AudioObjectID?, keepFallback: Bool, restart: Bool,
        onChunk: @escaping @Sendable ([Float]) -> Void, onEvent: @escaping @Sendable (AudioInputEvent) -> Void
    ) throws {
        // A start without a stop must not leave the old observer or loss watch behind.
        stopWatching()
        let (engine, startedOn, failed) = engine(for: requested, keepFallback: keepFallback)
        if restart,
            !Self.restartKeepsDevice(
                startedOn: requested, endedOn: startedOn, selectionFailed: failed, wasFallback: keepFallback)
        {
            stop()
            throw ZackError.audioFormat
        }
        let input = engine.inputNode
        input.removeTap(onBus: 0)
        // The hardware format: a chosen device can run at another rate than the engine, and the tap then gets
        // nothing with the input node's output format.
        let inputFormat = input.inputFormat(forBus: 0)
        guard
            let target = AVAudioFormat(
                commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false),
            let converter = AVAudioConverter(from: inputFormat, to: target)
        else { throw ZackError.audioFormat }
        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { buffer, _ in
            if let chunk = Self.convert(buffer, converter: converter, target: target) { onChunk(chunk) }
        }
        // The engine stops itself when the device changes its format, or goes away while the engine follows the
        // default. A set device that goes away posts nothing; `watchLoss` covers that.
        let observer = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
        ) { [weak self, weak engine] _ in
            guard let self, let engine else { return }
            // Setting an input device makes the engine post exactly one configuration change shortly after
            // `start`, while it keeps running on that device. Treating it as a real change restarted the
            // recording on a new engine, which posted again: an endless loop that delivered no audio.
            let format = engine.inputNode.inputFormat(forBus: 0)
            if Self.isSpuriousChange(
                running: engine.isRunning, held: engine.inputNode.auAudioUnit.deviceID, startedOn: startedOn,
                alive: startedOn.map(AudioDevices.isAlive) ?? false, tapSampleRate: inputFormat.sampleRate,
                tapChannels: inputFormat.channelCount, currentSampleRate: format.sampleRate,
                currentChannels: format.channelCount)
            {
                return
            }
            markStale()
            onEvent(
                Self.classify(
                    startedOn: startedOn, isAlive: startedOn.map(AudioDevices.isAlive) ?? false,
                    current: currentTarget()))
        }
        lock.withLock { self.observer = observer }
        engine.prepare()
        do {
            // Not under the lock: starting can take long and may already post a configuration change.
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            stopWatching()
            throw error
        }
        if let startedOn { watchLoss(of: startedOn, onEvent: onEvent) }
    }

    /// Refuses when the engine's device is no longer the target, or when the new engine does not get that device
    /// again, so a restart never switches the microphone silently; otherwise starts again on that same device.
    public func restart(
        onChunk: @escaping @Sendable ([Float]) -> Void, onEvent: @escaping @Sendable (AudioInputEvent) -> Void
    ) throws {
        let (startedOn, failed) = lock.withLock { (engineDevice, failedSelection) }
        let current = Self.target(
            requested: device(), selectionFailed: failed, defaultID: AudioDevices.defaultInputID())
        guard Self.canRestart(startedOn: startedOn, current: current) else {
            stop()
            throw ZackError.audioFormat
        }
        stop()
        try start(requested: startedOn, keepFallback: failed, restart: true, onChunk: onChunk, onEvent: onEvent)
    }

    /// A configuration change that left everything as it was: the engine still runs, its input unit is still on the
    /// device it started on, that device lives, and the hardware format equals the one the tap was installed with.
    static func isSpuriousChange(
        running: Bool, held: AudioObjectID, startedOn: AudioObjectID?, alive: Bool,
        tapSampleRate: Double, tapChannels: AVAudioChannelCount,
        currentSampleRate: Double, currentChannels: AVAudioChannelCount
    ) -> Bool {
        running && startedOn != nil && held == startedOn && alive && tapSampleRate == currentSampleRate
            && tapChannels == currentChannels
    }

    static func canRestart(startedOn: AudioObjectID?, current: AudioObjectID?) -> Bool {
        startedOn != nil && startedOn == current
    }

    /// The device the engine should be on: the requested one, or the system default after a failed selection.
    static func target(requested: AudioObjectID?, selectionFailed: Bool, defaultID: AudioObjectID?) -> AudioObjectID? {
        selectionFailed ? defaultID : requested
    }

    /// Whether a restart may continue on the engine it built: only on the device it ran on before, and with that
    /// device set, unless the engine already ran on the default it had fallen back to (`wasFallback`).
    static func restartKeepsDevice(
        startedOn: AudioObjectID?, endedOn: AudioObjectID?, selectionFailed: Bool, wasFallback: Bool
    ) -> Bool {
        startedOn != nil && endedOn == startedOn && (!selectionFailed || wasFallback)
    }

    /// The unit may accept a device without an error and still stay on another one.
    static func selectionHeld(requested: AudioObjectID, actual: AudioObjectID) -> Bool {
        requested == actual
    }

    public func stop() {
        stopWatching()
        let engine = lock.withLock { self.engine }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }

    /// Only the same, still living device with a new format may continue. Core Audio can update the default
    /// input after the engine posts its change, so the target alone must not decide: a restart would
    /// silently continue on another microphone.
    static func classify(startedOn: AudioObjectID?, isAlive: Bool, current: AudioObjectID?) -> AudioInputEvent {
        guard let startedOn, isAlive, current == startedOn else { return .deviceLost }
        return .formatChanged
    }

    /// The target now, for comparison with the device the engine started on.
    private func currentTarget() -> AudioObjectID? {
        Self.target(requested: device(), selectionFailed: selectionFailed, defaultID: AudioDevices.defaultInputID())
    }

    /// The engine for `requested`: the current one if it already runs on that device, else a new one. Also
    /// returns the device the engine records from and whether setting `requested` failed this time.
    private func engine(
        for requested: AudioObjectID?, keepFallback: Bool
    ) -> (AVAudioEngine, AudioObjectID?, failed: Bool) {
        let current = lock.withLock { () -> AVAudioEngine? in
            guard requested == engineDevice, !stale else { return nil }
            // It records from the requested device already.
            failedSelection = keepFallback
            return engine
        }
        if let current { return (current, requested, false) }
        // Not under the lock: setting the device talks to Core Audio.
        let made = Self.makeEngine(on: requested)
        // An engine must never be released while the lock is held: tearing it down waits on its internal queue, whose
        // configuration-change handler takes this lock. The old engine is returned and dropped after the unlock.
        let previous = lock.withLock { () -> AVAudioEngine in
            let old = engine
            engine = made.engine
            engineDevice = made.device
            failedSelection = made.failed || keepFallback
            stale = false
            return old
        }
        withExtendedLifetime(previous) {}
        return (made.engine, made.device, made.failed)
    }

    /// A new engine on `requested`, set before anything reads the input format. If the unit refuses the device or
    /// stays on another one, a fresh engine on the system default, marked as failed.
    private static func makeEngine(
        on requested: AudioObjectID?
    ) -> (engine: AVAudioEngine, device: AudioObjectID?, failed: Bool) {
        let engine = AVAudioEngine()
        guard let requested else { return (engine, nil, false) }
        let unit = engine.inputNode.auAudioUnit
        // The log names no device, only what failed and the error code.
        do {
            try unit.setDeviceID(requested)
            if selectionHeld(requested: requested, actual: unit.deviceID) { return (engine, requested, false) }
            logger.error("input device not held by the unit")
        } catch {
            logger.error("input device not set, code \((error as NSError).code, privacy: .public)")
        }
        return (AVAudioEngine(), AudioDevices.defaultInputID(), true)
    }

    private func markStale() {
        lock.withLock { stale = true }
    }

    /// An engine with a set device posts no configuration change when that device is unplugged: it records on from
    /// another device at another rate. The device itself tells, so its loss ends the recording as a change would.
    private func watchLoss(of device: AudioObjectID, onEvent: @escaping @Sendable (AudioInputEvent) -> Void) {
        let queue = watchQueue
        let onLoss: @Sendable () -> Void = { [weak self] in
            // The log names no device.
            Self.logger.notice("input device went away")
            self?.markStale()
            onEvent(.deviceLost)
        }
        // Not under the lock: listening talks to Core Audio, and a device already gone reports at once.
        let watch = DeviceLossWatch(
            device: device, listen: { AudioDevices.observeAlive($0, queue: queue, $1) },
            isAlive: { AudioDevices.isAlive($0) }, onLoss: onLoss)
        lock.withLock { lossWatch = watch }
    }

    /// Removes the configuration-change observer and cancels the loss watch. Both are released outside the lock:
    /// removing the Core Audio listener may wait for a running handler, which takes the lock.
    private func stopWatching() {
        let (observer, watch) = lock.withLock {
            defer {
                self.observer = nil
                lossWatch = nil
            }
            return (self.observer, lossWatch)
        }
        if let observer { NotificationCenter.default.removeObserver(observer) }
        watch?.cancel()
    }

    private static func convert(
        _ buffer: AVAudioPCMBuffer, converter: AVAudioConverter, target: AVAudioFormat
    ) -> [Float]? {
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * target.sampleRate / buffer.format.sampleRate) + 1
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return nil }
        var delivered = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if delivered {
                status.pointee = .noDataNow
                return nil
            }
            delivered = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, let channel = output.floatChannelData?[0] else { return nil }
        return Array(UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
    }
}
