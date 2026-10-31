import Foundation
import Testing
import ZackCore

@testable import ZackDesktop

struct UserFilesEditingTests {
    let files = UserFiles(
        directory: FileManager.default.temporaryDirectory.appending(path: "zack-edit-\(UUID().uuidString)"))

    @Test func readForEditingCreatesMissingFilesFromTheTemplate() throws {
        defer { try? FileManager.default.removeItem(at: files.directory) }
        #expect(try files.readForEditing(.codeApps) == UserFiles.codeAppsTemplate)
    }

    @Test func writeConvertsWindows1252ToUTF8() throws {
        defer { try? FileManager.default.removeItem(at: files.directory) }
        try FileManager.default.createDirectory(at: files.directory, withIntermediateDirectories: true)
        try #require("Müller\n".data(using: .windowsCP1252)).write(to: files.vocabularyURL)
        let read = try files.readForEditing(.vocabulary)
        #expect(read == "Müller\n")
        try files.write("Müller\nMeier\n", to: .vocabulary, replacing: read)
        #expect(try Data(contentsOf: files.vocabularyURL) == Data("Müller\nMeier\n".utf8))
    }

    @Test func writeRefusesWhenTheFileChangedOnDisk() throws {
        defer { try? FileManager.default.removeItem(at: files.directory) }
        let read = try files.readForEditing(.snippets)
        try Data("Adresse => example.com\n".utf8).write(to: files.snippetsURL)
        #expect(throws: UserFileError.changedOnDisk) { try files.write("x => y\n", to: .snippets, replacing: read) }
        #expect(try String(contentsOf: files.snippetsURL, encoding: .utf8) == "Adresse => example.com\n")
    }

    @Test func readForEditingReportsAnUnreadableFile() throws {
        defer { try? FileManager.default.removeItem(at: files.directory) }
        try FileManager.default.createDirectory(at: files.vocabularyURL, withIntermediateDirectories: true)
        #expect(throws: UserFileError.unreadable) { try files.readForEditing(.vocabulary) }
    }

    @Test func vocabularyAndSnippetTemplatesHaveOnlyComments() {
        #expect(EntryDocument<VocabularyFormat>(text: UserFiles.vocabularyTemplate).items.isEmpty)
        #expect(EntryDocument<SnippetFormat>(text: UserFiles.snippetsTemplate).items.isEmpty)
        #expect(EntryDocument<VocabularyFormat>(text: UserFiles.vocabularyTemplate).unreadableCount == 0)
    }

    @Test func unreadableLinesUsesSingularAndPlural() {
        #expect(EditorText.unreadableLines(1) == "1 Zeile in der Datei kann Zack nicht lesen.")
        #expect(EditorText.unreadableLines(2) == "2 Zeilen in der Datei kann Zack nicht lesen.")
    }
}
