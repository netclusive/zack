import Foundation
import Synchronization
import os

/// Pauses a playing player once a dictation's pill appears and resumes it when the recording ends; only a pause of its
/// own is resumed. Calls return at once and run in order on a queue of their own, so play never overtakes pause and
/// neither the pill nor the release waits for Core Audio.
public final class MediaPause: Sendable {
    /// Tested players only: Spotify, and Chrome's audio helper for YouTube.
    public static let players: Set<String> = ["com.spotify.client", "com.google.Chrome.helper"]

    private let commands: any PlaybackCommands
    private let outputs: any AudioOutputs
    /// Wait after the play in `resumeNow`: a command sent right before the process exits does not arrive.
    private let exitGrace: Duration
    private let queue = DispatchQueue(label: "com.netclusive.zack.media", qos: .userInitiated)
    /// The running dictation paused playback; changed on `queue` only.
    private let paused = Mutex(false)
    private let logger = Logger(subsystem: Signposts.subsystem, category: "media")

    public init(commands: any PlaybackCommands, outputs: any AudioOutputs, exitGrace: Duration = .milliseconds(300)) {
        self.commands = commands
        self.outputs = outputs
        self.exitGrace = exitGrace
    }

    /// The pill appeared; `enabled` is the setting at this moment.
    public func shown(enabled: Bool) {
        guard enabled else { return }
        queue.async { self.pauseIfPlaying() }
    }

    /// The recording ended, whichever way.
    public func ended() {
        queue.async { _ = self.resume() }
    }

    /// The app quits: resumes a pause of its own before returning, then gives the command time to leave the process.
    public func resumeNow() {
        guard queue.sync(execute: { resume() }) else { return }
        let (seconds, attoseconds) = exitGrace.components
        Thread.sleep(forTimeInterval: Double(seconds) + Double(attoseconds) / 1e18)
    }

    /// Waits until the queued work is done.
    func drain() {
        queue.sync {}
    }

    private func pauseIfPlaying() {
        guard !paused.withLock({ $0 }), !outputs.playingBundleIDs().isDisjoint(with: Self.players) else { return }
        commands.pause()
        paused.withLock { $0 = true }
        logger.info("paused")
    }

    /// True if it sent a play.
    private func resume() -> Bool {
        guard paused.withLock({ $0 }) else { return false }
        commands.play()
        paused.withLock { $0 = false }
        logger.info("resumed")
        return true
    }
}
