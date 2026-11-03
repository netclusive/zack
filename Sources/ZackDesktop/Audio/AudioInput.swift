/// What an audio source reports besides audio.
public enum AudioInputEvent: Equatable, Sendable {
    /// Same device, new format (e.g. a Bluetooth headset switching profiles): the capture restarts the input.
    case formatChanged
    /// The engine's target (the chosen device or the default) changed or went away: the recording ends.
    case deviceLost
}

/// Source of 16 kHz mono audio chunks, so capture logic can be tested without a microphone.
/// `start` and `stop` are called one after the other, never concurrently (`MicrophoneCapture` ensures this).
public protocol AudioInput: AnyObject, Sendable {
    /// Starts delivering chunks on a background thread; events may arrive on any thread.
    func start(onChunk: @escaping @Sendable ([Float]) -> Void, onEvent: @escaping @Sendable (AudioInputEvent) -> Void)
        throws
    func stop()
    /// Starts the same recording again after a format change. A source that cannot guarantee it is still
    /// the same device throws; the capture then ends the recording. Not concurrent with `start` or `stop`.
    func restart(onChunk: @escaping @Sendable ([Float]) -> Void, onEvent: @escaping @Sendable (AudioInputEvent) -> Void)
        throws
}

extension AudioInput {
    /// For sources with a single device, such as the test fakes: stop and start, without a device check.
    /// `EngineAudioInput` implements its own, which throws when the device may have changed.
    public func restart(
        onChunk: @escaping @Sendable ([Float]) -> Void, onEvent: @escaping @Sendable (AudioInputEvent) -> Void
    ) throws {
        stop()
        try start(onChunk: onChunk, onEvent: onEvent)
    }
}
