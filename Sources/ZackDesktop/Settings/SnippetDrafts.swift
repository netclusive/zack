import Foundation
import Observation
import ZackCore

/// The chosen snippet of the "Textbausteine" pane, edited as a draft and written through the editor. A draft belongs
/// to the line and the entry it started from: when the document changes and that pair is gone, the draft goes too.
@MainActor @Observable
public final class SnippetDrafts {
    public enum RowID: Hashable, Sendable {
        case line(Int)
        case new
    }

    public struct Anchor: Equatable, Sendable {
        public let line: Int
        public let entry: Snippet
    }

    /// The chosen snippet as typed; `anchor` is nil until a new snippet is saved.
    public struct Draft: Equatable, Sendable {
        /// Stays the same across saves of this snippet; a different snippet gets a new draft and new fields.
        public let id = UUID()
        public var anchor: Anchor?
        public var name: String
        public var text: String

        var entry: Snippet { Snippet(name: name, text: text) }

        /// Compared as written, so a trailing space alone writes nothing.
        var changesFile: Bool {
            guard let anchor else { return true }
            return SnippetFormat.line(for: entry) != SnippetFormat.line(for: anchor.entry)
        }
    }

    public let editor: FileEditor<SnippetFormat>
    /// The chosen snippet; nil when none is chosen.
    public private(set) var draft: Draft?
    /// The last save was refused; the problems show until fixed, saved or dropped.
    private var refused = false
    /// Set when a reload drops typed text; the editor's own notice covers refused writes.
    public private(set) var lostEdit: String?
    /// The saved snippet whose removal waits for confirmation.
    public private(set) var pendingRemoval: Anchor?

    public init(editor: FileEditor<SnippetFormat>) {
        self.editor = editor
    }

    public var currentRow: RowID? {
        guard let draft else { return nil }
        return draft.anchor.map { .line($0.line) } ?? .new
    }

    /// Recomputed from the draft, so a fix clears them while typing.
    public var issues: [EntryIssue] {
        guard refused, let draft else { return [] }
        return SnippetFormat.issues(in: draft.entry)
    }

    // MARK: Fields

    /// Typing into `field`; a late write from fields that showed another snippet (`owner`) changes nothing.
    public func set(_ field: EntryField, to value: String, owner: UUID?) {
        guard let owner, draft?.id == owner else { return }
        if field == .name { draft?.name = value } else { draft?.text = value }
    }

    /// Esc: the field shows the saved value again.
    public func discard(_ field: EntryField) {
        // Read before writing: `draft?.name = draft?…` would overlap two accesses to the property.
        let saved = draft?.anchor?.entry
        if field == .name { draft?.name = saved?.name ?? "" } else { draft?.text = saved?.text ?? "" }
    }

    // MARK: Actions

    /// A snippet with problems or a failed write stays chosen until it is saved or its field is reset with Esc.
    public func choose(_ row: RowID?) {
        guard row != currentRow, save(leaving: true) else { return }
        refused = false
        guard case .line(let line) = row, let item = editor.document.items.first(where: { $0.line == line }) else {
            // The new row is only chosen by "+".
            dropDraft()
            return
        }
        draft = Draft(anchor: Anchor(line: item.line, entry: item.entry), name: item.entry.name, text: item.entry.text)
    }

    /// "+": a blank new snippet, unless the chosen one cannot be saved; true when it was started.
    public func add() -> Bool {
        guard save(leaving: true) else { return false }
        draft = Draft(anchor: nil, name: "", text: "")
        refused = false
        return true
    }

    public func requestRemoval() {
        guard let current = draft else { return }
        guard current.anchor != nil else {
            // Never saved: nothing to delete in the file.
            dropDraft()
            return
        }
        // Save pending text first, so the question names the saved snippet and the removal matches the file.
        save(leaving: false)
        pendingRemoval = draft?.anchor
    }

    public func cancelRemoval() {
        pendingRemoval = nil
    }

    public func remove(_ anchor: Anchor) {
        pendingRemoval = nil
        editor.remove(line: anchor.line, expecting: anchor.entry)
        dropDraft()
        if editor.notice == nil { lostEdit = nil }
    }

    /// Writes the chosen snippet if it changed; false while it has problems or its write failed. A new snippet waits
    /// for both fields unless the user leaves it; leaving it blank drops it.
    @discardableResult
    public func save(leaving: Bool) -> Bool {
        guard var current = draft, current.changesFile else {
            refused = false
            return true
        }
        if let anchor = current.anchor {
            guard editor.update(line: anchor.line, from: anchor.entry, to: current.entry).isEmpty else {
                refused = true
                return false
            }
        } else {
            let blankName = Self.isBlank(current.name)
            let blankText = Self.isBlank(current.text)
            if blankName, blankText {
                if leaving { dropDraft() }
                return true
            }
            if !leaving, blankName || blankText { return true }
            guard editor.add(current.entry).isEmpty else {
                refused = true
                return false
            }
        }
        refused = false
        // A failed write keeps the snippet chosen with its draft for another try.
        if let notice = editor.notice, notice != EditorText.changedOnDisk, editor.state == .loaded { return false }
        let line = current.anchor?.line ?? editor.document.items.last?.line
        guard editor.notice == nil, editor.state == .loaded,
            let saved = editor.document.items.first(where: { $0.line == line })
        else {
            // Refused: the file was reloaded and the notice says the edit is lost.
            dropDraft()
            return true
        }
        lostEdit = nil
        // Keep the text as typed (the file drops a trailing space) on the saved entry.
        current.anchor = Anchor(line: saved.line, entry: saved.entry)
        draft = current
        return true
    }

    /// After any change of the document: a draft whose line no longer holds its entry goes.
    public func dropStale() {
        guard let current = draft, let anchor = current.anchor,
            !editor.document.items.contains(where: { $0.line == anchor.line && $0.entry == anchor.entry })
        else { return }
        if current.changesFile, editor.notice == nil { lostEdit = EditorText.changedOnDisk }
        dropDraft()
    }

    /// No snippet chosen; the view ends the editing of its fields.
    private func dropDraft() {
        draft = nil
        refused = false
    }

    private static func isBlank(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
