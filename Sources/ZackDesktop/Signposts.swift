import Synchronization
import os

/// Latency marks for `scripts/latency.sh`: interval names, a cleaner flag and the audio length, never content.
///
/// A mark that measures nothing is discarded: its interval is dropped without an end. The script pairs each begin
/// with the end of the same signpost ID, so it never counts a dropped interval, and no later end can close it.
public final class Signposts: Sendable {
    public static let subsystem = "com.netclusive.zack"
    private let signposter: OSSignposter
    private let pill = Mutex<OSSignpostIntervalState?>(nil)
    private let insert = Mutex<OSSignpostIntervalState?>(nil)
    private let insertsEnded = Mutex(0)
    private let microphoneStarts = Mutex((open: 0, ended: 0))

    public convenience init() {
        self.init(signposter: OSSignposter(subsystem: Self.subsystem, category: "latency"))
    }

    /// Tests pass `.disabled`, so nothing reaches the log the script reads.
    init(signposter: OSSignposter) {
        self.signposter = signposter
    }

    /// Key down.
    public func beginPill() {
        let state = signposter.beginInterval("pill", id: signposter.makeSignpostID())
        pill.withLock { $0 = state }
    }

    /// Pill on screen.
    public func endPill() {
        guard let state = pill.withLock({ $0.take() }) else { return }
        signposter.endInterval("pill", state)
    }

    /// The pill will not appear for the last key down, or appears without one ("Erneut versuchen").
    public func discardPill() {
        pill.withLock { $0 = nil }
    }

    /// Key released.
    public func beginInsert() {
        let state = signposter.beginInterval("insert", id: signposter.makeSignpostID())
        insert.withLock { $0 = state }
    }

    /// Cmd+V sent or text on the clipboard.
    public func endInsert(usedCleaner: Bool, audioSeconds: Double) {
        guard let state = insert.withLock({ $0.take() }) else { return }
        insertsEnded.withLock { $0 += 1 }
        let cleaner = usedCleaner ? 1 : 0
        let seconds = Int(audioSeconds.rounded())
        signposter.endInterval(
            "insert", state, "cleaner=\(cleaner, privacy: .public) audio=\(seconds, privacy: .public)")
    }

    /// The key release inserts nothing (too short, silent, failed), or an insert follows without a release.
    public func discardInsert() {
        insert.withLock { $0 = nil }
    }

    /// Runs the blocking start of the audio input in a "micstart" interval, without content, so a hand check can
    /// read how long a cold start blocks. A failed start ends the interval too.
    func measureMicrophoneStart<T>(_ start: () throws -> T) rethrows -> T {
        let state = signposter.beginInterval("micstart", id: signposter.makeSignpostID())
        microphoneStarts.withLock { $0.open += 1 }
        defer {
            signposter.endInterval("micstart", state)
            microphoneStarts.withLock { $0 = (open: $0.open - 1, ended: $0.ended + 1) }
        }
        return try start()
    }

    /// Open marks, ended inserts and microphone starts; for tests.
    var isPillOpen: Bool { pill.withLock { $0 != nil } }
    var isInsertOpen: Bool { insert.withLock { $0 != nil } }
    var endedInserts: Int { insertsEnded.withLock { $0 } }
    var openMicrophoneStarts: Int { microphoneStarts.withLock { $0.open } }
    var endedMicrophoneStarts: Int { microphoneStarts.withLock { $0.ended } }
}
