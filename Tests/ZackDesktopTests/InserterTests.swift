import Foundation
import Testing

@testable import ZackDesktop

@MainActor
struct InserterTests {
    let clipboard = FakeClipboard()
    let keystrokes: FakeKeystrokes

    init() {
        keystrokes = FakeKeystrokes(clipboard: clipboard)
    }

    func makeInserter(
        accessibility: Bool = true, timing: InsertTiming = InsertTiming(),
        sleep: @escaping @Sendable (Duration) async -> Void = { _ in }
    ) -> Inserter {
        Inserter(
            clipboard: clipboard, keystrokes: keystrokes, canPostKeystrokes: { accessibility },
            frontmostBundleID: { "com.example.editor" }, timing: timing, sleep: sleep)
    }

    @Test func pastesAndRestoresThePreviousClipboard() async {
        clipboard.externalCopy("vorher")
        let inserter = makeInserter()
        #expect(await inserter.insert("Hallo Welt.") == .pasted)
        #expect(keystrokes.pasted == ["Hallo Welt."])
        await inserter.waitForRestore()
        #expect(clipboard.contents == FakeClipboard.text("vorher"))
    }

    @Test func dictationIsMarkedTransient() async {
        _ = await makeInserter().insert("Hallo")
        #expect(clipboard.lastWriteTransient == true)
    }

    @Test func clipboardChangedMeanwhileIsNotOverwritten() async {
        clipboard.externalCopy("vorher")
        let clipboard = clipboard
        let inserter = makeInserter(sleep: { _ in await MainActor.run { clipboard.externalCopy("neu kopiert") } })
        _ = await inserter.insert("Hallo")
        await inserter.waitForRestore()
        #expect(clipboard.contents == FakeClipboard.text("neu kopiert"))
    }

    @Test func withoutAccessibilityTheTextStaysOnTheClipboard() async {
        clipboard.externalCopy("vorher")
        let inserter = makeInserter(accessibility: false)
        #expect(await inserter.insert("Hallo") == .clipboardOnly)
        await inserter.waitForRestore()
        #expect(keystrokes.pasted.isEmpty)
        #expect(clipboard.contents == FakeClipboard.text("Hallo"))
        // Nothing to paste, so the clipboard is not read either.
        #expect(clipboard.snapshotCalls == 0)
    }

    @Test func deniedClipboardAccessSkipsSavingAndClearsTheDictation() async {
        clipboard.externalCopy("vorher")
        clipboard.access = .alwaysDeny
        let inserter = makeInserter()
        #expect(await inserter.insert("Hallo") == .pasted)
        #expect(keystrokes.pasted == ["Hallo"])
        await inserter.waitForRestore()
        #expect(clipboard.snapshotCalls == 0)
        // Without a snapshot the dictation must not linger.
        #expect(clipboard.contents == ClipboardSnapshot(items: []))
    }

    @Test func deniedClipboardAccessLeavesANewCopyAlone() async {
        clipboard.access = .alwaysDeny
        let inserter = makeInserter(sleep: { _ in await MainActor.run { clipboard.externalCopy("neu kopiert") } })
        _ = await inserter.insert("Hallo")
        await inserter.waitForRestore()
        #expect(clipboard.contents == FakeClipboard.text("neu kopiert"))
    }

    @Test func restoreWaitsThePerAppDelay() async {
        let waited = WaitLog()
        let timing = InsertTiming(overrides: ["com.example.editor": .milliseconds(600)])
        let inserter = makeInserter(timing: timing, sleep: { await waited.append($0) })
        _ = await inserter.insert("Hallo")
        await inserter.waitForRestore()
        #expect(await waited.values == [.milliseconds(600)])
        #expect(InsertTiming().restoreDelay(for: "com.example.other") == .milliseconds(250))
    }

    @Test func quickSecondDictationRestoresTheOriginalClipboard() async {
        clipboard.externalCopy("vorher")
        let gate = Gate()
        let inserter = makeInserter(sleep: { _ in await gate.wait() })
        _ = await inserter.insert("Erstes")
        _ = await inserter.insert("Zweites")
        await gate.open()
        await inserter.waitForRestore()
        #expect(clipboard.contents == FakeClipboard.text("vorher"))
        // The first dictation's pending restore was cancelled: one restore only, of the original snapshot.
        #expect(clipboard.restored == [FakeClipboard.text("vorher")])
    }

    @Test func aSupersededRestoreDoesNotDisturbTheNewerOne() async {
        clipboard.externalCopy("vorher")
        let gates = GateSequence()
        let inserter = makeInserter(sleep: { _ in await gates.next().wait() })
        _ = await inserter.insert("Erstes")
        for _ in 0..<50 { await Task.yield() }
        _ = await inserter.insert("Zweites")
        for _ in 0..<50 { await Task.yield() }
        // The first restore wakes up while the second is still waiting. It was cancelled, so it must
        // leave the second one's snapshot in place for the third dictation.
        await gates.open(0)
        for _ in 0..<50 { await Task.yield() }
        _ = await inserter.insert("Drittes")
        for _ in 0..<50 { await Task.yield() }
        await gates.openAll()
        await inserter.waitForRestore()
        for _ in 0..<50 { await Task.yield() }
        #expect(clipboard.contents == FakeClipboard.text("vorher"))
        #expect(clipboard.restored == [FakeClipboard.text("vorher")])
    }

    @Test func concealedClipboardIsClearedNotRestored() async {
        // A password manager entry as SystemClipboard.snapshot() records it: the type only, no data.
        clipboard.contents = ClipboardSnapshot(items: [
            .init(entries: [.init(type: Inserter.concealedType, data: Data())])
        ])
        let inserter = makeInserter()
        _ = await inserter.insert("Diktat")
        #expect(keystrokes.pasted == ["Diktat"])
        await inserter.waitForRestore()
        #expect(clipboard.contents == ClipboardSnapshot(items: []))
        #expect(clipboard.text == nil)
    }

    @Test func concealedClipboardChangedMeanwhileIsNotTouched() async {
        clipboard.contents = ClipboardSnapshot(items: [
            .init(entries: [.init(type: Inserter.concealedType, data: Data())])
        ])
        let inserter = makeInserter(sleep: { _ in await MainActor.run { clipboard.externalCopy("neu kopiert") } })
        _ = await inserter.insert("Diktat")
        await inserter.waitForRestore()
        #expect(clipboard.contents == FakeClipboard.text("neu kopiert"))
    }

    @Test func quickSecondDictationKeepsTheConcealedSnapshot() async {
        clipboard.contents = ClipboardSnapshot(items: [
            .init(entries: [.init(type: Inserter.concealedType, data: Data())])
        ])
        let gate = Gate()
        let inserter = makeInserter(sleep: { _ in await gate.wait() })
        _ = await inserter.insert("Erstes")
        _ = await inserter.insert("Zweites")
        await gate.open()
        await inserter.waitForRestore()
        #expect(clipboard.contents == ClipboardSnapshot(items: []))
    }

    @Test func copyIsANormalClipboardEntry() {
        makeInserter().copy("Letztes Diktat")
        #expect(clipboard.lastWriteTransient == false)
        #expect(clipboard.contents == FakeClipboard.text("Letztes Diktat"))
    }
}

actor WaitLog {
    private(set) var values: [Duration] = []

    func append(_ value: Duration) {
        values.append(value)
    }
}

/// Holds sleepers until the test opens it.
actor Gate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        for waiter in waiters { waiter.resume() }
        waiters = []
    }
}

/// Hands each sleeper its own gate, in call order.
actor GateSequence {
    private var gates: [Gate] = []
    private var served = 0

    func next() -> Gate {
        if served == gates.count { gates.append(Gate()) }
        defer { served += 1 }
        return gates[served]
    }

    func open(_ index: Int) async {
        if index == gates.count { gates.append(Gate()) }
        await gates[index].open()
    }

    func openAll() async {
        for gate in gates { await gate.open() }
    }
}
