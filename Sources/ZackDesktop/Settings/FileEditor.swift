import OSLog
import Observation
import ZackCore

/// Edits one user file line by line: validates each change, writes it at once, reloads on outside changes.
@MainActor @Observable
public final class FileEditor<Format: EntryFormat> {
    public enum State: Equatable, Sendable { case loaded, unreadable }

    public private(set) var state: State = .loaded
    public private(set) var document = EntryDocument<Format>(text: "")
    /// Conflict or write failure; cleared by the next successful write or `reload()`.
    public private(set) var notice: String?
    public let kind: UserFileKind

    @ObservationIgnored private let files: UserFiles
    @ObservationIgnored private var lastText = ""
    @ObservationIgnored private let logger = Logger(subsystem: "com.netclusive.zack", category: "editor")

    public init(files: UserFiles, kind: UserFileKind) {
        self.files = files
        self.kind = kind
        reload()
    }

    public func reload() {
        notice = nil
        do {
            let text = try files.readForEditing(kind)
            lastText = text
            document = EntryDocument(text: text)
            state = .loaded
        } catch {
            // Error kind only: the associated description may carry a path.
            switch error {
            case .writeFailed: logger.error("Reload failed: could not create files")
            case .unreadable, .changedOnDisk: logger.error("Reload failed: file unreadable")
            }
            state = .unreadable
        }
    }

    @discardableResult
    public func update(line: Int, from old: Format.Entry, to new: Format.Entry) -> [EntryIssue] {
        guard state == .loaded else { return [] }
        let issues = Format.issues(in: new)
        guard issues.isEmpty else { return issues }
        guard isCurrent(line: line, entry: old) else { return [] }
        var edited = document
        edited.replace(line: line, with: new)
        commit(edited)
        return []
    }

    @discardableResult
    public func add(_ entry: Format.Entry) -> [EntryIssue] {
        guard state == .loaded else { return [] }
        let issues = Format.issues(in: entry)
        guard issues.isEmpty else { return issues }
        var edited = document
        edited.append(entry)
        commit(edited)
        return []
    }

    public func remove(line: Int, expecting old: Format.Entry) {
        guard state == .loaded else { return }
        guard isCurrent(line: line, entry: old) else { return }
        var edited = document
        edited.remove(line: line)
        commit(edited)
    }

    /// A stale line (outside edit, wrong entry) is never written: reload and tell the user.
    private func isCurrent(line: Int, entry: Format.Entry) -> Bool {
        if document.items.contains(where: { $0.line == line && $0.entry == entry }) { return true }
        logger.error("Stale line ignored")
        reload()
        notice = EditorText.changedOnDisk
        return false
    }

    private func commit(_ edited: EntryDocument<Format>) {
        do {
            try files.write(edited.text, to: kind, replacing: lastText)
            lastText = edited.text
            document = edited
            notice = nil
        } catch {
            // Error kinds only: the associated description may carry a path.
            switch error {
            case .changedOnDisk:
                logger.error("Write refused: file changed on disk")
                reload()
                notice = EditorText.changedOnDisk
            case .writeFailed(let description):
                logger.error("Write failed")
                reload()
                notice = EditorText.writeFailed(description)
            case .unreadable:
                logger.error("File unreadable")
                state = .unreadable
            }
        }
    }
}
