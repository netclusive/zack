import AppKit
import SwiftUI
import ZackUpdate

@main
struct ZackApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuContent(model: delegate.model, updater: delegate.updater)
        } label: {
            MenuBarLabel(model: delegate.model)
        }
        .menuBarExtraStyle(.menu)
    }
}

/// Starts the app model and the updater once AppKit is ready, before any menu is opened.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model: AppModel
    /// Off unless the build carries a feed and a public key (release builds).
    let updater: Updater

    override init() {
        let model = AppModel()
        self.model = model
        let updater = Updater(
            configuration: UpdateConfiguration(bundle: .main), isDictating: { [model] in model.dictation != .idle })
        self.updater = updater
        model.updater = updater
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.start()
        updater.start()
    }
}
