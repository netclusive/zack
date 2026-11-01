/// The areas of the settings window, in sidebar order.
public enum SettingsPane: String, CaseIterable, Sendable, Identifiable {
    case general, vocabulary, snippets, codeApps, updates, setup

    public var id: String { rawValue }

    /// Sidebar entry and window title.
    public var title: String {
        switch self {
        case .general: "Allgemein"
        case .vocabulary: "Wörterbuch"
        case .snippets: "Textbausteine"
        case .codeApps: "Code-Apps"
        case .updates: "Updates"
        case .setup: "Einrichtung"
        }
    }

    /// Lucide template image in the app's asset catalog.
    public var icon: String {
        switch self {
        case .general: "lucide-settings"
        case .vocabulary: "lucide-book-a"
        case .snippets: "lucide-text-quote"
        case .codeApps: "lucide-code"
        case .updates: "lucide-refresh-cw"
        case .setup: "lucide-shield-check"
        }
    }
}
