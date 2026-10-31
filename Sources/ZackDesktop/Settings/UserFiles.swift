import Foundation
import ZackCore

public enum UserFileKind: String, CaseIterable, Sendable { case vocabulary, snippets, codeApps }

public enum UserFileError: Error, Equatable, Sendable {
    case unreadable, changedOnDisk
    case writeFailed(String)
}

/// Dictionary and snippets as plain text files, editable in any editor.
public struct UserFiles: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// `~/Library/Application Support/Zack`.
    public static func standard() throws -> UserFiles {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
        return UserFiles(directory: support.appending(path: "Zack", directoryHint: .isDirectory))
    }

    public var vocabularyURL: URL { url(for: .vocabulary) }
    public var snippetsURL: URL { url(for: .snippets) }
    public var codeAppsURL: URL { url(for: .codeApps) }

    public func url(for kind: UserFileKind) -> URL {
        switch kind {
        case .vocabulary: directory.appending(path: "vocabulary.txt")
        case .snippets: directory.appending(path: "snippets.txt")
        case .codeApps: directory.appending(path: "code-apps.txt")
        }
    }

    /// Creates missing files first; an existing file that cannot be read as text throws `.unreadable`.
    public func readForEditing(_ kind: UserFileKind) throws(UserFileError) -> String {
        do {
            try createMissing()
        } catch {
            throw .writeFailed(error.localizedDescription)
        }
        guard let text = Self.readText(url(for: kind)) else { throw .unreadable }
        return text
    }

    /// Reads the file again; throws `.changedOnDisk` if it differs from `expected`, else writes `text` atomically as UTF-8.
    public func write(_ text: String, to kind: UserFileKind, replacing expected: String) throws(UserFileError) {
        let url = url(for: kind)
        // A missing or unreadable file counts as changed and is never overwritten.
        guard Self.readText(url) == expected else { throw .changedOnDisk }
        do {
            // An atomic write onto a symlink would replace the link; write to its target instead.
            try Data(text.utf8).write(to: url.resolvingSymlinksInPath(), options: .atomic)
        } catch {
            throw .writeFailed(error.localizedDescription)
        }
    }

    /// Creates missing files with commented examples; existing files stay untouched.
    public func createMissing() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (url, template) in [
            (vocabularyURL, Self.vocabularyTemplate), (snippetsURL, Self.snippetsTemplate),
            (codeAppsURL, Self.codeAppsTemplate),
        ]
        where !FileManager.default.fileExists(atPath: url.path) {
            try Data(template.utf8).write(to: url, options: .withoutOverwriting)
        }
    }

    /// Reads both files with the ZackCore parsers; a missing or unreadable file counts as empty.
    public func load() -> (vocabulary: Vocabulary, snippets: [Snippet]) {
        let vocabulary = Self.readText(vocabularyURL).map(VocabularyFile.parse)
        let snippets = Self.readText(snippetsURL).map(SnippetFile.parse)
        return (vocabulary ?? Vocabulary(), snippets ?? [])
    }

    /// A missing or unreadable file counts as empty, so every app stays in prose mode.
    public func loadCodeApps() -> CodeApps {
        CodeApps(parsing: Self.readText(codeAppsURL) ?? "")
    }

    /// Switches code mode for one app in `code-apps.txt` (a missing file starts from the template, an unreadable one throws).
    public func toggleCodeMode(for bundleID: String) throws {
        let current: String
        if FileManager.default.fileExists(atPath: codeAppsURL.path) {
            // An existing but unreadable file must never be replaced by the template.
            guard let text = Self.readText(codeAppsURL) else { throw CocoaError(.fileReadUnknown) }
            current = text
        } else {
            current = Self.codeAppsTemplate
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(CodeApps.toggled(bundleID, in: current).utf8)
            .write(to: codeAppsURL.resolvingSymlinksInPath(), options: .atomic)
    }

    /// UTF-16 with a byte order mark; else UTF-8 first, and files saved by a Windows editor fall back to
    /// Windows-1252, then Latin-1, so umlauts survive. Text with NUL (binary data, UTF-16 without a byte order mark)
    /// is unreadable.
    static func readText(_ url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let encodings: [String.Encoding] =
            data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF])
            ? [.utf16] : [.utf8, .windowsCP1252, .isoLatin1]
        guard let text = encodings.lazy.compactMap({ String(data: data, encoding: $0) }).first,
            !text.utf8.contains(0)
        else { return nil }
        return text
    }

    static let vocabularyTemplate = """
        # Wörterbuch für Zack
        # Ein Begriff pro Zeile: Zack schreibt ihn genau so und gibt ihn der Erkennung als Hinweis.
        # Ersetzung: falsch => richtig
        # Zeilen mit # am Anfang gelten nicht. Beispiele, zum Aktivieren das # entfernen:
        # VMware
        # git hub => GitHub

        """

    static let snippetsTemplate = """
        # Textbausteine für Zack
        # Eine Zeile pro Baustein: Name => Text, Zeilenumbruch als \\n
        # Das Diktat „Baustein <Name>“ fügt den Text ein. Beispiel, zum Aktivieren das # entfernen:
        # Gruß => Viele Grüße\\nMax Mustermann

        """

    static let codeAppsTemplate = """
        # Code-Modus für Zack
        # Eine Bundle-ID pro Zeile: In diesen Apps diktiert Zack im Code-Modus.
        # Ein * am Ende gilt für alle IDs mit diesem Anfang. Zeilen mit # am Anfang gelten nicht.
        # Im Menü schaltet „Code-Modus in <App>“ die zuletzt aktive App ein oder aus.
        # Terminal
        com.apple.Terminal
        # iTerm2
        com.googlecode.iterm2
        # Ghostty
        com.mitchellh.ghostty
        # Visual Studio Code
        com.microsoft.VSCode
        # Cursor
        com.todesktop.230313mzl4w4u92
        # Xcode
        com.apple.dt.Xcode
        # JetBrains-IDEs
        com.jetbrains.*

        """
}
