#if DEBUG
    import AppKit
    import SwiftUI

    /// Debug spike: checks whether editing shortcuts work in windows of an app without a main menu.
    struct EditingSpikeView: View {
        struct Row: Identifiable {
            let id: Int
            var spelling: String
            var heard: String
        }

        @State private var field = "Max Mustermann"
        @State private var notes = "Mehrzeiliger Text zum Prüfen von Ausschneiden, Kopieren und Einsetzen."
        @State private var rows = [
            Row(id: 0, spelling: "Zack", heard: "Sack"),
            Row(id: 1, spelling: "example.com", heard: "Example Punkt com"),
        ]

        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                TextField("Textfeld", text: $field)
                TextEditor(text: $notes)
                    .frame(height: 80)
                Table(rows) {
                    TableColumn("Schreibweise") { row in
                        TextField("", text: binding(row.id, \.spelling))
                    }
                    TableColumn("Erkannt als") { row in
                        TextField("", text: binding(row.id, \.heard))
                    }
                }
                .frame(height: 100)
                Button("Bearbeiten-Menü setzen") { Self.installEditMenu() }
            }
            .padding()
            .frame(width: 420)
        }

        private func binding(_ id: Int, _ keyPath: WritableKeyPath<Row, String>) -> Binding<String> {
            Binding(
                get: { rows.first { $0.id == id }?[keyPath: keyPath] ?? "" },
                set: { value in
                    if let index = rows.firstIndex(where: { $0.id == id }) { rows[index][keyPath: keyPath] = value }
                }
            )
        }

        /// Replaces the main menu with an app menu, an Edit menu and a Window menu (all targets nil: responder chain).
        static func installEditMenu() {
            let mainMenu = NSMenu()

            // The first top-level item is treated as the application menu.
            mainMenu.addItem(NSMenuItem(title: "Zack", action: nil, keyEquivalent: ""))
            mainMenu.items[0].submenu = NSMenu(title: "Zack")

            let edit = NSMenu(title: "Bearbeiten")
            edit.addItem(withTitle: "Widerrufen", action: Selector(("undo:")), keyEquivalent: "z")
            let redo = edit.addItem(withTitle: "Wiederholen", action: Selector(("redo:")), keyEquivalent: "z")
            redo.keyEquivalentModifierMask = [.command, .shift]
            edit.addItem(.separator())
            edit.addItem(withTitle: "Ausschneiden", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
            edit.addItem(withTitle: "Kopieren", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
            edit.addItem(withTitle: "Einsetzen", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
            edit.addItem(withTitle: "Alles auswählen", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
            let editItem = NSMenuItem(title: "Bearbeiten", action: nil, keyEquivalent: "")
            editItem.submenu = edit
            mainMenu.addItem(editItem)

            let window = NSMenu(title: "Fenster")
            window.addItem(
                withTitle: "Fenster schließen", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
            let windowItem = NSMenuItem(title: "Fenster", action: nil, keyEquivalent: "")
            windowItem.submenu = window
            mainMenu.addItem(windowItem)

            NSApp.mainMenu = mainMenu
        }
    }
#endif
