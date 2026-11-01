import ZackCore

extension EntryProblem {
    public var message: String {
        switch self {
        case .empty: "Darf nicht leer sein."
        case .arrow: "Die Zeichenfolge => ist hier nicht erlaubt."
        case .leadingHash: "Darf nicht mit # beginnen."
        case .lineBreak: "Nur eine Zeile erlaubt."
        }
    }
}

/// German texts shown by the line editors.
public enum EditorText {
    public static let duplicateSnippet = "Nur der erste Baustein mit diesem Namen wird eingefügt."
    public static let duplicateSpelling = "Diese Schreibweise steht schon im Wörterbuch."
    public static let changedOnDisk =
        "Die Datei wurde außerhalb geändert und neu geladen. Die letzte Änderung ist nicht gespeichert."
    public static let unreadableFile = "Zack kann die Datei nicht lesen."
    public static let noBundleID = "Diese App hat keine Bundle-ID."

    public static func writeFailed(_ description: String) -> String {
        "Zack konnte die Datei nicht speichern: \(description)"
    }

    public static func unreadableLines(_ count: Int) -> String {
        count == 1
            ? "1 Zeile in der Datei kann Zack nicht lesen."
            : "\(count) Zeilen in der Datei kann Zack nicht lesen."
    }

    public static func alreadyListed(_ app: String) -> String { "\(app) steht schon in der Liste." }

    public static func coveredByPrefix(_ app: String) -> String {
        "\(app) ist schon über einen Präfix-Eintrag erfasst."
    }
}
