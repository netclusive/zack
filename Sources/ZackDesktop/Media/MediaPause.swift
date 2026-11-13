import Foundation
import Synchronization
import os

/// Pauses a playing player once a dictation's pill appears and resumes it when the recording ends; only a pause of its
/// own is resumed. Calls return at once and run in order on a queue of their own, so play never overtakes pause and
/// neither the pill nor the release waits for Core Audio.
public final class MediaPause: Sendable {
    /// Spotify only. Chrome's audio helper also outputs for tabs that are not the current playback, so a pause reached
    /// a paused Spotify and the play started it.
    public static let players: Set<String> = ["com.spotify.client"]

    private let commands: any PlaybackCommands
    private let outputs: any AudioOutputs
    /// Shortest time from a pause of its own to the play: Spotify ignores a play within about 250 ms of a pause and
    /// stays paused, as after a hold just past the pill.
    private let minimumPause: Duration
    /// Wait after the play in `resumeNow`: a command sent right before the process exits does not arrive.
    private let exitGrace: Duration
    private let queue = DispatchQueue(label: "com.netclusive.zack.media", qos: .userInitiated)
    /// When the running dictation paused playback, nil if it did not; changed on `queue` only.
    private let pausedAt = Mutex<ContinuousClock.Instant?>(nil)
    /// Set by `resumeNow`: the app quits, so no later pill may pause again; changed on `queue` only.
    private let closed = Mutex(false)
    private let logger = Logger(subsystem: Signposts.subsystem, category: "media")

    public init(
        commands: any PlaybackCommands, outputs: any AudioOutputs, minimumPause: Duration = .milliseconds(600),
        exitGrace: Duration = .milliseconds(300)
    ) {
        self.commands = commands
        self.outputs = outputs
        self.minimumPause = minimumPause
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
    /// Pills after this pause nothing.
    public func resumeNow() {
        let played = queue.sync {
            closed.withLock { $0 = true }
            return resume()
        }
        guard played else { return }
        Self.sleep(exitGrace)
    }

    /// Waits until the queued work is done.
    func drain() {
        queue.sync {}
    }

    /// Checks the commands last, so MediaRemote still loads only once a listed player plays.
    private func pauseIfPlaying() {
        guard !closed.withLock({ $0 }), pausedAt.withLock({ $0 }) == nil,
            !outputs.playingBundleIDs().isDisjoint(with: Self.players),
            commands.isAvailable
        else { return }
        commands.pause()
        pausedAt.withLock { $0 = .now }
        logger.info("paused")
    }

    /// True if it sent a play. Waits on the queue, not on the caller, until the pause has settled.
    private func resume() -> Bool {
        guard let since = pausedAt.withLock({ $0 }) else { return false }
        let remaining = minimumPause - since.duration(to: .now)
        if remaining > .zero { Self.sleep(remaining) }
        commands.play()
        pausedAt.withLock { $0 = nil }
        logger.info("resumed")
        return true
    }

    private static func sleep(_ duration: Duration) {
        let (seconds, attoseconds) = duration.components
        Thread.sleep(forTimeInterval: Double(seconds) + Double(attoseconds) / 1e18)
    }
}
