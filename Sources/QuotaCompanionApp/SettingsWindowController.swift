import AppKit
import Combine
import SwiftUI

/// A single management window, independent of the transient hover card.
@MainActor final class SettingsWindowController: NSObject, NSWindowDelegate {
    let navigation = SettingsNavigation()
    private let model: CompanionModel
    private(set) var window: NSWindow?
    private var subscriptions: Set<AnyCancellable> = []
    var confirmDiscard: (() -> Bool)?
    init(model: CompanionModel) {
        self.model = model
        super.init()
        OwnedDialogs.shared.start()
        NotificationCenter.default.publisher(for: OwnedDialogs.changed).sink { [weak self] _ in
            guard let self else { return }
            self.model.managementSheet = OwnedDialogs.shared.hasChild(self.window)
            if !self.model.managementSheet, self.navigation.closeAfterEditor, self.model.secretary.editor == nil {
                self.navigation.closeAfterEditor = false
                DispatchQueue.main.async { [weak self] in self?.window?.performClose(nil) }
            }
        }.store(in: &subscriptions)
        navigation.requestPage = { [weak self] page in self?.navigate(to: page) }
        model.$language.combineLatest(navigation.$page).sink { [weak self] language, page in
            self?.window?.title = page.windowTitle(Copybook(language: language))
        }.store(in: &subscriptions)
        model.secretary.$editor.sink { [weak self] editor in
            self?.model.managementEditing = editor != nil
        }.store(in: &subscriptions)
        navigation.$todoTitle.combineLatest(navigation.$originalTodoTitle).sink { [weak self] title, original in
            self?.model.managementTodoEditing = title != original
        }.store(in: &subscriptions)
    }
    func show(page: SettingsPage = .appearance, activate: Bool = true) {
        model.collapse()
        if window == nil {
            let host = NSHostingController(rootView: SettingsView(model: model, navigation: navigation))
            let created = NSWindow(contentViewController: host)
            created.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            var restored = model.managementWindowSize
            if let screen = NSScreen.main {
                restored.width = min(restored.width, max(780, screen.visibleFrame.width))
                restored.height = min(restored.height, max(620, screen.visibleFrame.height - 28))
            }
            created.setContentSize(restored)
            created.contentMinSize = NSSize(width: 780, height: 620)
            created.isReleasedWhenClosed = false
            created.delegate = self
            created.center()
            window = created
            OwnedDialogs.shared.managementWindow = created
        }
        navigate(to: page)
        navigation.visible = true
        window?.makeKeyAndOrderFront(nil)
        window?.attachedSheet?.makeKeyAndOrderFront(nil)
        if activate { NSApp.activate(ignoringOtherApps: true) }
    }
    func navigate(to page: SettingsPage) {
        guard !model.reminders.busy else { return }
        guard !OwnedDialogs.shared.hasChild(window), window?.attachedSheet == nil, model.secretary.editor == nil, model.backgroundDraft == nil else { return }
        guard page == navigation.page || discardTodoIfNeeded() else { return }
        guard page == navigation.page || model.speech.discardDraft(copy: model.copy) else { return }
        if window?.isVisible != true { navigation.session = UUID() }
        navigation.page = page
    }
    private func discardTodoIfNeeded() -> Bool {
        guard navigation.hasTodoDraft else { navigation.clearTodoDraft(); return true }
        let discard: Bool
        if let confirmDiscard { discard = confirmDiscard() }
        else {
            let alert = NSAlert()
            alert.messageText = model.copy.text("放弃未保存的待办修改？", "Discard unsaved to-do changes?")
            alert.informativeText = model.copy.text("选择继续编辑以保留当前输入。", "Continue editing to keep your draft.")
            alert.addButton(withTitle: model.copy.text("继续编辑", "Keep editing"))
            alert.addButton(withTitle: model.copy.text("放弃修改", "Discard changes"))
            discard = alert.runOwnedModal(parent: window) == .alertSecondButtonReturn
        }
        if discard { navigation.clearTodoDraft() }
        return discard
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard !model.reminders.busy else { return false }
        guard !OwnedDialogs.shared.hasChild(sender), sender.attachedSheet == nil, model.secretary.editor == nil else {
            if model.secretary.editor != nil {
                navigation.closeAfterEditor = true
                navigation.closeEditorRequest += 1
            }
            sender.attachedSheet?.makeKeyAndOrderFront(nil); return false
        }
        return discardTodoIfNeeded() && model.speech.discardDraft(copy: model.copy)
    }
    func windowDidBecomeKey(_ notification: Notification) { model.managementActive = true }
    func windowDidResize(_ notification: Notification) {
        if let size = window?.contentView?.bounds.size { model.managementWindowSize = size }
    }
    func windowDidResignKey(_ notification: Notification) { model.managementActive = false }
    func windowWillClose(_ notification: Notification) { model.managementActive = false; navigation.visible = false }
    func windowWillBeginSheet(_ notification: Notification) { model.managementSheet = true }
    func windowDidEndSheet(_ notification: Notification) {
        model.managementSheet = false
        if navigation.closeAfterEditor {
            navigation.closeAfterEditor = false
            DispatchQueue.main.async { [weak self] in self?.window?.performClose(nil) }
        }
    }
}
