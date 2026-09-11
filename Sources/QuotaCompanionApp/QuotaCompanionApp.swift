import AppKit
import Carbon.HIToolbox
import SwiftUI
import UserNotifications
import QuotaCore

@main
struct QuotaCompanionApplication: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Settings {
            EmptyView()
        }.commands {
            CommandGroup(replacing: .appSettings) {
                Button(delegate.model.copy.text("设置…", "Settings…")) { delegate.openSettings() }.keyboardShortcut(",")
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let runtimeDefaults: UserDefaults = {
        guard let directory = IsolatedRuntime.directory else { return .standard }
        return try! IsolatedDefaults(directory: directory)
    }()
    private(set) lazy var model = CompanionModel(defaults: runtimeDefaults)
    private var statusItem: NSStatusItem?
    private var panelController: PanelController?
    private lazy var settingsController = SettingsWindowController(model: model)
    private var settingsObserver: NSObjectProtocol?

    func applicationWillFinishLaunching(_ notification: Notification) {
        guard !IsolatedRuntime.enabled else { return }
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()
        let controller = PanelController(model: model, positionDefaults: runtimeDefaults)
        panelController = controller
        controller.show()
        model.start()
        settingsObserver = NotificationCenter.default.addObserver(
            forName: .openCompanionSettings,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.openSettings() }
        }
        if !IsolatedRuntime.enabled {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
        if let commandIndex = CommandLine.arguments.firstIndex(of: "--quota-command"),
           CommandLine.arguments.indices.contains(commandIndex + 1) {
            handleCommand(CommandLine.arguments[commandIndex + 1])
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        NSAppleEventManager.shared().removeEventHandler(forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
        if let settingsObserver { NotificationCenter.default.removeObserver(settingsObserver) }
    }

    @objc private func handleGetURLEvent(_ event: NSAppleEventDescriptor, withReplyEvent reply: NSAppleEventDescriptor) {
        guard let raw = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: raw) else { return }
        switch url.host ?? url.path {
        case let command: handleCommand(command)
        }
    }

    private func handleCommand(_ command: String) {
        switch command {
        case "show": model.showExpanded(); panelController?.show()
        case "collapse": model.collapse(); panelController?.show()
        case "settings": openSettings()
        default: panelController?.show()
        }
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "drop.fill", accessibilityDescription: "额度水滴 Dev")
        let menu = NSMenu()
        menu.addItem(withTitle: "展开额度水滴", action: #selector(showCompanion), keyEquivalent: "")
        menu.addItem(withTitle: "收起详情", action: #selector(collapseCompanion), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "立即刷新", action: #selector(refresh), keyEquivalent: "r")
        menu.addItem(withTitle: "设置…", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出额度水滴", action: #selector(quit), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }
        item.menu = menu
        statusItem = item
    }

    @objc private func showCompanion() { model.showExpanded(); panelController?.show() }
    @objc private func collapseCompanion() { model.collapse(); panelController?.show() }
    @objc private func refresh() { model.refreshNow() }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc func openSettings() { settingsController.show() }
}
