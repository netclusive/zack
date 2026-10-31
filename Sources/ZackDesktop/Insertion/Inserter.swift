import Foundation

public enum InsertOutcome: Equatable, Sendable {
    /// Cmd+V was sent; the previous clipboard comes back after the restore delay.
    case pasted
    /// No Accessibility permission: the text waits on the clipboard.
    case clipboardOnly
}

/// Restore delay after Cmd+V, per app where needed.
public struct InsertTiming: Sendable {
    public var defaultDelay: Duration
    /// Bundle ID to delay, for apps that read the clipboard late.
    public var overrides: [String: Duration]

    public init(defaultDelay: Duration = .milliseconds(250), overrides: [String: Duration] = [:]) {
        self.defaultDelay = defaultDelay
        self.overrides = overrides
    }

    /// Measured values.
    public static let measured = InsertTiming()

    public func restoreDelay(for bundleID: String?) -> Duration {
        bundleID.flatMap { overrides[$0] } ?? defaultDelay
    }
}

/// Inserts through the clipboard: save it, set the text, send Cmd+V, restore it after a pause.
@MainActor
public final class Inserter {
    /// Marker from nspasteboard.org: clipboard managers leave such entries out of their history.
    public static let transientType = "org.nspasteboard.TransientType"
    /// Marker from nspasteboard.org: password managers flag secrets with it; Zack never keeps or restores them.
    public static let concealedType = "org.nspasteboard.ConcealedType"

    private struct PendingRestore {
        let snapshot: ClipboardSnapshot
        let task: Task<Void, Never>
    }

    private let clipboard: any Clipboard
    private let keystrokes: any KeystrokePoster
    private let canPostKeystrokes: @MainActor () -> Bool
    private let frontmostBundleID: @MainActor () -> String?
    private let timing: InsertTiming
    private let sleep: @Sendable (Duration) async -> Void
    private var pending: PendingRestore?

    public init(
        clipboard: any Clipboard, keystrokes: any KeystrokePoster,
        canPostKeystrokes: @escaping @MainActor () -> Bool, frontmostBundleID: @escaping @MainActor () -> String?,
        timing: InsertTiming = InsertTiming(),
        sleep: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }
    ) {
        self.clipboard = clipboard
        self.keystrokes = keystrokes
        self.canPostKeystrokes = canPostKeystrokes
        self.frontmostBundleID = frontmostBundleID
        self.timing = timing
        self.sleep = sleep
    }

    /// Returns once Cmd+V is sent; the clipboard is restored in the background.
    public func insert(_ text: String) async -> InsertOutcome {
        // Without Accessibility nothing is pasted, so the clipboard is neither read nor restored.
        guard canPostKeystrokes() else {
            clipboard.write(text, transient: true)
            return .clipboardOnly
        }
        let saved = takePendingSnapshot() ?? savedClipboard()
        let own = clipboard.write(text, transient: true)
        keystrokes.postPaste()
        let delay = timing.restoreDelay(for: frontmostBundleID())
        // Holds the inserter until the restore is done, also for a short-lived one (debug menu).
        let task = Task {
            await sleep(delay)
            guard !Task.isCancelled else { return }
            restore(saved, ifChangeCountIs: own)
        }
        pending = PendingRestore(snapshot: saved, task: task)
        return .pasted
    }

    /// Puts `text` on the clipboard as a normal entry ("Letztes Diktat kopieren").
    public func copy(_ text: String) {
        _ = takePendingSnapshot()
        clipboard.write(text, transient: false)
    }

    /// Waits for a scheduled restore; for tests.
    func waitForRestore() async {
        await pending?.task.value
    }

    /// A restore still pending holds the user's clipboard from before the previous dictation; it wins.
    private func takePendingSnapshot() -> ClipboardSnapshot? {
        guard let pending else { return nil }
        pending.task.cancel()
        self.pending = nil
        return pending.snapshot
    }

    /// Empty if reading is denied in System Settings: there is nothing to restore, so the restore clears the
    /// dictation instead of leaving it on the clipboard.
    private func savedClipboard() -> ClipboardSnapshot {
        clipboard.access == .alwaysDeny ? ClipboardSnapshot(items: []) : clipboard.snapshot()
    }

    private func restore(_ snapshot: ClipboardSnapshot, ifChangeCountIs own: Int) {
        pending = nil
        // Someone copied in the meantime: their content wins.
        guard clipboard.changeCount == own else { return }
        // A concealed entry (password) must not come back: clear, so neither it nor the dictation lingers.
        let concealed = snapshot.items.contains { $0.entries.contains { $0.type == Self.concealedType } }
        clipboard.restore(concealed ? ClipboardSnapshot(items: []) : snapshot)
    }
}
