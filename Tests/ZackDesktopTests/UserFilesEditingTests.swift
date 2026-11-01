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

    @Test func readsUTF16WithAByteOrderMark() throws {
        defer { try? FileManager.default.removeItem(at: files.directory) }
        try FileManager.default.createDirectory(at: files.directory, withIntermediateDirectories: true)
        let littleEndian = try #require("Müller\n".data(using: .utf16LittleEndian))
        try (Data([0xFF, 0xFE]) + littleEndian).write(to: files.vocabularyURL)
        #expect(try files.readForEditing(.vocabulary) == "Müller\n")
        #expect(files.load().vocabulary.terms == ["Müller"])
        let bigEndian = try #require("Gruß => Viele Grüße\n".data(using: .utf16BigEndian))
        try (Data([0xFE, 0xFF]) + bigEndian).write(to: files.snippetsURL)
        #expect(try files.readForEditing(.snippets) == "Gruß => Viele Grüße\n")
    }

    @Test func nulBytesWithoutAByteOrderMarkAreUnreadable() throws {
        defer { try? FileManager.default.removeItem(at: files.directory) }
        try FileManager.default.createDirectory(at: files.directory, withIntermediateDirectories: true)
        // UTF-16 without a byte order mark: every second byte of "Müller" is NUL.
        try #require("Müller\n".data(using: .utf16LittleEndian)).write(to: files.vocabularyURL)
        #expect(throws: UserFileError.unreadable) { try files.readForEditing(.vocabulary) }
        #expect(files.load().vocabulary == Vocabulary())
    }

    @Test func writeRefusesWhenTheFileChangedOnDisk() throws {
        defer { try? FileManager.default.removeItem(at: files.directory) }
        let read = try files.readForEditing(.snippets)
        try Data("Adresse => example.com\n".utf8).write(to: files.snippetsURL)
        #expect(throws: UserFileError.changedOnDisk) { try files.write("x => y\n", to: .snippets, replacing: read) }
        #expect(try String(contentsOf: files.snippetsURL, encoding: .utf8) == "Adresse => example.com\n")
    }

    @Test func writeKeepsASymlinkedFileALink() throws {
        defer { try? FileManager.default.removeItem(at: files.directory) }
        let target = try link(files.vocabularyURL, holding: "Müller\n")
        let read = try files.readForEditing(.vocabulary)
        try files.write("Müller\nMeier\n", to: .vocabulary, replacing: read)
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: files.vocabularyURL.path) == "target.txt")
        #expect(try String(contentsOf: target, encoding: .utf8) == "Müller\nMeier\n")
    }

    @Test func toggleCodeModeKeepsASymlinkedFileALink() throws {
        defer { try? FileManager.default.removeItem(at: files.directory) }
        let target = try link(files.codeAppsURL, holding: "com.example.Editor\n")
        try files.toggleCodeMode(for: "com.example.Terminal")
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: files.codeAppsURL.path) == "target.txt")
        #expect(try String(contentsOf: target, encoding: .utf8) == "com.example.Editor\ncom.example.Terminal\n")
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

    /// Makes `url` a relative symlink to `target.txt` in the same folder, which holds `text`; returns the target.
    private func link(_ url: URL, holding text: String) throws -> URL {
        try FileManager.default.createDirectory(at: files.directory, withIntermediateDirectories: true)
        let target = files.directory.appending(path: "target.txt")
        try Data(text.utf8).write(to: target)
        try FileManager.default.createSymbolicLink(atPath: url.path, withDestinationPath: "target.txt")
        return target
    }

    @Test func englishExampleFilesAreCreated() throws {
        let english = UserFiles(directory: files.directory, language: { .english })
        defer { try? FileManager.default.removeItem(at: files.directory) }
        try english.createMissing()
        let snippets = try String(contentsOf: english.snippetsURL, encoding: .utf8)
        #expect(snippets.contains("snippet <name>"))
        #expect(snippets.contains("Jane Doe"))
        #expect(!snippets.contains("Baustein"))
        #expect(try String(contentsOf: english.vocabularyURL, encoding: .utf8).contains("wrong => right"))
        let apps = try String(contentsOf: english.codeAppsURL, encoding: .utf8)
        let germanIDs = CodeApps(parsing: UserFiles.codeAppsTemplate)
        #expect(germanIDs == CodeApps(parsing: apps))
        #expect(EntryDocument<SnippetFormat>(text: snippets).items.isEmpty)
    }

    @Test func germanExampleFilesAreUnchanged() throws {
        let german = UserFiles(directory: files.directory, language: { .german })
        defer { try? FileManager.default.removeItem(at: files.directory) }
        try german.createMissing()
        #expect(try String(contentsOf: german.vocabularyURL, encoding: .utf8) == UserFiles.vocabularyTemplate)
        #expect(try String(contentsOf: german.snippetsURL, encoding: .utf8) == UserFiles.snippetsTemplate)
        #expect(try String(contentsOf: german.codeAppsURL, encoding: .utf8) == UserFiles.codeAppsTemplate)
    }

    @Test func createMissingKeepsExistingFilesInOtherLanguage() throws {
        let english = UserFiles(directory: files.directory, language: { .english })
        defer { try? FileManager.default.removeItem(at: files.directory) }
        try FileManager.default.createDirectory(at: files.directory, withIntermediateDirectories: true)
        try Data(UserFiles.vocabularyTemplate.utf8).write(to: english.vocabularyURL)
        try english.createMissing()
        #expect(try String(contentsOf: english.vocabularyURL, encoding: .utf8) == UserFiles.vocabularyTemplate)
        #expect(try String(contentsOf: english.snippetsURL, encoding: .utf8).contains("Jane Doe"))
    }
}
