import Foundation
import Testing
import ZackCore

@testable import ZackDesktop

@MainActor
struct VocabularyDraftsTests {
    let files = UserFiles(
        directory: FileManager.default.temporaryDirectory.appending(path: "zack-drafts-\(UUID().uuidString)"))
    let vmware = VocabularyEntry(spelling: "VMware")

    private func makeDrafts(_ text: String) throws -> VocabularyDrafts {
        try FileManager.default.createDirectory(at: files.directory, withIntermediateDirectories: true)
        try Data(text.utf8).write(to: files.vocabularyURL)
        return VocabularyDrafts(editor: FileEditor(files: files, kind: .vocabulary))
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
        String(decoding: try Data(contentsOf: files.vocabularyURL), as: UTF8.self)
    }

    /// Regression (b3735c8): a failed write dropped the typed text with the draft.
    @Test func failedWriteKeepsTheLineDraftForAnotherTry() throws {
        defer { removeFolder() }
        let drafts = try makeDrafts("VMware\n")
        drafts.set(.heardAs, to: "VM Ware", row: .line(0), saved: vmware)
        try lockFolder(true)
        drafts.save(.line(0), leavingRow: true)
        #expect(drafts.editor.notice != nil)
        #expect(drafts.editor.notice != EditorText.changedOnDisk)
        #expect(drafts.value(.heardAs, row: .line(0), saved: vmware) == "VM Ware")

        try lockFolder(false)
        drafts.save(.line(0), leavingRow: true)
        #expect(drafts.editor.notice == nil)
        #expect(try fileText() == "VM Ware => VMware\n")
    }

    /// Regression (b3735c8): a failed write dropped the new row.
    @Test func failedWriteKeepsTheNewRowForAnotherTry() throws {
        defer { removeFolder() }
        let drafts = try makeDrafts("VMware\n")
        drafts.add()
        drafts.set(.spelling, to: "Kibana", row: .new, saved: nil)
        try lockFolder(true)
        drafts.save(.new, leavingRow: true)
        #expect(drafts.editor.notice != nil)
        #expect(drafts.newEntry == VocabularyEntry(spelling: "Kibana"))

        try lockFolder(false)
        drafts.save(.new, leavingRow: true)
        #expect(drafts.newEntry == nil)
        #expect(drafts.selection == .saved(line: 1, entry: VocabularyEntry(spelling: "Kibana")))
        #expect(try fileText() == "VMware\nKibana\n")
    }

    /// Regression (e8f0ccf): the window losing key status writes what is valid and keeps a blank new row.
    @Test func losingKeyStatusSavesValidDraftsAndKeepsABlankNewRow() throws {
        defer { removeFolder() }
        let drafts = try makeDrafts("VMware\n")
        drafts.set(.heardAs, to: "VM Ware", row: .line(0), saved: vmware)
        drafts.add()
        drafts.savePending()
        #expect(try fileText() == "VM Ware => VMware\n")
        #expect(drafts.newEntry == VocabularyEntry(spelling: ""))

        // Closing the window drops the blank row instead.
        drafts.saveAll()
        #expect(drafts.newEntry == nil)
    }

    @Test func conflictDropsTheLineDraftAndSaysSo() throws {
        defer { removeFolder() }
        let drafts = try makeDrafts("VMware\n")
        drafts.set(.heardAs, to: "VM Ware", row: .line(0), saved: vmware)
        try Data("VMware\nGitHub\n".utf8).write(to: files.vocabularyURL)
        drafts.save(.line(0), leavingRow: true)
        #expect(drafts.editor.notice == EditorText.changedOnDisk)
        #expect(drafts.value(.heardAs, row: .line(0), saved: vmware) == "")
        #expect(try fileText() == "VMware\nGitHub\n")
    }

    @Test func conflictDropsTheNewRow() throws {
        defer { removeFolder() }
        let drafts = try makeDrafts("VMware\n")
        drafts.add()
        drafts.set(.spelling, to: "Kibana", row: .new, saved: nil)
        try Data("VMware\nGitHub\n".utf8).write(to: files.vocabularyURL)
        drafts.save(.new, leavingRow: true)
        #expect(drafts.editor.notice == EditorText.changedOnDisk)
        #expect(drafts.newEntry == nil)
        #expect(drafts.selection == nil)
    }

    @Test func invalidDraftIsRefusedAndFlagged() throws {
        defer { removeFolder() }
        let drafts = try makeDrafts("VMware\n")
        drafts.set(.spelling, to: "a => b", row: .line(0), saved: vmware)
        drafts.save(.line(0), leavingRow: true)
        #expect(drafts.issues == [EntryIssue(field: .spelling, problem: .arrow)])
        #expect(try fileText() == "VMware\n")

        drafts.discard(.spelling, row: .line(0))
        #expect(drafts.issues.isEmpty)
        #expect(drafts.value(.spelling, row: .line(0), saved: vmware) == "VMware")
    }

    @Test func reloadDropsStaleDraftsAndReportsTheLostTyping() throws {
        defer { removeFolder() }
        let drafts = try makeDrafts("VMware\nKibana\n")
        drafts.set(.heardAs, to: "Kiwana", row: .line(1), saved: VocabularyEntry(spelling: "Kibana"))
        drafts.select(.line(1))
        try Data("VMware\n".utf8).write(to: files.vocabularyURL)
        drafts.editor.reload()
        #expect(drafts.dropStale() == [1])
        #expect(drafts.selection == nil)
        #expect(drafts.lostEdit == EditorText.changedOnDisk)
    }

    @Test func removingALineMovesTheLaterDrafts() throws {
        defer { removeFolder() }
        let drafts = try makeDrafts("VMware\nKibana\nGitHub\n")
        drafts.set(.heardAs, to: "Git Hub", row: .line(2), saved: VocabularyEntry(spelling: "GitHub"))
        drafts.select(.line(0))
        drafts.removeSelected()
        #expect(try fileText() == "Kibana\nGitHub\n")
        #expect(drafts.value(.heardAs, row: .line(1), saved: VocabularyEntry(spelling: "GitHub")) == "Git Hub")
        drafts.saveAll()
        #expect(try fileText() == "Kibana\nGit Hub => GitHub\n")
    }
}
