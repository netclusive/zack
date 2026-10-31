import Foundation
import Testing
import ZackCore

@testable import ZackDesktop

@MainActor
struct FileEditorTests {
    let files = UserFiles(
        directory: FileManager.default.temporaryDirectory.appending(path: "zack-editor-\(UUID().uuidString)"))

    private func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: files.directory, withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    private func read(_ url: URL) throws -> String {
        String(decoding: try Data(contentsOf: url), as: UTF8.self)
    }

    @Test func validUpdateWritesOnlyThatLine() throws {
        defer { try? FileManager.default.removeItem(at: files.directory) }
        try write("# Kopf\nVMware\nKibana\n", to: files.vocabularyURL)
        let editor = FileEditor<VocabularyFormat>(files: files, kind: .vocabulary)
        #expect(editor.update(line: 2, to: VocabularyEntry(spelling: "Kibana", heardAs: "Kiwana")).isEmpty)
        #expect(try read(files.vocabularyURL) == "# Kopf\nVMware\nKiwana => Kibana\n")
    }

    @Test func invalidEntryIsNotWritten() throws {
        defer { try? FileManager.default.removeItem(at: files.directory) }
        try write("VMware\n", to: files.vocabularyURL)
        let editor = FileEditor<VocabularyFormat>(files: files, kind: .vocabulary)
        #expect(
            editor.update(line: 0, to: VocabularyEntry(spelling: "a => b")) == [
                EntryIssue(field: .spelling, problem: .arrow)
            ])
        #expect(try read(files.vocabularyURL) == "VMware\n")
    }

    @Test func externalChangeReloadsAndDropsTheEdit() throws {
        defer { try? FileManager.default.removeItem(at: files.directory) }
        try write("VMware\n", to: files.vocabularyURL)
        let editor = FileEditor<VocabularyFormat>(files: files, kind: .vocabulary)
        try write("VMware\nGitHub\n", to: files.vocabularyURL)
        editor.add(VocabularyEntry(spelling: "Kibana"))
        #expect(try read(files.vocabularyURL) == "VMware\nGitHub\n")
        #expect(editor.document.text == "VMware\nGitHub\n")
        #expect(editor.notice == EditorText.changedOnDisk)
    }

    @Test func unreadableFileLocksTheEditor() throws {
        defer { try? FileManager.default.removeItem(at: files.directory) }
        try FileManager.default.createDirectory(at: files.snippetsURL, withIntermediateDirectories: true)
        let editor = FileEditor<SnippetFormat>(files: files, kind: .snippets)
        #expect(editor.state == .unreadable)
        editor.add(Snippet(name: "Gruß", text: "Hallo"))
        var isDirectory: ObjCBool = false
        #expect(
            FileManager.default.fileExists(atPath: files.snippetsURL.path, isDirectory: &isDirectory)
                && isDirectory.boolValue)
    }

    @Test func addAppendsAndRemoveDeletes() throws {
        defer { try? FileManager.default.removeItem(at: files.directory) }
        try write("# Kopf\nGruß => Hallo\n", to: files.snippetsURL)
        let editor = FileEditor<SnippetFormat>(files: files, kind: .snippets)
        editor.add(Snippet(name: "Adresse", text: "Max Mustermann\nexample.com"))
        #expect(try read(files.snippetsURL) == "# Kopf\nGruß => Hallo\nAdresse => Max Mustermann\\nexample.com\n")
        editor.remove(line: 1)
        #expect(try read(files.snippetsURL) == "# Kopf\nAdresse => Max Mustermann\\nexample.com\n")
    }

    @Test func reloadPicksUpAnExternalChange() throws {
        defer { try? FileManager.default.removeItem(at: files.directory) }
        try write("VMware\n", to: files.vocabularyURL)
        let editor = FileEditor<VocabularyFormat>(files: files, kind: .vocabulary)
        try write("GitHub\n", to: files.vocabularyURL)
        editor.reload()
        #expect(editor.document.items.map(\.entry) == [VocabularyEntry(spelling: "GitHub")])
        #expect(editor.notice == nil)
    }
}
