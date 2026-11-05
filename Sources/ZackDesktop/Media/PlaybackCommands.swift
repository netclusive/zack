/// Pause and play for the app macOS treats as the current playback.
public protocol PlaybackCommands: Sendable {
    func pause()
    func play()
}
