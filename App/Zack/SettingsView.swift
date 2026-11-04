import SwiftUI
import ZackDesktop
import ZackUpdate

/// Settings window: the panes in a sidebar, the chosen one beside it.
struct SettingsView: View {
    let model: AppModel
    let updater: Updater?
    /// The sidebar holds the keyboard focus when the window opens and after a click on a pane, so its selection shows
    /// in the accent colour. Otherwise AppKit focuses the first search field, and a row click leaves no focus at all.
    @FocusState private var sidebarFocused: Bool

    var body: some View {
        NavigationSplitView {
            List(SettingsPane.allCases, selection: selection) { pane in
                Label(pane.title, image: pane.icon)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(.rect)
                    // A click on the selected pane leaves the selection unchanged and never reaches the binding.
                    .simultaneousGesture(TapGesture().onEnded { sidebarFocused = true })
                    .tag(pane)
            }
            .focused($sidebarFocused)
            // AppKit focuses the first key view once the window is ordered front, which happens after onAppear.
            .onAppear { Task { sidebarFocused = true } }
            // Fixed sidebar as in System Settings; collapsed, it would hide the only way between the panes.
            .toolbar(removing: .sidebarToggle)
            // After the toolbar modifier: before it, the width is ignored and the sidebar gets a fifth of the window.
            .navigationSplitViewColumnWidth(180)
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
                sidebarFocused = true
            })
    }
}
