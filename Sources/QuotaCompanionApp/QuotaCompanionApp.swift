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
                Button(delegate.model.copy.text("设置", "Settings")) { delegate.openSettings() }.keyboardShortcut(",")
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let isolatedPreview = Bundle.main.object(forInfoDictionaryKey: "QuotaSecretaryPreview") as? Bool == true
    let model: CompanionModel = {
        guard Bundle.main.object(forInfoDictionaryKey: "QuotaSecretaryPreview") as? Bool == true else { return CompanionModel() }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(Bundle.main.bundleIdentifier ?? "quota-secretary-ui-preview", isDirectory: true)
        // The preview has its own bundle identifier, so standard defaults are
        // already isolated. A suite matching the application domain can fail.
        let defaults = UserDefaults.standard
        return CompanionModel(defaults: defaults, store: SnapshotStore(directory: root))
    }()
    private var statusItem: NSStatusItem?
    private var panelController: PanelController?
    private lazy var settingsController = SettingsWindowController(model: model)
    private var settingsObserver: NSObjectProtocol?
    private var dayObserver: NSObjectProtocol?
    private var instanceLease: CompanionInstanceLease?
    private var previewDeadline: Timer?

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if !isolatedPreview {
            if let existing = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "dev.quota-companion.mac")
                .first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier && $0.isFinishedLaunching }) {
                existing.activate(options: []); NSApp.terminate(nil); return
            }
            guard let lease = CompanionInstanceLease.acquire() else {
                NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "dev.quota-companion.mac")
                    .first { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }?.activate(options: [])
                NSApp.terminate(nil); return
            }
            instanceLease = lease
        }
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()
        let controller = PanelController(model: model)
        panelController = controller
        let managementOnlyPreview = isolatedPreview && (Bundle.main.object(forInfoDictionaryKey: "QuotaManagementOnlyPreview") as? Bool == true || ProcessInfo.processInfo.environment["QUOTA_PREVIEW_MANAGEMENT_ONLY"] == "1")
        if !managementOnlyPreview { controller.show() }
        if isolatedPreview {
            // QA apps cannot remain as a second desktop pet indefinitely.
            let requested = Double(ProcessInfo.processInfo.environment["QUOTA_PREVIEW_LIFETIME"] ?? "600") ?? 600
            previewDeadline = Timer.scheduledTimer(withTimeInterval: min(1800, max(15, requested)), repeats: false) { _ in
                Task { @MainActor in NSApp.terminate(nil) }
            }
            let now = Date(), minute = SecretaryData.minute(now)
            model.snapshot = QuotaSnapshot(state: .live, source: .demo, observedAt: now, windows: QuotaSnapshot.demo().windows)
            if !model.secretary.hasPlan {
                _ = model.secretary.commit { data in
                    data.reminders = false
                    data.exceptions[SecretaryData.dayKey(now)] = [ScheduleBlock(start: max(0,minute-20),end: min(1440,minute+40),title: "示例：开发 App")]
                    data.todos = [TodoItem(title: "示例：整理发布说明")]
                }
            }
            model.secretary.start()
            if !managementOnlyPreview { model.showExpanded() }
            // Explicitly isolated QA bundle only; never imports into a user's library.
            if let path = ProcessInfo.processInfo.environment["QUOTA_PREVIEW_CHARACTER"] {
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    while model.characterLibrary.isBusy { try? await Task.sleep(for: .milliseconds(25)) }
                    model.characterLibrary.importPackage(URL(fileURLWithPath: path), copy: model.copy)
                    while model.characterLibrary.isBusy { try? await Task.sleep(for: .milliseconds(25)) }
                    model.collapse()
                }
            }
            if Bundle.main.object(forInfoDictionaryKey: "QuotaCalendarPreview") as? Bool == true {
                if model.secretary.data.categories.isEmpty {
                    _ = model.secretary.commit { data in
                        let category = ScheduleCategory(name: "工作", colorHex: "A8C9F2")
                        try data.saveCategory(category)
                        var work = ScheduleBlock(start: 540, end: 660, title: "示例：整理工作资料与本周计划"); work.categoryID = category.id
                        for day in 1...7 { data.week[day] = [work, ScheduleBlock(start: 780,end: 840,title: "示例：阅读与休息",colorHex: "E5D8EE")] }
                        data.exceptions = [:]; data.reminders = false
                    }
                }
                model.secretary.calendarPosition.browse(now)
                settingsController.show(page: .day)
            } else if StartupQA.enabled {
                settingsController.show(page: .general)
            } else if VoiceCloneQA.enabled || SpeechStatusQA.enabled {
                // Explicit double-opt-in QA only: consented fixture metadata, no secrets or remote requests.
                for provider in APIProvider.allCases {
                    _ = model.speech.saveAPI(provider:provider,address:provider.endpoint,key:"",consent:true,copy:model.copy)
                }
                if SpeechStatusQA.enabled { model.speech.selectSource(.bailian,consent:true) }
                settingsController.show(page: .speech)
            } else if managementOnlyPreview { settingsController.show(page: .appearance) }
        } else { model.start() }
        settingsObserver = NotificationCenter.default.addObserver(
            forName: .openCompanionSettings,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.openSettings() }
        }
        dayObserver = NotificationCenter.default.addObserver(forName: .openCompanionDay, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.settingsController.show(page: .day) }
        }
        if !isolatedPreview { UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in } }
        if let commandIndex = CommandLine.arguments.firstIndex(of: "--quota-command"),
           CommandLine.arguments.indices.contains(commandIndex + 1) {
            handleCommand(CommandLine.arguments[commandIndex + 1])
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        (VoiceDraftLifecycle.mayTerminate?() ?? true) ? .terminateNow : .terminateCancel
    }
    func applicationWillTerminate(_ notification: Notification) {
        model.speech.stop()
        model.secretary.stop()
        model.reminders.stop()
        NSAppleEventManager.shared().removeEventHandler(forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
        if let settingsObserver { NotificationCenter.default.removeObserver(settingsObserver) }
        if let dayObserver { NotificationCenter.default.removeObserver(dayObserver) }
        previewDeadline?.invalidate()
        instanceLease = nil
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
        case "day": settingsController.show(page: .day)
        default: panelController?.show()
        }
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "sun.max", accessibilityDescription: "朝夕")
        let menu = NSMenu()
        menu.addItem(withTitle: model.copy.text("展开朝夕", "Show Zhaoxi"), action: #selector(showCompanion), keyEquivalent: "")
        menu.addItem(withTitle: "收起详情", action: #selector(collapseCompanion), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "立即刷新", action: #selector(refresh), keyEquivalent: "r")
        menu.addItem(withTitle: "今日安排", action: #selector(openDay), keyEquivalent: "")
        menu.addItem(withTitle: "设置", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: model.copy.text("退出朝夕", "Quit Zhaoxi"), action: #selector(quit), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }
        menu.delegate = self
        menuNeedsUpdate(menu)
        item.menu = menu
        statusItem = item
    }

    static func statusMenuTitles(_ copy: Copybook) -> [String] {
        [copy.text("展开朝夕", "Show Zhaoxi"), copy.text("收起详情", "Collapse details"),
         copy.text("立即刷新", "Refresh now"), copy.text("今日安排", "Today's schedule"),
         copy.text("设置", "Settings"), copy.text("退出朝夕", "Quit Zhaoxi")]
    }
    func menuNeedsUpdate(_ menu: NSMenu) {
        for (item, title) in zip(menu.items.filter { !$0.isSeparatorItem }, Self.statusMenuTitles(model.copy)) {
            item.title = title
        }
    }

    @objc private func showCompanion() { model.showExpanded(); panelController?.show() }
    @objc private func collapseCompanion() { model.collapse(); panelController?.show() }
    @objc private func refresh() { model.refreshNow() }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc func openSettings() { settingsController.show() }
    @objc private func openDay() { model.showDay() }
}
