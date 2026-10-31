import SwiftUI
import ZackCore
import ZackDesktop

/// "Wörterbuch": the entries of vocabulary.txt in a table, edited in place.
struct VocabularyPane: View {
    let editor: FileEditor<VocabularyFormat>?
    let openFile: () -> Void

    var body: some View {
        if let editor, editor.state == .loaded {
            VocabularyTable(editor: editor, openFile: openFile)
        } else {
            UnreadableFileNote(openFile: editor == nil ? nil : openFile)
        }
    }
}

/// Each cell edits a draft; Return or leaving the field saves it, Esc drops it. A draft belongs to the line and the
/// entry it started from: when the document changes and that pair is gone, the draft goes too, so it is never saved
/// over a reloaded file.
private struct VocabularyTable: View {
    typealias Item = EntryDocument<VocabularyFormat>.Item

    enum RowID: Hashable {
        case line(Int)
        case new
    }

    struct Row: Identifiable {
        let id: RowID
        /// Nil for the row "+" added, which reaches the file once it is valid.
        let item: Item?
    }

    struct FieldKey: Hashable {
        let row: RowID
        let field: EntryField
    }

    enum Selection: Equatable {
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

    let editor: FileEditor<VocabularyFormat>
    let openFile: () -> Void

    @State private var query = ""
    @State private var drafts: [Int: LineDraft] = [:]
    @State private var newEntry: VocabularyEntry?
    /// Rows whose last save was refused; their problems show until fixed, saved or dropped.
    @State private var refused: Set<RowID> = []
    @State private var selection: Selection?
    /// Set when a reload drops typed text; the editor's own notice covers refused writes.
    @State private var lostEdit: String?
    @FocusState private var focus: FieldKey?
    /// A field whose row now shows another entry; its editing was ended, and nothing it sends is saved.
    @State private var detachedFocus: FieldKey?

    var body: some View {
        let document = editor.document
        let duplicates = document.laterDuplicates
        ScrollViewReader { proxy in
            VStack(alignment: .leading, spacing: 12) {
                Text(
                    "Zack schreibt diese Begriffe genau so und gibt sie der Erkennung als Hinweis. Optional: wie die Erkennung sie falsch hört."
                )
                .fixedSize(horizontal: false, vertical: true)
                TextField("Suchen", text: $query)
                    .textFieldStyle(.roundedBorder)
                Table(rows(document), selection: tableSelection) {
                    TableColumn("Schreibweise") { row in
                        VStack(alignment: .leading, spacing: 2) {
                            cell(row, .spelling)
                            if let line = row.item?.line, duplicates.contains(line) {
                                Text(EditorText.duplicateSpelling)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    TableColumn("Erkannt als (optional)") { row in
                        cell(row, .heardAs)
                    }
                }
                let problems = problemMessages
                if !problems.isEmpty {
                    ProblemList(messages: problems)
                }
                EditorFooter(
                    onAdd: { add(scrollingWith: proxy) }, onRemove: remove, canRemove: selection != nil,
                    unreadableCount: document.unreadableCount, notice: editor.notice ?? lostEdit, openFile: openFile)
            }
            .padding(20)
        }
        .onChange(of: editor.document) { dropStaleDrafts() }
        .onChange(of: focus) { old, new in focusMoved(from: old, to: new) }
        .onDisappear(perform: saveAll)
        .onWindowWillClose(perform: saveAll)
    }

    // MARK: Rows and cells

    private func rows(_ document: EntryDocument<VocabularyFormat>) -> [Row] {
        var rows = document.items(matching: query).map { Row(id: .line($0.line), item: $0) }
        if newEntry != nil { rows.append(Row(id: .new, item: nil)) }
        return rows
    }

    private func cell(_ row: Row, _ field: EntryField) -> some View {
        let key = FieldKey(row: row.id, field: field)
        let label = Self.label(field)
        return TextField("", text: text(key, item: row.item), prompt: row.item == nil ? Text(label) : nil)
            .textFieldStyle(.plain)
            .accessibilityLabel(label)
            .focused($focus, equals: key)
            .onSubmit { save(row.id, leavingRow: true) }
            .onExitCommand { discard(key) }
            .overlay {
                if isFlagged(key) {
                    RoundedRectangle(cornerRadius: 3).stroke(Brand.problem)
                }
            }
    }

    private func text(_ key: FieldKey, item: Item?) -> Binding<String> {
        Binding(
            get: {
                switch key.row {
                case .new: newEntry.map { Self.value(key.field, of: $0) } ?? ""
                case .line(let line):
                    drafts[line]?.value(key.field) ?? item.map { Self.value(key.field, of: $0.entry) } ?? ""
                }
            },
            set: { text in
                switch key.row {
                case .new:
                    // A late write after the row was dropped must not bring it back.
                    guard let entry = newEntry else { return }
                    newEntry = Self.setting(key.field, to: text, in: entry)
                case .line(let line):
                    // A field that showed an entry no longer at this line (reload, removal) writes nothing.
                    guard key != detachedFocus, let item, isCurrent(line, item.entry) else { return }
                    var draft = drafts[line] ?? LineDraft(base: item.entry)
                    guard draft.base == item.entry else { return }
                    draft.set(key.field, text)
                    drafts[line] = draft
                }
            })
    }

    private var tableSelection: Binding<RowID?> {
        Binding(
            get: {
                switch selection {
                case .saved(let line, _): .line(line)
                case .new: .new
                case nil: nil
                }
            },
            set: { select($0) })
    }

    // MARK: Problems

    /// Problems of the refused rows, recomputed from the drafts, so a fix clears them while typing.
    private var problemMessages: [String] {
        let issues = drafts.keys.sorted().flatMap { issues(for: .line($0)) } + issues(for: .new)
        return ProblemList.messages(for: issues, label: Self.label)
    }

    private func issues(for row: RowID) -> [EntryIssue] {
        guard refused.contains(row) else { return [] }
        switch row {
        case .new: return newEntry.map { VocabularyFormat.issues(in: $0) } ?? []
        case .line(let line): return drafts[line].map { VocabularyFormat.issues(in: $0.entry) } ?? []
        }
    }

    private func isFlagged(_ key: FieldKey) -> Bool {
        issues(for: key.row).contains { $0.field == key.field }
    }

    // MARK: Actions

    private func add(scrollingWith proxy: ScrollViewProxy) {
        if newEntry == nil { newEntry = VocabularyEntry(spelling: "") }
        selection = .new
        // The row exists after this update.
        Task {
            proxy.scrollTo(RowID.new)
            focus = FieldKey(row: .new, field: .spelling)
        }
    }

    private func remove() {
        switch selection {
        case nil: return
        case .new: dropNewEntry()
        case .saved(let line, let entry):
            selection = nil
            // From this line on, the rows show other entries afterwards; a field there stops editing.
            if case .line(let focused) = focus?.row, focused >= line { detachFocus() }
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

    private func select(_ row: RowID?) {
        switch row {
        case nil: selection = nil
        case .new: selection = newEntry == nil ? nil : .new
        case .line(let line):
            selection = editor.document.items.first { $0.line == line }
                .map { .saved(line: $0.line, entry: $0.entry) }
        }
    }

    /// Esc: the field shows the saved value again.
    private func discard(_ key: FieldKey) {
        switch key.row {
        case .new:
            newEntry = newEntry.map { Self.setting(key.field, to: "", in: $0) }
        case .line(let line):
            drafts[line]?.set(key.field, nil)
            if drafts[line]?.isEmpty == true {
                drafts[line] = nil
                refused.remove(key.row)
            }
        }
    }

    /// Leaving a field saves its line; the new row saves once the focus leaves the whole row. A detached field saves
    /// nothing.
    private func focusMoved(from old: FieldKey?, to new: FieldKey?) {
        if let old, old != new, old != detachedFocus {
            switch old.row {
            case .line: save(old.row, leavingRow: true)
            case .new: if new?.row != .new { save(.new, leavingRow: true) }
            }
        }
        if let new {
            detachedFocus = nil
            select(new.row)
        }
    }

    /// Ends the editing of the focused field, whose row now shows another entry.
    private func detachFocus() {
        detachedFocus = focus
        focus = nil
    }

    private func save(_ row: RowID, leavingRow: Bool) {
        switch row {
        case .line(let line): saveLine(line)
        case .new: saveNewEntry(discardIfEmpty: leavingRow)
        }
    }

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

    /// Closing the window or leaving the pane saves what is valid; the rest is dropped with the view.
    private func saveAll() {
        for line in drafts.keys.sorted() { saveLine(line) }
        saveNewEntry(discardIfEmpty: true)
    }

    private func dropNewEntry() {
        newEntry = nil
        refused.remove(.new)
        if selection == .new { selection = nil }
    }

    /// After any change of the document: drafts and the selection whose line no longer holds their entry go, and so
    /// does the editing of a field in such a row. Focusing a row selects it, so a focused row without a draft is
    /// caught through the selection.
    private func dropStaleDrafts() {
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
        if case .line(let focused) = focus?.row, staleLines.contains(focused) { detachFocus() }
        if lostTyping, editor.notice == nil { lostEdit = EditorText.changedOnDisk }
    }

    private func isCurrent(_ line: Int, _ entry: VocabularyEntry) -> Bool {
        editor.document.items.contains { $0.line == line && $0.entry == entry }
    }

    // MARK: Fields

    private static func label(_ field: EntryField) -> String {
        field == .spelling ? "Schreibweise" : "Erkannt als (optional)"
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
