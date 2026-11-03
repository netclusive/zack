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

/// Each cell edits a draft in `VocabularyDrafts`; Return, leaving the field or the window losing key status saves it,
/// Esc drops it. The view adds the focus: a field whose row now shows another entry stops editing.
private struct VocabularyTable: View {
    typealias Item = EntryDocument<VocabularyFormat>.Item
    typealias RowID = VocabularyDrafts.RowID

    struct Row: Identifiable {
        let id: RowID
        /// Nil for the row "+" added, which reaches the file once it is valid.
        let item: Item?
    }

    struct FieldKey: Hashable {
        let row: RowID
        let field: EntryField
    }

    let editor: FileEditor<VocabularyFormat>
    let openFile: () -> Void

    @State private var query = ""
    @State private var drafts: VocabularyDrafts
    @FocusState private var focus: FieldKey?
    /// A field whose row now shows another entry; its editing was ended, and nothing it sends is saved.
    @State private var detachedFocus: FieldKey?

    init(editor: FileEditor<VocabularyFormat>, openFile: @escaping () -> Void) {
        self.editor = editor
        self.openFile = openFile
        _drafts = State(initialValue: VocabularyDrafts(editor: editor))
    }

    var body: some View {
        let document = editor.document
        let duplicates = document.laterDuplicates
        ScrollViewReader { proxy in
            VStack(alignment: .leading, spacing: 12) {
                // No fixedSize on text outside a scroll view: it raises the pane's height above the window's.
                Text(
                    "Zack schreibt diese Begriffe genau so und gibt sie der Erkennung als Hinweis. Optional: wie die Erkennung sie falsch hört."
                )
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
                    onAdd: { add(scrollingWith: proxy) }, onRemove: remove, canRemove: drafts.selection != nil,
                    unreadableCount: document.unreadableCount, notice: editor.notice ?? drafts.lostEdit,
                    openFile: openFile)
            }
            .padding(20)
        }
        .onChange(of: editor.document) { dropStaleDrafts() }
        .onChange(of: focus) { old, new in focusMoved(from: old, to: new) }
        .onDisappear { drafts.saveAll() }
        .onWindowWillClose { drafts.saveAll() }
        // Another app may dictate next, and Zack reads the file for each dictation.
        .onWindowDidResignKey { drafts.savePending() }
    }

    // MARK: Rows and cells

    private func rows(_ document: EntryDocument<VocabularyFormat>) -> [Row] {
        var rows = document.items(matching: query).map { Row(id: .line($0.line), item: $0) }
        if drafts.newEntry != nil { rows.append(Row(id: .new, item: nil)) }
        return rows
    }

    private func cell(_ row: Row, _ field: EntryField) -> some View {
        let key = FieldKey(row: row.id, field: field)
        let label = Self.label(field)
        return TextField("", text: text(key, item: row.item), prompt: row.item == nil ? Text(label) : nil)
            .textFieldStyle(.plain)
            .accessibilityLabel(label)
            .focused($focus, equals: key)
            .onSubmit { drafts.save(row.id, leavingRow: true) }
            .onExitCommand { drafts.discard(key.field, row: key.row) }
            .overlay {
                if isFlagged(key) {
                    RoundedRectangle(cornerRadius: 3).stroke(Brand.problem)
                }
            }
    }

    private func text(_ key: FieldKey, item: Item?) -> Binding<String> {
        Binding(
            get: { drafts.value(key.field, row: key.row, saved: item?.entry) },
            set: { text in
                // A detached field writes nothing.
                guard key != detachedFocus else { return }
                drafts.set(key.field, to: text, row: key.row, saved: item?.entry)
            })
    }

    private var tableSelection: Binding<RowID?> {
        Binding(
            get: {
                switch drafts.selection {
                case .saved(let line, _): .line(line)
                case .new: .new
                case nil: nil
                }
            },
            set: { drafts.select($0) })
    }

    // MARK: Problems

    private var problemMessages: [String] {
        ProblemList.messages(for: drafts.issues, label: Self.label)
    }

    private func isFlagged(_ key: FieldKey) -> Bool {
        drafts.issues(for: key.row).contains { $0.field == key.field }
    }

    // MARK: Actions

    private func add(scrollingWith proxy: ScrollViewProxy) {
        drafts.add()
        // The row exists after this update.
        Task {
            proxy.scrollTo(RowID.new)
            focus = FieldKey(row: .new, field: .spelling)
        }
    }

    private func remove() {
        // From the removed line on, the rows show other entries afterwards; a field there stops editing.
        if case .saved(let line, _) = drafts.selection, case .line(let focused) = focus?.row, focused >= line {
            detachFocus()
        }
        drafts.removeSelected()
    }

    /// Leaving a field saves its line; the new row saves once the focus leaves the whole row. A detached field saves
    /// nothing.
    private func focusMoved(from old: FieldKey?, to new: FieldKey?) {
        if let old, old != new, old != detachedFocus {
            switch old.row {
            case .line: drafts.save(old.row, leavingRow: true)
            case .new: if new?.row != .new { drafts.save(.new, leavingRow: true) }
            }
        }
        if let new {
            detachedFocus = nil
            drafts.select(new.row)
        }
    }

    /// Ends the editing of the focused field, whose row now shows another entry.
    private func detachFocus() {
        detachedFocus = focus
        focus = nil
    }

    /// After any change of the document the drafts drop what went stale, and a field in such a row stops editing.
    /// Focusing a row selects it, so a focused row without a draft is caught through the selection.
    private func dropStaleDrafts() {
        let staleLines = drafts.dropStale()
        if case .line(let focused) = focus?.row, staleLines.contains(focused) { detachFocus() }
    }

    // MARK: Fields

    private static func label(_ field: EntryField) -> String {
        field == .spelling ? String(localized: "Schreibweise") : String(localized: "Erkannt als (optional)")
    }
}
