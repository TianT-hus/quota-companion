import AppKit
import AVFoundation
import Combine
import QuotaCore
import ServiceManagement
import SwiftUI
import UserNotifications

@MainActor
final class CompanionModel: ObservableObject {
    let characterLibrary: CharacterLibrary
    @Published var snapshot: QuotaSnapshot
    @Published var detailDirection: DetailDirection = .right
    @Published private(set) var interaction = PetInteraction()
    var isExpanded: Bool { interaction.mode != .petOnly }
    var isPinned: Bool { interaction.mode == .keyboardDetails }
    @Published var companionSize: CompanionSize { didSet { defaults.set(companionSize.rawValue, forKey: "companionSize") } }
    @Published var palette: CompanionPalette { didSet { defaults.set(palette.rawValue, forKey: "companionPalette"); customAppearance.quotaHex = nil; customAppearance.quotaPresetID = nil } }
    @Published var chestTextStyle: ChestTextStyle { didSet { defaults.set(chestTextStyle.rawValue, forKey: "chestTextStyle"); customAppearance.chest = nil } }
    @Published var customAppearance: CustomAppearance {
        didSet { if let data = try? JSONEncoder().encode(customAppearance) { defaults.set(data, forKey: "customAppearance.v1") } }
    }
    var quotaTint: QuotaCore.RGBColor? { customAppearance.quotaHex.flatMap(QuotaCore.RGBColor.init(hexString:)) }
    var progressTint: QuotaCore.RGBColor? { customAppearance.progressFollowsQuota ? quotaTint : QuotaCore.RGBColor(hexString: customAppearance.progressHex) }
    @Published private(set) var isCompanionVisible = true
    @Published var isConnecting = false
    @Published var diagnosticMessage = ""
    @Published var installMessage = ""
    @Published private(set) var launchAtLoginMessage = ""
    @Published var language: AppLanguage {
        didSet { defaults.set(language.rawValue, forKey: Keys.language) }
    }
    @Published var speechEnabled: Bool {
        didSet { defaults.set(speechEnabled, forKey: Keys.speech) }
    }
    @Published var launchAtLogin: Bool {
        didSet {
            defaults.set(launchAtLogin, forKey: Keys.launchAtLogin)
            updateLaunchAtLogin()
        }
    }
    @Published var customCLIPath: String {
        didSet { defaults.set(customCLIPath, forKey: Keys.cliPath) }
    }
    @Published var customMascotPath: String? {
        didSet { defaults.set(customMascotPath, forKey: Keys.mascotPath) }
    }
    @Published private(set) var customBackgroundName: String?
    @Published private(set) var background: CompanionBackground?
    @Published private(set) var isImportingBackground = false
    @Published private(set) var backgroundMessage = ""
    @Published var backgroundDraft: BackgroundDraft?
    private var backgroundTask: Task<Void, Never>?
    private var backgroundGeneration = 0

    private let defaults: UserDefaults
    private let store: SnapshotStore
    private let snapshotBox = SnapshotBox()
    private var client: CodexAppServerClient?
    private var clientCLIPath: String?
    private var monitorTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var thresholdTracker: ThresholdTracker
    private var socketServer: QuotaSocketServer?
    private let speechSynthesizer = AVSpeechSynthesizer()
    private var presentationHandler: ((PetPresentation) -> Void)?
    private let presentationBox = PresentationBox()
    func recordPresentation(_ data: Data) { presentationBox.set(data) }

    var copy: Copybook { Copybook(language: language) }

    init(defaults: UserDefaults = .standard, store: SnapshotStore = SnapshotStore()) {
        self.defaults = defaults
        self.store = store
        characterLibrary = CharacterLibrary(directory: store.directory.appendingPathComponent("Characters", isDirectory: true), defaults: defaults)
        customAppearance = defaults.data(forKey: "customAppearance.v1").flatMap { try? JSONDecoder().decode(CustomAppearance.self, from: $0) } ?? CustomAppearance()
        companionSize = CompanionSize(rawValue: defaults.string(forKey: "companionSize") ?? "") ?? .medium
        palette = CompanionPalette(rawValue: defaults.string(forKey: "companionPalette") ?? "") ?? .water
        chestTextStyle = ChestTextStyle(rawValue: defaults.string(forKey: "chestTextStyle") ?? "") ?? .whiteInk
        language = AppLanguage(rawValue: defaults.string(forKey: Keys.language) ?? "system") ?? .system
        speechEnabled = defaults.bool(forKey: Keys.speech)
        launchAtLogin = defaults.bool(forKey: Keys.launchAtLogin)
        customCLIPath = defaults.string(forKey: Keys.cliPath) ?? ""
        customMascotPath = defaults.string(forKey: Keys.mascotPath)
        customBackgroundName = defaults.string(forKey: "customBackgroundName")

        snapshot = store.loadSnapshot()?.markedStale() ?? .unavailable()
        thresholdTracker = store.loadThresholdTracker()
        snapshotBox.set(snapshot)
        loadSavedBackground()
    }

    deinit { monitorTask?.cancel(); refreshTask?.cancel(); backgroundTask?.cancel() }

    private var backgroundStore: BackgroundImageStore {
        BackgroundImageStore(directory: store.directory.appendingPathComponent("Backgrounds", isDirectory: true))
    }

    func chooseBackground() {
        guard !isImportingBackground else { return }
        holdInteraction(true)
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .webP, .heic]
        panel.allowsMultipleSelection = false
        panel.message = copy.text("选择本地背景图片，自动调整清晰度，不会上传。", "Choose a local background. Readability is adjusted automatically; nothing is uploaded.")
        panel.begin { [weak self] response in
            self?.holdInteraction(false)
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in self?.importBackground(from: url, presentError: true, editBeforeApplying: true) }
        }
    }

    func importBackground(from source: URL, presentError: Bool = false, editBeforeApplying: Bool = false) {
        holdInteraction(true)
        backgroundTask?.cancel()
        backgroundGeneration += 1
        let generation = backgroundGeneration
        let storage = backgroundStore
        isImportingBackground = true
        backgroundMessage = copy.text("正在优化背景…", "Optimizing background…")
        backgroundTask = Task { [weak self] in
            defer { self?.holdInteraction(false) }
            do {
                let result = try await Task.detached(priority: .utility) {
                    let scoped = source.startAccessingSecurityScopedResource()
                    defer { if scoped { source.stopAccessingSecurityScopedResource() } }
                    let prepared = try BackgroundImageStore.prepare(url: source)
                    let name = editBeforeApplying ? nil : try storage.save(prepared)
                    return (name, prepared)
                }.value
                guard !Task.isCancelled, let self, generation == self.backgroundGeneration else { return }
                guard let image = NSImage(data: result.1.png) else { throw BackgroundImportError.decodeFailed }
                if editBeforeApplying {
                    self.backgroundDraft = BackgroundDraft(image: image, prepared: result.1, composition: BackgroundComposition())
                    self.isImportingBackground = false
                    self.backgroundMessage = ""
                    return
                }
                self.background = CompanionBackground(image: image, appearances: result.1.appearances)
                self.customBackgroundName = result.0
                self.defaults.set(result.0, forKey: "customBackgroundName")
                self.customAppearance.background = nil
                self.isImportingBackground = false
                self.backgroundMessage = self.copy.text("已自动调整清晰度，仅保存在本机。", "Readability adjusted. Saved only on this Mac.")
            } catch {
                guard !Task.isCancelled, let self, generation == self.backgroundGeneration else { return }
                self.isImportingBackground = false
                self.backgroundMessage = self.backgroundError(error)
                if presentError {
                    let alert = NSAlert()
                    alert.messageText = self.copy.text("背景未更改", "Background unchanged")
                    alert.informativeText = self.backgroundMessage
                    alert.addButton(withTitle: self.copy.text("好", "OK"))
                    if let window = NSApp.keyWindow {
                        self.holdInteraction(true)
                        alert.beginSheetModal(for: window) { [weak self] _ in self?.holdInteraction(false) }
                    }
                    else { alert.runModal() }
                }
            }
        }
    }

    func restoreDefaultBackground() {
        backgroundTask?.cancel()
        backgroundGeneration += 1
        isImportingBackground = false
        background = nil
        backgroundDraft = nil
        customAppearance.background = nil
        customBackgroundName = nil
        defaults.removeObject(forKey: "customBackgroundName")
        backgroundMessage = copy.text("已恢复浅青玻璃背景。", "Restored the glass background.")
    }

    func editBackground() {
        guard let background, !isImportingBackground else { return }
        backgroundDraft = BackgroundDraft(image: background.image, prepared: nil, composition: customAppearance.background ?? BackgroundComposition())
    }

    func applyBackgroundDraft(_ draft: BackgroundDraft, composition: BackgroundComposition) {
        guard !isImportingBackground else { return }
        isImportingBackground = true
        backgroundGeneration += 1
        let generation = backgroundGeneration
        let storage = backgroundStore
        backgroundTask?.cancel()
        let previousName = customBackgroundName
        backgroundTask = Task { [weak self] in
            do {
                let prepared = draft.prepared
                let result = try await Task.detached(priority: .utility) {
                    let image = try prepared ?? previousName.map { try storage.load(name: $0) }
                    guard let image else { throw BackgroundImportError.unreadable }
                    let adjusted = try BackgroundImageStore.analyzedComposition(png: image.png, composition: composition)
                    let name = prepared == nil ? nil : try storage.save(image)
                    return (name, adjusted)
                }.value
                guard let self, !Task.isCancelled, generation == self.backgroundGeneration else { return }
                if let prepared = draft.prepared, let name = result.0 {
                    self.background = CompanionBackground(image: draft.image, appearances: prepared.appearances)
                    self.customBackgroundName = name
                    self.defaults.set(name, forKey: "customBackgroundName")
                }
                self.customAppearance.background = result.1
                self.isImportingBackground = false
                self.backgroundDraft = nil
                self.backgroundMessage = self.copy.text("构图已保存，图片仅保存在本机。", "Composition saved. Images stay on this Mac.")
            } catch {
                guard let self, !Task.isCancelled, generation == self.backgroundGeneration else { return }
                self.isImportingBackground = false
                self.backgroundMessage = self.backgroundError(error)
            }
        }
    }

    private func loadSavedBackground() {
        guard let name = customBackgroundName else { return }
        let generation = backgroundGeneration
        let storage = backgroundStore
        backgroundTask = Task { [weak self] in
            do {
                let prepared = try await Task.detached(priority: .utility) { try storage.load(name: name) }.value
                guard !Task.isCancelled, let self, generation == self.backgroundGeneration else { return }
                guard let image = NSImage(data: prepared.png) else { throw BackgroundImportError.decodeFailed }
                self.background = CompanionBackground(image: image, appearances: prepared.appearances)
            } catch {
                guard !Task.isCancelled, let self, generation == self.backgroundGeneration else { return }
                self.backgroundMessage = self.backgroundError(error)
            }
        }
    }

    private func backgroundError(_ error: Error) -> String {
        if let error = error as? BackgroundImportError {
            return error.message(chinese: copy.locale.language.languageCode?.identifier == "zh")
        }
        return copy.text("无法保存背景，请检查磁盘空间和文件访问权限。当前背景未更改。", "Could not save the background. Check disk space and file access. The current background is unchanged.")
    }

    func start() {
        startSocketServer()
        monitorTask?.cancel()
        monitorTask = Task { [weak self] in await self?.monitorLoop() }
    }

    func refreshNow() {
        guard !isConnecting else { return }
        guard let client, clientCLIPath == customCLIPath else {
            monitorTask?.cancel()
            let previousClient = self.client
            isConnecting = true
            monitorTask = Task { [weak self] in
                await previousClient?.stop()
                await self?.monitorLoop()
            }
            return
        }
        isConnecting = true
        refreshTask = Task { [weak self] in
            guard let self else { return }
            defer { self.isConnecting = false }
            do {
                let data = try await client.readRateLimits()
                guard !Task.isCancelled else { return }
                self.consume(data)
            } catch {
                guard !Task.isCancelled else { return }
                self.markDisconnected(error)
            }
        }
    }

    func toggleExpanded() { updateInteraction { $0.click() } }
    func showExpanded() { updateInteraction { $0.showTemporary(now: ProcessInfo.processInfo.systemUptime) } }
    func showKeyboardDetails() { updateInteraction { $0.showPinned() } }
    func openSettings() {
        collapse()
        NotificationCenter.default.post(name: .openCompanionSettings, object: nil)
    }
    func collapse() { updateInteraction { $0.close() } }
    func togglePin() { updateInteraction { $0.togglePin(now: ProcessInfo.processInfo.systemUptime) } }
    func holdInteraction(_ active: Bool) {
        updateInteraction { $0.hold(active, now: ProcessInfo.processInfo.systemUptime) }
    }
    func updateInteraction(_ change: (inout PetInteraction) -> Void) {
        var next = interaction
        change(&next)
        guard next != interaction else { return }
        let oldMode = interaction.mode
        interaction = next
        if oldMode != next.mode { presentationHandler?(next.mode) }
    }
    func setCompanionVisible(_ visible: Bool) { isCompanionVisible = visible }
    func setPresentationHandler(_ handler: @escaping (PetPresentation) -> Void) {
        presentationHandler = handler
        handler(interaction.mode)
    }

    func preview(remaining: Int?) {
        guard let remaining else {
            snapshot = snapshot.markedStale()
            snapshotBox.set(snapshot)
            return
        }
        let now = Date()
        snapshot = QuotaSnapshot(
            state: .stale,
            source: .demo,
            observedAt: now,
            windows: [
                QuotaWindow(kind: .primary, usedPercent: Double(100 - remaining), windowDurationMinutes: 300, resetsAt: now.addingTimeInterval(9_120)),
                QuotaWindow(kind: .secondary, usedPercent: 42, windowDurationMinutes: 10_080, resetsAt: now.addingTimeInterval(277_200)),
            ]
        )
        snapshotBox.set(snapshot)
    }

    func importMascot() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .webP]
        panel.allowsMultipleSelection = false
        panel.message = copy.text("选择透明 PNG、WebP 或 Codex 宠物精灵图", "Choose a transparent PNG, WebP, or Codex pet sprite sheet")
        guard panel.runModal() == .OK, let source = panel.url else { return }
        let directory = store.directory.appendingPathComponent("Mascots", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let destination = directory.appendingPathComponent(source.lastPathComponent)
            if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
            try FileManager.default.copyItem(at: source, to: destination)
            customMascotPath = destination.path
            diagnosticMessage = NSImage(contentsOf: destination).flatMap(SpriteSheetDescriptor.grid(for:)) != nil
                ? copy.text("已识别 Codex 精灵图网格", "Codex sprite grid detected")
                : copy.text("已导入静态宠物图", "Static mascot imported")
        } catch {
            diagnosticMessage = error.localizedDescription
        }
    }

    func resetMascot() { customMascotPath = nil }

    func confirmAndInstallPlugin() {
        guard !IsolatedRuntime.enabled else { installMessage = "Plugin installation is disabled in isolated QA."; return }
        guard let root = bundledMarketplaceRoot else {
            installMessage = copy.text("开发构建中未找到随包插件目录。先运行 scripts/package-app.sh。", "The bundled plugin directory is missing. Run scripts/package-app.sh first.")
            return
        }
        guard let cli = CodexCLI.locate(customPath: customCLIPath.nilIfEmpty) else {
            installMessage = copy.text("未找到 Codex CLI。", "Codex CLI was not found.")
            return
        }
        let command = "\(cli.shellQuoted) plugin marketplace add \(root.path.shellQuoted)"
        let alert = NSAlert()
        alert.messageText = copy.text("安装 Codex 插件？", "Install the Codex plugin?")
        alert.informativeText = copy.text("将执行：\n\(command)\n\n目标：当前用户的 Codex 插件市场配置", "Command:\n\(command)\n\nTarget: the current user's Codex marketplace configuration")
        alert.addButton(withTitle: copy.text("确认安装", "Install"))
        alert.addButton(withTitle: copy.text("取消", "Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: cli)
        process.arguments = ["plugin", "marketplace", "add", root.path]
        process.standardOutput = output
        process.standardError = output
        do {
            try process.run()
            process.waitUntilExit()
            installMessage = process.terminationStatus == 0
                ? copy.text("插件市场已添加。请在 Codex 插件目录中安装“额度水滴 Dev”。", "Marketplace added. Install Quota Drop Dev from the Codex plugin directory.")
                : copy.text("安装命令未成功，请在诊断页复制命令后重试。", "The install command failed. Copy it from Diagnostics and retry.")
        } catch {
            installMessage = error.localizedDescription
        }
    }

    var pluginInstallCommand: String {
        guard let root = bundledMarketplaceRoot else { return copy.text("打包后显示", "Available after packaging") }
        let cli = CodexCLI.locate(customPath: customCLIPath.nilIfEmpty) ?? "codex"
        return "\(cli.shellQuoted) plugin marketplace add \(root.path.shellQuoted)"
    }

    private var bundledMarketplaceRoot: URL? {
        Bundle.main.resourceURL?.appendingPathComponent("PluginMarketplace", isDirectory: true)
    }

    private func monitorLoop() async {
        let retryDelays: [UInt64] = [5, 15, 30, 60, 300]
        var attempt = 0
        repeat {
            if Task.isCancelled { return }
            isConnecting = true
            let appServer = CodexAppServerClient(customCLIPath: customCLIPath.nilIfEmpty)
            client = appServer
            clientCLIPath = customCLIPath
            await appServer.setNotificationHandler { [weak self] data in
                Task { @MainActor in self?.consume(data) }
            }
            do {
                let data = try await appServer.readRateLimits()
                guard !Task.isCancelled else { await appServer.stop(); return }
                consume(data)
                isConnecting = false
                diagnosticMessage = copy.text("已连接 Codex App Server", "Connected to Codex App Server")
                attempt = 0
                while !Task.isCancelled {
                    try await Task.sleep(for: .seconds(60))
                    let refreshed = try await appServer.readRateLimits()
                    guard !Task.isCancelled else { await appServer.stop(); return }
                    consume(refreshed)
                }
            } catch {
                await appServer.stop()
                guard !Task.isCancelled else { return }
                isConnecting = false
                markDisconnected(error)
                let delay = retryDelays[min(attempt, retryDelays.count - 1)]
                attempt += 1
                try? await Task.sleep(for: .seconds(delay))
            }
        } while !Task.isCancelled
    }

    private func consume(_ data: Data) {
        do {
            guard let patch = try RateLimitPayloadParser.parse(data) else { return }
            var accumulator = RateLimitAccumulator(snapshot: snapshot.source == .demo ? nil : snapshot)
            guard let updated = accumulator.merge(patch) else { return }
            let previous = snapshot.source == .demo ? nil : snapshot
            let events = thresholdTracker.events(previous: previous, current: updated)
            snapshot = updated
            snapshotBox.set(updated)
            try? store.save(snapshot: updated)
            try? store.save(thresholdTracker: thresholdTracker)
            events.forEach(notify)
        } catch {
            diagnosticMessage = copy.text("额度响应无法解析", "Could not parse quota response")
        }
    }

    private func markDisconnected(_ error: Error) {
        snapshot = snapshot.source == .demo ? snapshot : snapshot.markedStale()
        snapshotBox.set(snapshot)
        diagnosticMessage = error.localizedDescription
    }

    private func notify(_ event: ThresholdEvent) {
        guard !IsolatedRuntime.enabled else { return }
        let content = UNMutableNotificationContent()
        content.title = copy.text("Codex 额度提醒", "Codex quota alert")
        content.body = copy.text(
            "\(event.window.accessibleLabel(locale: copy.locale))剩余 \(Int(event.window.remainingPercent.rounded()))%",
            "\(event.window.accessibleLabel(locale: copy.locale)) has \(Int(event.window.remainingPercent.rounded()))% remaining"
        )
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        if speechEnabled {
            let utterance = AVSpeechUtterance(string: content.body)
            utterance.voice = AVSpeechSynthesisVoice(language: copy.locale.identifier)
            speechSynthesizer.speak(utterance)
        }
    }

    private func startSocketServer() {
        let server = QuotaSocketServer(path: store.socketURL.path) { [self, snapshotBox, presentationBox] request in
            switch request {
            case "presentation":
                return presentationBox.data()
            case "show":
                DispatchQueue.main.async { self.showExpanded() }
                return Data(#"{"ok":true,"state":"expanded"}"#.utf8)
            case "collapse":
                DispatchQueue.main.async { self.collapse() }
                return Data(#"{"ok":true,"state":"collapsed"}"#.utf8)
            case "settings":
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .openCompanionSettings, object: nil)
                }
                return Data(#"{"ok":true,"state":"settings"}"#.utf8)
            default:
                return snapshotBox.data()
            }
        }
        try? server.start()
        socketServer = server
    }

    private func updateLaunchAtLogin() {
        guard !IsolatedRuntime.enabled else { return }
        launchAtLoginMessage = ""
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }
        do {
            if launchAtLogin { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            launchAtLoginMessage = copy.text("启动设置未能应用：", "Startup setting could not be applied: ") + error.localizedDescription
            diagnosticMessage = error.localizedDescription
        }
    }

    private enum Keys {
        static let language = "language"
        static let speech = "speechEnabled"
        static let launchAtLogin = "launchAtLogin"
        static let cliPath = "customCLIPath"
        static let mascotPath = "customMascotPath"
    }
}

extension Notification.Name {
    static let openCompanionSettings = Notification.Name("QuotaCompanion.openSettings")
}

private final class PresentationBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value = Data("{}".utf8)
    func set(_ data: Data) { lock.lock(); value = data; lock.unlock() }
    func data() -> Data { lock.lock(); defer { lock.unlock() }; return value }
}

private final class SnapshotBox: @unchecked Sendable {
    private let lock = NSLock()
    private var snapshot = QuotaSnapshot.unavailable()
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }()

    func set(_ value: QuotaSnapshot) {
        lock.lock()
        snapshot = value
        lock.unlock()
    }

    func data() -> Data {
        lock.lock()
        let value = snapshot
        lock.unlock()
        return (try? encoder.encode(value)) ?? Data("{}".utf8)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
    var shellQuoted: String { "'" + replacingOccurrences(of: "'", with: "'\\''") + "'" }
}
