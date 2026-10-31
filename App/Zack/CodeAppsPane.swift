import AppKit
import SwiftUI
import UniformTypeIdentifiers
import ZackCore
import ZackDesktop

/// "Code-Apps": the apps of code-apps.txt; apps are added from the Applications folder, not typed.
struct CodeAppsPane: View {
    let editor: FileEditor<CodeAppsFormat>?
    let openFile: () -> Void

    var body: some View {
        if let editor, editor.state == .loaded {
            CodeAppsList(editor: editor, openFile: openFile)
        } else {
            UnreadableFileNote(openFile: editor == nil ? nil : openFile)
        }
    }
}

private struct CodeAppsList: View {
    typealias Item = EntryDocument<CodeAppsFormat>.Item

    /// Hints of the last "App hinzufügen …"; they hold while the file stays as it was after that action.
    struct Hints {
        let messages: [String]
        let document: EntryDocument<CodeAppsFormat>
    }

    let editor: FileEditor<CodeAppsFormat>
    let openFile: () -> Void

    @State private var selection: Int?
    @State private var hints: Hints?

    var body: some View {
        let document = editor.document
        VStack(alignment: .leading, spacing: 12) {
            Text(
                "In diesen Apps diktiert Zack im Code-Modus: Dateinamen und Schreibweisen werden zu Code, kurze Befehle bekommen keinen Punkt."
            )
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            List(selection: $selection) {
                ForEach(document.items) { item in
                    row(item.entry)
                        .tag(item.line)
                }
            }
            .listStyle(.bordered)
            .accessibilityLabel("Code-Apps")
            EditorFooter(
                onAdd: addApps, onRemove: removeSelected, canRemove: selectedItem(in: document) != nil,
                unreadableCount: document.unreadableCount, notice: editor.notice ?? shownHints(for: document),
                openFile: openFile)
        }
        .padding(20)
        .onChange(of: editor.document) {
            if let selection, selectedItem(in: editor.document)?.line != selection { self.selection = nil }
        }
    }

    // MARK: Views

    @ViewBuilder
    private func row(_ entry: CodeAppEntry) -> some View {
        switch entry {
        case .app(let id):
            let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
            HStack(spacing: 8) {
                Image(nsImage: url.map { NSWorkspace.shared.icon(forFile: $0.path) } ?? Self.genericIcon)
                    .resizable()
                    .frame(width: 20, height: 20)
                    .accessibilityHidden(true)
                if let url {
                    Text(FileManager.default.displayName(atPath: url.path))
                } else {
                    Text(verbatim: id)
                    Text("nicht installiert").foregroundStyle(.secondary)
                }
            }
        case .prefix(let prefix):
            Text(verbatim: "Alle Apps mit ‚\(prefix)‘")
        }
    }

    private static var genericIcon: NSImage {
        NSWorkspace.shared.icon(for: .applicationBundle)
    }

    // MARK: Actions

    private func shownHints(for document: EntryDocument<CodeAppsFormat>) -> String? {
        guard let hints, hints.document == document, !hints.messages.isEmpty else { return nil }
        return hints.messages.joined(separator: " ")
    }

    private func selectedItem(in document: EntryDocument<CodeAppsFormat>) -> Item? {
        document.items.first { $0.line == selection }
    }

    private func removeSelected() {
        hints = nil
        guard let item = selectedItem(in: editor.document) else { return }
        editor.remove(line: item.line, expecting: item.entry)
        selection = nil
    }

    private func addApps() {
        hints = nil
        let panel = NSOpenPanel()
        panel.directoryURL = URL(filePath: "/Applications", directoryHint: .isDirectory)
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return }
        var messages: [String] = []
        for url in panel.urls {
            let name = FileManager.default.displayName(atPath: url.path)
            guard let id = Bundle(url: url)?.bundleIdentifier else {
                messages.append(EditorText.noBundleID)
                continue
            }
            // Read per app: an app added a moment ago makes the next one of the same ID a duplicate.
            switch CodeApps(parsing: editor.document.text).match(id) {
            case .exact: messages.append(EditorText.alreadyListed(name))
            case .prefix: messages.append(EditorText.coveredByPrefix(name))
            case .none: _ = editor.add(.app(id))
            }
        }
        hints = Hints(messages: messages, document: editor.document)
    }
}
