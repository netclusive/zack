import ZackCore

extension EntryProblem {
    public var message: String {
        switch self {
        case .empty: UIText.localized("Darf nicht leer sein.")
        case .arrow: UIText.localized("Die Zeichenfolge => ist hier nicht erlaubt.")
        case .leadingHash: UIText.localized("Darf nicht mit # beginnen.")
        case .lineBreak: UIText.localized("Nur eine Zeile erlaubt.")
        }
    }
}

/// Texts shown by the line editors.
public enum EditorText {
    public static var duplicateSnippet: String {
        UIText.localized("Nur der erste Baustein mit diesem Namen wird eingefügt.")
    }
    public static var duplicateSpelling: String {
        UIText.localized("Diese Schreibweise steht schon im Wörterbuch.")
    }
    public static var changedOnDisk: String {
        UIText.localized(
            "Die Datei wurde außerhalb geändert und neu geladen. Die letzte Änderung ist nicht gespeichert.")
    }
    public static var unreadableFile: String { UIText.localized("Zack kann die Datei nicht lesen.") }
    public static var noBundleID: String { UIText.localized("Diese App hat keine Bundle-ID.") }

    public static func writeFailed(_ description: String) -> String {
        UIText.localized("Zack konnte die Datei nicht speichern: \(description)")
    }

    public static func unreadableLines(_ count: Int) -> String {
        UIText.localized("\(count) Zeilen in der Datei kann Zack nicht lesen.")
    }

    public static func alreadyListed(_ app: String) -> String {
        UIText.localized("\(app) steht schon in der Liste.")
    }

    public static func coveredByPrefix(_ app: String) -> String {
        UIText.localized("\(app) ist schon über einen Präfix-Eintrag erfasst.")
    }
}
