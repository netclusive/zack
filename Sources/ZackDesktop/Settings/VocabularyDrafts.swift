import Foundation
import Observation
import ZackCore

/// Unsaved edits of the "Wörterbuch" table: each cell edits a draft, saving writes it through the editor, Esc drops it.
/// A draft belongs to the line and the entry it started from: when the document changes and that pair is gone, the
/// draft goes too, so it is never saved over a reloaded file.
@MainActor @Observable
public final class VocabularyDrafts {
    public enum RowID: Hashable, Sendable {
        case line(Int)
        case new
    }

    public enum Selection: Equatable, Sendable {
        case saved(line: Int, entry: VocabularyEntry)
        case new
    }

    /// Unsaved edits of one saved line; a nil field shows the saved value.
    struct LineDraft {
        let base: VocabularyEntry
        var spelling: String?
        var heardAs: String?

        var entry: VocabularyEntry {
            VocabularyEntry(spelling: spelling ?? base.spelling, heardAs: heardAs ?? base.heardAs)
        }

        var isEmpty: Bool { spelling == nil && heardAs == nil }

        /// Compared as written, so a trailing space alone writes nothing.
        var changesFile: Bool { VocabularyFormat.line(for: entry) != VocabularyFormat.line(for: base) }

        func value(_ field: EntryField) -> String? { field == .spelling ? spelling : heardAs }

        mutating func set(_ field: EntryField, _ value: String?) {
            if field == .spelling { spelling = value } else { heardAs = value }
        }
    }

    public let editor: FileEditor<VocabularyFormat>
    private var drafts: [Int: LineDraft] = [:]
    /// The row "+" added, which reaches the file once it is valid.
    public private(set) var newEntry: VocabularyEntry?
    /// Rows whose last save was refused; their problems show until fixed, saved or dropped.
    private var refused: Set<RowID> = []
    public private(set) var selection: Selection?
    /// Set when a reload drops typed text; the editor's own notice covers refused writes.
    public private(set) var lostEdit: String?

    public init(editor: FileEditor<VocabularyFormat>) {
        self.editor = editor
    }

    // MARK: Fields

    /// What a cell shows: its draft, else `saved`, the entry its row shows.
    public func value(_ field: EntryField, row: RowID, saved: VocabularyEntry?) -> String {
        switch row {
        case .new: newEntry.map { Self.value(field, of: $0) } ?? ""
        case .line(let line): drafts[line]?.value(field) ?? saved.map { Self.value(field, of: $0) } ?? ""
        }
    }

    public func set(_ field: EntryField, to text: String, row: RowID, saved: VocabularyEntry?) {
        switch row {
        case .new:
            // A late write after the row was dropped must not bring it back.
            guard let entry = newEntry else { return }
            newEntry = Self.setting(field, to: text, in: entry)
        case .line(let line):
            // A field that showed an entry no longer at this line (reload, removal) writes nothing.
            guard let saved, isCurrent(line, saved) else { return }
            var draft = drafts[line] ?? LineDraft(base: saved)
            guard draft.base == saved else { return }
            draft.set(field, text)
            drafts[line] = draft
        }
    }

    // MARK: Problems

    /// Problems of the refused rows, recomputed from the drafts, so a fix clears them while typing.
    public var issues: [EntryIssue] {
        drafts.keys.sorted().flatMap { issues(for: .line($0)) } + issues(for: .new)
    }

    public func issues(for row: RowID) -> [EntryIssue] {
        guard refused.contains(row) else { return [] }
        switch row {
        case .new: return newEntry.map { VocabularyFormat.issues(in: $0) } ?? []
        case .line(let line): return drafts[line].map { VocabularyFormat.issues(in: $0.entry) } ?? []
        }
    }

    // MARK: Actions

    /// "+": a blank new row, selected.
    public func add() {
        if newEntry == nil { newEntry = VocabularyEntry(spelling: "") }
        selection = .new
    }

    public func removeSelected() {
        switch selection {
        case nil: return
        case .new: dropNewEntry()
        case .saved(let line, let entry):
            selection = nil
            editor.remove(line: line, expecting: entry)
            // A refused removal reloaded the file; stale drafts go when the document changes.
            guard editor.notice == nil, editor.state == .loaded else { return }
            lostEdit = nil
            // Later lines moved up by one; their drafts move along.
            func moved(_ key: Int) -> Int? { key == line ? nil : key > line ? key - 1 : key }
            drafts = Dictionary(
                uniqueKeysWithValues: drafts.compactMap { element -> (Int, LineDraft)? in
                    moved(element.key).map { ($0, element.value) }
                })
            refused = Set(
                refused.compactMap { row -> RowID? in
                    guard case .line(let key) = row else { return row }
                    return moved(key).map { .line($0) }
                })
        }
    }

    public func select(_ row: RowID?) {
        switch row {
        case nil: selection = nil
        case .new: selection = newEntry == nil ? nil : .new
        case .line(let line):
            selection = editor.document.items.first { $0.line == line }
                .map { .saved(line: $0.line, entry: $0.entry) }
        }
    }

    /// Esc: the field shows the saved value again.
    public func discard(_ field: EntryField, row: RowID) {
        switch row {
        case .new:
            newEntry = newEntry.map { Self.setting(field, to: "", in: $0) }
        case .line(let line):
            drafts[line]?.set(field, nil)
            if drafts[line]?.isEmpty == true {
                drafts[line] = nil
                refused.remove(row)
            }
        }
    }

    /// Leaving the row saves it; the new row is dropped instead while blank.
    public func save(_ row: RowID, leavingRow: Bool) {
        switch row {
        case .line(let line): saveLine(line)
        case .new: saveNewEntry(discardIfEmpty: leavingRow)
        }
    }

    /// Closing the window or leaving the pane saves what is valid; the rest is dropped with the view.
    public func saveAll() {
        for line in drafts.keys.sorted() { saveLine(line) }
        saveNewEntry(discardIfEmpty: true)
    }

    /// The window losing key status saves like a focus change: what is valid is written, an invalid draft stays
    /// marked, and the new row stays even when blank.
    public func savePending() {
        for line in drafts.keys.sorted() { saveLine(line) }
        saveNewEntry(discardIfEmpty: false)
    }

    /// After any change of the document: drafts and the selection whose line no longer holds their entry go. Returns
    /// their lines, whose fields now show another entry.
    @discardableResult
    public func dropStale() -> Set<Int> {
        var staleLines = Set(drafts.filter { !isCurrent($0.key, $0.value.base) }.keys)
        let lostTyping = staleLines.contains { drafts[$0]?.changesFile == true }
        for line in staleLines {
            drafts[line] = nil
            refused.remove(.line(line))
        }
        if case .saved(let line, let entry) = selection, !isCurrent(line, entry) {
            selection = nil
            staleLines.insert(line)
        }
        if lostTyping, editor.notice == nil { lostEdit = EditorText.changedOnDisk }
        return staleLines
    }

    // MARK: Saving

    private func saveLine(_ line: Int) {
        guard let draft = drafts[line] else { return }
        guard draft.changesFile else {
            drafts[line] = nil
            refused.remove(.line(line))
            return
        }
        guard editor.update(line: line, from: draft.base, to: draft.entry).isEmpty else {
            refused.insert(.line(line))
            return
        }
        refused.remove(.line(line))
        // A refused write reloaded the file and set the notice. A failed write keeps the draft for another try; after
        // a conflict the notice says it is lost.
        guard editor.notice == nil, editor.state == .loaded else {
            if editor.notice == EditorText.changedOnDisk { drafts[line] = nil }
            return
        }
        drafts[line] = nil
        guard let saved = editor.document.items.first(where: { $0.line == line }) else { return }
        lostEdit = nil
        if case .saved(line, _) = selection { selection = .saved(line: line, entry: saved.entry) }
    }

    private func saveNewEntry(discardIfEmpty: Bool) {
        guard let entry = newEntry else { return }
        if Self.isBlank(entry.spelling), Self.isBlank(entry.heardAs ?? "") {
            if discardIfEmpty { dropNewEntry() }
            return
        }
        guard editor.add(entry).isEmpty else {
            refused.insert(.new)
            return
        }
        refused.remove(.new)
        // A failed write keeps the row for another try; after a conflict the notice says it is lost.
        guard editor.notice == nil, editor.state == .loaded else {
            if editor.notice == EditorText.changedOnDisk { dropNewEntry() }
            return
        }
        dropNewEntry()
        guard let saved = editor.document.items.last else { return }
        lostEdit = nil
        selection = .saved(line: saved.line, entry: saved.entry)
    }

    private func dropNewEntry() {
        newEntry = nil
        refused.remove(.new)
        if selection == .new { selection = nil }
    }

    private func isCurrent(_ line: Int, _ entry: VocabularyEntry) -> Bool {
        editor.document.items.contains { $0.line == line && $0.entry == entry }
    }

    private static func value(_ field: EntryField, of entry: VocabularyEntry) -> String {
        field == .spelling ? entry.spelling : entry.heardAs ?? ""
    }

    private static func setting(_ field: EntryField, to text: String, in entry: VocabularyEntry) -> VocabularyEntry {
        var entry = entry
        if field == .spelling { entry.spelling = text } else { entry.heardAs = text }
        return entry
    }

    private static func isBlank(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
