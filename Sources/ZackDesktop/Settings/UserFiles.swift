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
    private let language: @Sendable () -> DictationLanguage

    /// `language` picks the example texts of newly created files; it is read at each use.
    public init(directory: URL, language: @escaping @Sendable () -> DictationLanguage = { .german }) {
        self.directory = directory
        self.language = language
    }

    /// `~/Library/Application Support/Zack`.
    public static func standard(language: @escaping @Sendable () -> DictationLanguage = { .german }) throws
        -> UserFiles
    {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
        return UserFiles(
            directory: support.appending(path: "Zack", directoryHint: .isDirectory), language: language)
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
        let language = language()
        for kind in UserFileKind.allCases
        where !FileManager.default.fileExists(atPath: url(for: kind).path(percentEncoded: false)) {
            try Data(Self.template(for: kind, language: language).utf8)
                .write(to: url(for: kind), options: .withoutOverwriting)
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
        if FileManager.default.fileExists(atPath: codeAppsURL.path(percentEncoded: false)) {
            // An existing but unreadable file must never be replaced by the template.
            guard let text = Self.readText(codeAppsURL) else { throw CocoaError(.fileReadUnknown) }
            current = text
        } else {
            current = Self.template(for: .codeApps, language: language())
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

    /// Commented example text for a new file of `kind`.
    public static func template(for kind: UserFileKind, language: DictationLanguage) -> String {
        switch (kind, language) {
        case (.vocabulary, .german): vocabularyTemplate
        case (.vocabulary, .english): englishVocabularyTemplate
        case (.snippets, .german): snippetsTemplate
        case (.snippets, .english): englishSnippetsTemplate
        case (.codeApps, .german): codeAppsTemplate
        case (.codeApps, .english): englishCodeAppsTemplate
        }
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

    static let englishVocabularyTemplate = """
        # Vocabulary for Zack
        # One term per line: Zack writes it exactly like this and passes it to the recognizer as a hint.
        # Replacement: wrong => right
        # Lines starting with # are ignored. Examples, remove the # to activate:
        # VMware
        # git hub => GitHub

        """

    static let englishSnippetsTemplate = """
        # Snippets for Zack
        # One snippet per line: name => text, line break as \\n
        # Dictating "snippet <name>" inserts the text. Example, remove the # to activate:
        # signature => Best regards\\nJane Doe

        """

    static let englishCodeAppsTemplate = """
        # Code mode for Zack
        # One bundle ID per line: Zack dictates in code mode in these apps.
        # A * at the end matches all IDs with this beginning. Lines starting with # are ignored.
        # The menu item "Code Mode in <App>" switches the last active app on or off.
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
        # JetBrains IDEs
        com.jetbrains.*

        """
}
