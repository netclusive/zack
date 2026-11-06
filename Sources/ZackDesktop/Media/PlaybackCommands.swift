/// Pause and play for the app macOS treats as the current playback.
public protocol PlaybackCommands: Sendable {
    /// False if the commands cannot reach any player, so pause and play would do nothing.
    var isAvailable: Bool { get }
    func pause()
    func play()
}
