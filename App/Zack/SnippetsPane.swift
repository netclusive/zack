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

/// The chosen snippet is edited as a draft in `SnippetDrafts`. The text saves 0.5 s after the last keystroke; leaving
/// the fields, Return in the name, choosing another snippet, leaving the pane, the window losing key status and closing
/// the window save as well.
private struct SnippetsEditor: View {
    typealias RowID = SnippetDrafts.RowID

    enum Field: Hashable {
        case name, text
    }

    let editor: FileEditor<SnippetFormat>
    let language: DictationLanguage
    let openFile: () -> Void

    @State private var query = ""
    @State private var drafts: SnippetDrafts
    @FocusState private var focus: Field?

    init(editor: FileEditor<SnippetFormat>, language: DictationLanguage, openFile: @escaping () -> Void) {
        self.editor = editor
        self.language = language
        self.openFile = openFile
        _drafts = State(initialValue: SnippetDrafts(editor: editor))
    }

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
                onAdd: add, onRemove: { drafts.requestRemoval() }, canRemove: drafts.draft != nil,
                unreadableCount: document.unreadableCount, notice: editor.notice ?? drafts.lostEdit,
                openFile: openFile)
        }
        .padding(20)
        .task(id: drafts.draft?.text) {
            try? await Task.sleep(for: .milliseconds(500))
            // Cancelled by the next keystroke or by the end of the view; both save on their own.
            guard !Task.isCancelled else { return }
            drafts.save(leaving: false)
        }
        .onChange(of: editor.document) { drafts.dropStale() }
        // Moving the focus does not leave the snippet: a new one with a blank field keeps waiting.
        .onChange(of: focus) { old, new in
            if old != nil, old != new { drafts.save(leaving: false) }
        }
        // No snippet chosen: the editing of its fields ends with it.
        .onChange(of: drafts.draft == nil) { _, none in
            if none { focus = nil }
        }
        .onDisappear { drafts.save(leaving: true) }
        .onWindowWillClose { drafts.save(leaving: true) }
        // Like a focus change: another app may dictate next, and Zack reads the file for each dictation.
        .onWindowDidResignKey { drafts.save(leaving: false) }
        .confirmationDialog(
            removalTitle, isPresented: removalPresented, titleVisibility: .visible, presenting: drafts.pendingRemoval
        ) { anchor in
            Button("Löschen", role: .destructive) { drafts.remove(anchor) }
            Button("Abbrechen", role: .cancel) {}
        }
    }

    // MARK: Views

    private func names(_ document: EntryDocument<SnippetFormat>) -> some View {
        let draft = drafts.draft
        return List(selection: listSelection) {
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
                TextField("Name", text: binding(.name))
                    .focused($focus, equals: .name)
                    .onSubmit { drafts.save(leaving: true) }
                    .onExitCommand { drafts.discard(.name) }
                    .overlay { flag(.name) }
            }
            Section {
                TextEditor(text: binding(.text))
                    .font(.body)
                    .frame(minHeight: 120, maxHeight: .infinity)
                    .accessibilityLabel("Text")
                    .focused($focus, equals: .text)
                    .onExitCommand { drafts.discard(.text) }
                    .overlay { flag(.text) }
            } header: {
                Text("Text")
            } footer: {
                notes(duplicates: duplicates)
            }
        }
        .formStyle(.grouped)
        .disabled(drafts.draft == nil)
        // New fields for another snippet: no field editor keeps text from the previous one.
        .id(drafts.draft?.id)
    }

    @ViewBuilder
    private func notes(duplicates: Set<Int>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let name = drafts.draft?.name.trimmingCharacters(in: .whitespaces), !name.isEmpty {
                Text("‚\(language.pack.snippetTrigger.capitalized) \(name)‘ diktieren fügt den Text ein.")
                    .foregroundStyle(.secondary)
            }
            if let line = drafts.draft?.anchor?.line, duplicates.contains(line) {
                Text(EditorText.duplicateSnippet)
                    .foregroundStyle(.secondary)
            }
            let problems = ProblemList.messages(for: drafts.issues, label: Self.label)
            if !problems.isEmpty {
                ProblemList(messages: problems)
            }
        }
        .font(.callout)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func flag(_ field: EntryField) -> some View {
        if drafts.issues.contains(where: { $0.field == field }) {
            RoundedRectangle(cornerRadius: 4).stroke(Brand.problem)
        }
    }

    /// Bound to the draft that is chosen now; `SnippetDrafts` ignores a late write from fields of another one.
    private func binding(_ field: EntryField) -> Binding<String> {
        let owner = drafts.draft?.id
        return Binding(
            get: { (field == .name ? drafts.draft?.name : drafts.draft?.text) ?? "" },
            set: { drafts.set(field, to: $0, owner: owner) })
    }

    private var listSelection: Binding<RowID?> {
        Binding(get: { drafts.currentRow }, set: { drafts.choose($0) })
    }

    private var removalTitle: String {
        String(localized: "Baustein ‚\(drafts.pendingRemoval?.entry.name ?? "")‘ löschen?")
    }

    private var removalPresented: Binding<Bool> {
        Binding(get: { drafts.pendingRemoval != nil }, set: { if !$0 { drafts.cancelRemoval() } })
    }

    // MARK: Actions

    private func add() {
        guard drafts.add() else { return }
        // The fields are enabled after this update.
        Task { focus = .name }
    }

    // MARK: Fields

    private static func label(_ field: EntryField) -> String {
        field == .name ? String(localized: "Name") : String(localized: "Text")
    }
}
