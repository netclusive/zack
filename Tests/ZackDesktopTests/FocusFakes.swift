import CoreFoundation
import Synchronization
import Testing

@testable import ZackDesktop

/// Stands in for the Accessibility reader; snapshots and text come from the test.
final class FakeFocusSource: FocusSource {
    private struct State {
        var queue: [FocusSnapshot] = [.unknown]
        var texts: [TextRange: String] = [:]
        var lastElement: FocusElement?
        var selections: [TextRange] = []
        var selectSucceeds = true
        var reads = 0
        var holdsAll = false
        var holdsNext = false
        var holdsNextSelect = false
        var heldSelect: CheckedContinuation<Void, Never>?
        var waiting: [CheckedContinuation<FocusSnapshot?, Never>] = []
    }

    private let state = Mutex(State())

    var selectSucceeds: Bool {
        get { state.withLock { $0.selectSucceeds } }
        set { state.withLock { $0.selectSucceeds = newValue } }
    }
    var selections: [TextRange] { state.withLock { $0.selections } }
    var reads: Int { state.withLock { $0.reads } }
    /// Reads currently waiting for a release.
    var heldReads: Int { state.withLock { $0.waiting.count } }

    /// Replaces the queue; each read takes the next entry, the last one repeats.
    func queue(_ snapshots: FocusSnapshot...) {
        state.withLock { $0.queue = snapshots.isEmpty ? [.unknown] : snapshots }
    }

    func setText(_ text: String, at range: TextRange) {
        state.withLock { $0.texts[range] = text }
    }

    /// All following reads wait until `releaseReads()`.
    func holdReads() {
        state.withLock { $0.holdsAll = true }
    }

    func releaseReads() {
        let waiting = state.withLock { state -> [CheckedContinuation<FocusSnapshot?, Never>] in
            state.holdsAll = false
            defer { state.waiting = [] }
            return state.waiting
        }
        for continuation in waiting { continuation.resume(returning: nil) }
    }

    /// Only the next read waits; `releaseHeldRead(returning:)` lets it go with exactly that snapshot.
    func holdNextRead() {
        state.withLock { $0.holdsNext = true }
    }

    func releaseHeldRead(returning snapshot: FocusSnapshot) {
        let continuation = state.withLock { state -> CheckedContinuation<FocusSnapshot?, Never>? in
            state.holdsNext = false
            return state.waiting.isEmpty ? nil : state.waiting.removeFirst()
        }
        continuation?.resume(returning: snapshot)
    }

    func read(text: Bool) async -> FocusSnapshot {
        // Deciding to wait and joining the waiting reads happen under one lock, so a release in between is not lost.
        let released = await withCheckedContinuation { (continuation: CheckedContinuation<FocusSnapshot?, Never>) in
            let waits = state.withLock { state -> Bool in
                state.reads += 1
                let waits = state.holdsNext || state.holdsAll
                state.holdsNext = false
                if waits { state.waiting.append(continuation) }
                return waits
            }
            if !waits { continuation.resume(returning: nil) }
        }
        var snapshot =
            released ?? state.withLock { state in state.queue.count > 1 ? state.queue.removeFirst() : state.queue[0] }
        if !text { snapshot.textBeforeCursor = nil }
        state.withLock { $0.lastElement = snapshot.element }
        return snapshot
    }

    func text(in range: TextRange, of element: FocusElement) async -> String? {
        state.withLock { state in
            guard let last = state.lastElement, last == element else { return nil }
            return state.texts[range]
        }
    }

    /// Selects currently waiting for `releaseSelect()` (0 or 1).
    var heldSelects: Int { state.withLock { $0.heldSelect == nil ? 0 : 1 } }

    /// Only the next select waits; it records its range and returns once `releaseSelect()` runs.
    func holdNextSelect() {
        state.withLock { $0.holdsNextSelect = true }
    }

    func releaseSelect() {
        state.withLock { state -> CheckedContinuation<Void, Never>? in
            defer { state.heldSelect = nil }
            return state.heldSelect
        }?.resume()
    }

    func select(_ range: TextRange, in element: FocusElement) async -> Bool {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let waits = state.withLock { state -> Bool in
                let waits = state.holdsNextSelect
                state.holdsNextSelect = false
                if waits { state.heldSelect = continuation }
                return waits
            }
            if !waits { continuation.resume() }
        }
        return state.withLock { state in
            state.selections.append(range)
            return state.selectSucceeds
        }
    }
}

struct FakeFocusSourceTests {
    let field = FocusElement(pid: 1, reference: "f" as CFString)

    @Test func queueRepeatsTheLastEntryAndTextFalseDropsTheText() async {
        let source = FakeFocusSource()
        source.queue(
            FocusSnapshot(element: field, textBeforeCursor: "a"), FocusSnapshot(element: field, textBeforeCursor: "b"))
        #expect(await source.read(text: true).textBeforeCursor == "a")
        #expect(await source.read(text: false).textBeforeCursor == nil)
        #expect(await source.read(text: true).textBeforeCursor == "b")
        #expect(source.reads == 3)
    }

    @Test func heldReadWaitsAndReturnsTheGivenSnapshot() async {
        let source = FakeFocusSource()
        source.holdNextRead()
        let result = Mutex<String?>(nil)
        Task {
            result.withLock { $0 = nil }
            let s = await source.read(text: true)
            result.withLock { $0 = s.textBeforeCursor }
        }
        #expect(await eventually { source.heldReads == 1 })
        source.releaseHeldRead(returning: FocusSnapshot(element: field, textBeforeCursor: "held"))
        #expect(await eventually { result.withLock { $0 } == "held" })
        #expect(source.heldReads == 0)
    }

    @Test func heldReadsReturnTheQueuedSnapshotAfterRelease() async {
        let source = FakeFocusSource()
        source.queue(FocusSnapshot(element: field, textBeforeCursor: "queued"))
        source.holdReads()
        let result = Mutex<String?>(nil)
        Task {
            let s = await source.read(text: true)
            result.withLock { $0 = s.textBeforeCursor }
        }
        #expect(await eventually { source.heldReads == 1 })
        #expect(result.withLock { $0 } == nil)
        source.releaseReads()
        #expect(await eventually { result.withLock { $0 } == "queued" })
        #expect(source.heldReads == 0)
        // Released for good: the next read does not wait.
        #expect(await source.read(text: true).textBeforeCursor == "queued")
    }

    @Test func textIsOnlyKnownForTheLastReadElement() async {
        let source = FakeFocusSource()
        let range = TextRange(location: 0, length: 2)
        source.setText("Hi", at: range)
        source.queue(FocusSnapshot(element: field))
        #expect(await source.text(in: range, of: field) == nil)
        _ = await source.read(text: false)
        #expect(await source.text(in: range, of: field) == "Hi")
        #expect(await source.select(range, in: field))
        #expect(source.selections == [range])
    }
}
