import Foundation
import Testing
import ZackCore

@testable import ZackDesktop

@MainActor
struct SnippetDraftsTests {
    let files = UserFiles(
        directory: FileManager.default.temporaryDirectory.appending(path: "zack-snippets-\(UUID().uuidString)"))

    private func makeDrafts(_ text: String) throws -> SnippetDrafts {
        try FileManager.default.createDirectory(at: files.directory, withIntermediateDirectories: true)
        try Data(text.utf8).write(to: files.snippetsURL)
        return SnippetDrafts(editor: FileEditor(files: files, kind: .snippets))
    }

    /// An atomic write creates a file next to the target, so a read-only folder makes it fail.
    private func lockFolder(_ locked: Bool) throws {
        try FileManager.default.setAttributes(
            [.posixPermissions: locked ? 0o555 : 0o755], ofItemAtPath: files.directory.path)
    }

    private func removeFolder() {
        try? lockFolder(false)
        try? FileManager.default.removeItem(at: files.directory)
    }

    private func fileText() throws -> String {
        String(decoding: try Data(contentsOf: files.snippetsURL), as: UTF8.self)
    }

    private func type(_ field: EntryField, _ value: String, into drafts: SnippetDrafts) {
        drafts.set(field, to: value, owner: drafts.draft?.id)
    }

    /// Regression (b3735c8): a failed write dropped the chosen snippet with its text.
    @Test func failedWriteKeepsTheSnippetChosenForAnotherTry() throws {
        defer { removeFolder() }
        let drafts = try makeDrafts("Gruß => Hallo\nAdresse => example.com\n")
        drafts.choose(.line(0))
        type(.text, "Viele Grüße", into: drafts)
        try lockFolder(true)
        #expect(!drafts.save(leaving: false))
        #expect(drafts.editor.notice != nil)
        #expect(drafts.editor.notice != EditorText.changedOnDisk)
        #expect(drafts.draft?.text == "Viele Grüße")

        // Choosing another snippet keeps the unsaved one.
        drafts.choose(.line(1))
        #expect(drafts.currentRow == .line(0))
        #expect(drafts.draft?.text == "Viele Grüße")

        try lockFolder(false)
        drafts.choose(.line(1))
        #expect(drafts.currentRow == .line(1))
        #expect(try fileText() == "Gruß => Viele Grüße\nAdresse => example.com\n")
    }

    /// Regression (b3735c8): a failed write dropped a new snippet.
    @Test func failedWriteKeepsANewSnippetForAnotherTry() throws {
        defer { removeFolder() }
        let drafts = try makeDrafts("Gruß => Hallo\n")
        #expect(drafts.add())
        type(.name, "Adresse", into: drafts)
        type(.text, "example.com", into: drafts)
        try lockFolder(true)
        #expect(!drafts.save(leaving: true))
        #expect(drafts.currentRow == .new)
        #expect(drafts.draft?.name == "Adresse")

        try lockFolder(false)
        #expect(drafts.save(leaving: true))
        #expect(drafts.currentRow == .line(1))
        #expect(try fileText() == "Gruß => Hallo\nAdresse => example.com\n")
    }

    @Test func conflictDropsTheDraftAndSaysSo() throws {
        defer { removeFolder() }
        let drafts = try makeDrafts("Gruß => Hallo\n")
        drafts.choose(.line(0))
        type(.text, "Viele Grüße", into: drafts)
        try Data("Gruß => Hallo\nAdresse => example.com\n".utf8).write(to: files.snippetsURL)
        #expect(drafts.save(leaving: false))
        #expect(drafts.editor.notice == EditorText.changedOnDisk)
        #expect(drafts.draft == nil)
        #expect(try fileText() == "Gruß => Hallo\nAdresse => example.com\n")
    }

    @Test func newSnippetWaitsForBothFieldsUntilLeft() throws {
        defer { removeFolder() }
        let drafts = try makeDrafts("Gruß => Hallo\n")
        #expect(drafts.add())
        type(.name, "Adresse", into: drafts)
        #expect(drafts.save(leaving: false))
        #expect(drafts.currentRow == .new)
        #expect(try fileText() == "Gruß => Hallo\n")

        #expect(!drafts.save(leaving: true))
        #expect(drafts.issues == [EntryIssue(field: .text, problem: .empty)])
        type(.text, "example.com", into: drafts)
        #expect(drafts.issues.isEmpty)
    }

    @Test func blankNewSnippetIsDroppedWhenLeft() throws {
        defer { removeFolder() }
        let drafts = try makeDrafts("Gruß => Hallo\n")
        #expect(drafts.add())
        drafts.choose(.line(0))
        #expect(drafts.currentRow == .line(0))
        #expect(try fileText() == "Gruß => Hallo\n")
    }

    @Test func escShowsTheSavedValueAgain() throws {
        defer { removeFolder() }
        let drafts = try makeDrafts("Gruß => Hallo\n")
        drafts.choose(.line(0))
        type(.name, "Gruss", into: drafts)
        drafts.discard(.name)
        #expect(drafts.draft?.name == "Gruß")
    }

    @Test func lateWriteFromAnotherSnippetsFieldChangesNothing() throws {
        defer { removeFolder() }
        let drafts = try makeDrafts("Gruß => Hallo\nAdresse => example.com\n")
        drafts.choose(.line(0))
        let first = drafts.draft?.id
        drafts.choose(.line(1))
        drafts.set(.text, to: "Viele Grüße", owner: first)
        #expect(drafts.draft?.text == "example.com")
    }

    @Test func removalSavesFirstAndWaitsForConfirmation() throws {
        defer { removeFolder() }
        let drafts = try makeDrafts("Gruß => Hallo\nAdresse => example.com\n")
        drafts.choose(.line(0))
        type(.text, "Viele Grüße", into: drafts)
        drafts.requestRemoval()
        let pending = try #require(drafts.pendingRemoval)
        #expect(pending.entry == Snippet(name: "Gruß", text: "Viele Grüße"))
        drafts.remove(pending)
        #expect(drafts.draft == nil)
        #expect(drafts.pendingRemoval == nil)
        #expect(try fileText() == "Adresse => example.com\n")
    }

    @Test func reloadDropsAStaleDraftAndReportsTheLostTyping() throws {
        defer { removeFolder() }
        let drafts = try makeDrafts("Gruß => Hallo\n")
        drafts.choose(.line(0))
        type(.text, "Viele Grüße", into: drafts)
        try Data("Adresse => example.com\n".utf8).write(to: files.snippetsURL)
        drafts.editor.reload()
        drafts.dropStale()
        #expect(drafts.draft == nil)
        #expect(drafts.lostEdit == EditorText.changedOnDisk)
    }
}
