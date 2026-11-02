import SwiftUI
import ZackCore
import ZackDesktop

/// "Textbausteine": the names on the left, the chosen snippet on the right.
struct SnippetsPane: View {
    let editor: FileEditor<SnippetFormat>?
    let language: DictationLanguage
    let openFile: () -> Void

    var body: some View {
        if let editor, editor.state == .loaded {
            SnippetsEditor(editor: editor, language: language, openFile: openFile)
        } else {
            UnreadableFileNote(openFile: editor == nil ? nil : openFile)
        }
    }
}

/// The chosen snippet is edited as a draft. The text saves 0.5 s after the last keystroke; leaving the fields, Return
/// in the name, choosing another snippet, leaving the pane, the window losing key status and closing the window save
/// as well. A draft belongs to the line and the entry it started from: when the document changes and that pair is
/// gone, the draft goes too.
private struct SnippetsEditor: View {
    enum RowID: Hashable {
        case line(Int)
        case new
    }

    enum Field: Hashable {
        case name, text
    }

    struct Anchor: Equatable {
        let line: Int
        let entry: Snippet
    }

    /// The chosen snippet as typed; `anchor` is nil until a new snippet is saved.
    struct Draft: Equatable {
        /// Stays the same across saves of this snippet; a different snippet gets a new draft and new fields.
        let id = UUID()
        var anchor: Anchor?
        var name: String
        var text: String

        var entry: Snippet { Snippet(name: name, text: text) }

        /// Compared as written, so a trailing space alone writes nothing.
        var changesFile: Bool {
            guard let anchor else { return true }
            return SnippetFormat.line(for: entry) != SnippetFormat.line(for: anchor.entry)
        }
    }

    let editor: FileEditor<SnippetFormat>
    let language: DictationLanguage
    let openFile: () -> Void

    @State private var query = ""
    /// The chosen snippet; nil when none is chosen.
    @State private var draft: Draft?
    /// The last save was refused; the problems show until fixed, saved or dropped.
    @State private var refused = false
    /// Set when a reload drops typed text; the editor's own notice covers refused writes.
    @State private var lostEdit: String?
    @State private var pendingRemoval: Anchor?
    @FocusState private var focus: Field?

    var body: some View {
        let document = editor.document
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 16) {
                VStack(spacing: 8) {
                    TextField("Suchen", text: $query)
                        .textFieldStyle(.roundedBorder)
                    names(document)
                }
                .frame(width: 200)
                details(duplicates: document.laterDuplicates)
            }
            EditorFooter(
                onAdd: add, onRemove: requestRemoval, canRemove: draft != nil,
                unreadableCount: document.unreadableCount, notice: editor.notice ?? lostEdit, openFile: openFile)
        }
        .padding(20)
        .task(id: draft?.text) {
            try? await Task.sleep(for: .milliseconds(500))
            // Cancelled by the next keystroke or by the end of the view; both save on their own.
            guard !Task.isCancelled else { return }
            save(leaving: false)
        }
        .onChange(of: editor.document) { dropStaleDraft() }
        // Moving the focus does not leave the snippet: a new one with a blank field keeps waiting.
        .onChange(of: focus) { old, new in
            if old != nil, old != new { save(leaving: false) }
        }
        .onDisappear { save(leaving: true) }
        .onWindowWillClose { save(leaving: true) }
        // Like a focus change: another app may dictate next, and Zack reads the file for each dictation.
        .onWindowDidResignKey { save(leaving: false) }
        .confirmationDialog(
            removalTitle, isPresented: removalPresented, titleVisibility: .visible, presenting: pendingRemoval
        ) { anchor in
            Button("Löschen", role: .destructive) { remove(anchor) }
            Button("Abbrechen", role: .cancel) {}
        }
    }

    // MARK: Views

    private func names(_ document: EntryDocument<SnippetFormat>) -> some View {
        List(selection: listSelection) {
            ForEach(document.items(matching: query)) { item in
                // The chosen snippet shows its name as typed.
                Text(draft?.anchor?.line == item.line ? draft?.name ?? item.entry.name : item.entry.name)
                    .tag(RowID.line(item.line))
            }
            if let draft, draft.anchor == nil {
                Text(draft.name.isEmpty ? String(localized: "Name") : draft.name)
                    .foregroundStyle(draft.name.isEmpty ? .secondary : .primary)
                    .tag(RowID.new)
            }
        }
        .listStyle(.bordered)
        .accessibilityLabel("Textbausteine")
    }

    private func details(duplicates: Set<Int>) -> some View {
        Form {
            Section {
                TextField("Name", text: field(\.name))
                    .focused($focus, equals: .name)
                    .onSubmit { save(leaving: true) }
                    .onExitCommand { draft?.name = draft?.anchor?.entry.name ?? "" }
                    .overlay { flag(.name) }
            }
            Section {
                TextEditor(text: field(\.text))
                    .font(.body)
                    .frame(minHeight: 120, maxHeight: .infinity)
                    .accessibilityLabel("Text")
                    .focused($focus, equals: .text)
                    .onExitCommand { draft?.text = draft?.anchor?.entry.text ?? "" }
                    .overlay { flag(.text) }
            } header: {
                Text("Text")
            } footer: {
                notes(duplicates: duplicates)
            }
        }
        .formStyle(.grouped)
        .disabled(draft == nil)
        // New fields for another snippet: no field editor keeps text from the previous one.
        .id(draft?.id)
    }

    @ViewBuilder
    private func notes(duplicates: Set<Int>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let name = draft?.name.trimmingCharacters(in: .whitespaces), !name.isEmpty {
                Text("‚\(language.pack.snippetTrigger.capitalized) \(name)‘ diktieren fügt den Text ein.")
                    .foregroundStyle(.secondary)
            }
            if let line = draft?.anchor?.line, duplicates.contains(line) {
                Text(EditorText.duplicateSnippet)
                    .foregroundStyle(.secondary)
            }
            let problems = ProblemList.messages(for: issues, label: Self.label)
            if !problems.isEmpty {
                ProblemList(messages: problems)
            }
        }
        .font(.callout)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func flag(_ field: EntryField) -> some View {
        if issues.contains(where: { $0.field == field }) {
            RoundedRectangle(cornerRadius: 4).stroke(Brand.problem)
        }
    }

    private func field(_ keyPath: WritableKeyPath<Draft, String>) -> Binding<String> {
        let owner = draft?.id
        return Binding(
            get: { draft?[keyPath: keyPath] ?? "" },
            set: { value in
                // A late write from fields that showed another snippet changes nothing.
                guard let owner, draft?.id == owner else { return }
                draft?[keyPath: keyPath] = value
            })
    }

    private var listSelection: Binding<RowID?> {
        Binding(get: { currentRow }, set: { choose($0) })
    }

    private var currentRow: RowID? {
        guard let draft else { return nil }
        return draft.anchor.map { .line($0.line) } ?? .new
    }

    private var removalTitle: String {
        String(localized: "Baustein ‚\(pendingRemoval?.entry.name ?? "")‘ löschen?")
    }

    private var removalPresented: Binding<Bool> {
        Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } })
    }

    /// Recomputed from the draft, so a fix clears them while typing.
    private var issues: [EntryIssue] {
        guard refused, let draft else { return [] }
        return SnippetFormat.issues(in: draft.entry)
    }

    // MARK: Actions

    /// A snippet with problems or a failed write stays chosen until it is saved or its field is reset with Esc.
    private func choose(_ row: RowID?) {
        guard row != currentRow, save(leaving: true) else { return }
        refused = false
        guard case .line(let line) = row, let item = editor.document.items.first(where: { $0.line == line }) else {
            // The new row is only chosen by "+".
            dropDraft()
            return
        }
        draft = Draft(anchor: Anchor(line: item.line, entry: item.entry), name: item.entry.name, text: item.entry.text)
    }

    private func add() {
        guard save(leaving: true) else { return }
        draft = Draft(anchor: nil, name: "", text: "")
        refused = false
        // The fields are enabled after this update.
        Task { focus = .name }
    }

    private func requestRemoval() {
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

    private func remove(_ anchor: Anchor) {
        editor.remove(line: anchor.line, expecting: anchor.entry)
        dropDraft()
        if editor.notice == nil { lostEdit = nil }
    }

    /// No snippet chosen; the editing of its fields ends with it.
    private func dropDraft() {
        draft = nil
        refused = false
        focus = nil
    }

    /// Writes the chosen snippet if it changed; false while it has problems or its write failed. A new snippet waits
    /// for both fields unless the user leaves it; leaving it blank drops it.
    @discardableResult
    private func save(leaving: Bool) -> Bool {
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
    private func dropStaleDraft() {
        guard let current = draft, let anchor = current.anchor,
            !editor.document.items.contains(where: { $0.line == anchor.line && $0.entry == anchor.entry })
        else { return }
        if current.changesFile, editor.notice == nil { lostEdit = EditorText.changedOnDisk }
        dropDraft()
    }

    // MARK: Fields

    private static func label(_ field: EntryField) -> String {
        field == .name ? String(localized: "Name") : String(localized: "Text")
    }

    private static func isBlank(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
