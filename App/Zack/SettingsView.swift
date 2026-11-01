import SwiftUI
import ZackDesktop
import ZackUpdate

/// Settings window: the panes in a sidebar, the chosen one beside it.
struct SettingsView: View {
    let model: AppModel
    let updater: Updater?

    var body: some View {
        NavigationSplitView {
            List(SettingsPane.allCases, selection: selection) { pane in
                Label(pane.title, image: pane.icon)
                    .tag(pane)
            }
            .navigationSplitViewColumnWidth(180)
            // Fixed sidebar as in System Settings; collapsed, it would hide the only way between the panes.
            .toolbar(removing: .sidebarToggle)
        } detail: {
            switch model.settingsPane {
            case .general: GeneralPane(model: model)
            case .vocabulary:
                VocabularyPane(editor: model.vocabularyEditor) { model.openInTextEditor(.vocabulary) }
            case .snippets:
                SnippetsPane(editor: model.snippetsEditor, language: model.dictationLanguage) {
                    model.openInTextEditor(.snippets)
                }
            case .codeApps:
                CodeAppsPane(editor: model.codeAppsEditor) { model.openInTextEditor(.codeApps) }
            case .updates: UpdatesPane(updater: updater)
            case .setup: ScrollView { SetupView(model: model) }
            }
        }
    }

    /// The list clears its selection with nil; the model always keeps one pane.
    private var selection: Binding<SettingsPane?> {
        Binding(
            get: { model.settingsPane },
            set: { pane in
                if let pane { model.selectSettingsPane(pane) }
            })
    }
}
