import AppKit
import Combine
import SwiftUI

@MainActor final class SettingsWindowController {
    let navigation = SettingsNavigation()
    private let model: CompanionModel
    private(set) var window: NSWindow?
    private var languageSubscription: AnyCancellable?
    init(model: CompanionModel) {
        self.model = model
        languageSubscription = model.$language.sink { [weak self] language in
            self?.window?.title = Copybook(language: language).text("设置", "Settings")
        }
    }
    func show(activate: Bool = true) {
        navigation.reset()
        if window == nil {
            let host = NSHostingController(rootView: SettingsView(model: model, navigation: navigation))
            let created = NSWindow(contentViewController: host)
            created.styleMask = [.titled, .closable, .miniaturizable]
            created.setContentSize(NSSize(width: 780, height: 620))
            created.isReleasedWhenClosed = false
            created.center()
            window = created
        }
        window?.title = model.copy.text("设置", "Settings")
        window?.makeKeyAndOrderFront(nil)
        if activate { NSApp.activate(ignoringOtherApps: true) }
    }
}
