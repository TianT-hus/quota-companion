import AppKit
import Combine
import ServiceManagement

enum StartupMethod: CaseIterable { case followCodex, login }

/// System registration is injectable: tests must never install a real login item.
@MainActor protocol StartupRegistering {
    var supported: Bool { get }
    func status(_ method: StartupMethod) -> SMAppService.Status
    func register(_ method: StartupMethod) throws
    func unregister(_ method: StartupMethod) throws
}

@MainActor struct SystemStartupRegistration: StartupRegistering {
    var supported: Bool {
        Bundle.main.bundleIdentifier == "dev.quota-companion.mac" &&
        Bundle.main.object(forInfoDictionaryKey: "QuotaSecretaryPreview") as? Bool != true &&
        FileManager.default.fileExists(atPath: Bundle.main.bundleURL.appendingPathComponent("Contents/Library/LaunchAgents/\(CodexFollowSettings.plistName)").path)
    }
    private func service(_ method: StartupMethod) -> SMAppService {
        method == .login ? .mainApp : .agent(plistName: CodexFollowSettings.plistName)
    }
    func status(_ method: StartupMethod) -> SMAppService.Status { service(method).status }
    func register(_ method: StartupMethod) throws { try service(method).register() }
    func unregister(_ method: StartupMethod) throws { try service(method).unregister() }
}

@MainActor final class CodexFollowSettings: ObservableObject {
    static let plistName = "dev.quota-companion.follow.plist"
    @Published private(set) var enabled: Bool
    @Published private(set) var launchAtLogin: Bool
    @Published private(set) var pendingApproval = false
    @Published private(set) var message = ""
    @Published private(set) var changing = false
    private let defaults: UserDefaults
    private let registration: any StartupRegistering
    private var failure: String?
    private var rollbackFailed = false

    init(defaults: UserDefaults, registration: (any StartupRegistering)? = nil) {
        self.defaults = defaults
        self.registration = registration ?? (StartupQA.enabled ? PreviewStartupRegistration(defaults: defaults) : SystemStartupRegistration())
        let following = defaults.bool(forKey: "followCodex.v1")
        enabled = following
        // Legacy builds retained a suspended login preference. Display the effective
        // mode without rewriting anything just because the page was opened.
        launchAtLogin = !following && defaults.bool(forKey: "launchAtLogin")
    }

    func refresh(copy: Copybook) {
        guard registration.supported else { return }
        let active: StartupMethod? = enabled ? .followCodex : launchAtLogin ? .login : nil
        pendingApproval = active.map { registration.status($0) == .requiresApproval } ?? false
        if let failure {
            message = copy.text("启动设置未能应用，原偏好已保留：", "Startup changes failed; previous preferences were retained: ") + failure
            if rollbackFailed { message += copy.text(" 系统注册未能完全恢复，请检查系统登录项设置。", " System registration could not be fully restored. Check Login Items in System Settings.") }
        } else if pendingApproval {
            message = copy.text("已提交，等待系统批准。请在“登录项与扩展”中允许朝夕运行。", "Submitted, awaiting system approval. Allow Zhaoxi in Login Items & Extensions.")
        } else if let active, registration.status(active) != .enabled {
            message = copy.text("系统尚未启用此启动方式，请关闭再开启重试，或检查系统登录项设置。", "This startup method is not enabled by macOS. Toggle it off and on to retry, or check Login Items in System Settings.")
        } else { message = "" }
    }

    /// Confirmation precedes all side effects. Turning a mode off never silently
    /// restores an old, suspended mode. Preferences commit only after system success.
    @discardableResult func request(_ method: StartupMethod, enabled value: Bool, copy: Copybook,
                                   confirmSwitch: () -> Bool) -> Bool {
        guard !changing else { return false }
        guard registration.supported else {
            message = copy.text("此预览不注册启动服务；请在已安装的完整应用中启用。", "This preview does not register startup services. Use the installed app.")
            return false
        }
        changing = true; defer { changing = false }
        let other: StartupMethod = method == .login ? .followCodex : .login
        let otherSelected = other == .login ? launchAtLogin : enabled
        if value && (otherSelected || isRegistered(other)), !confirmSwitch() { return false }
        failure = nil; rollbackFailed = false
        let before = Dictionary(uniqueKeysWithValues: StartupMethod.allCases.map { ($0, isRegistered($0)) })
        do {
            if value { try setRegistered(other, false) }
            try setRegistered(method, value)
            if method == .login {
                launchAtLogin = value
                if value { enabled = false }
            } else {
                enabled = value
                if value { launchAtLogin = false }
            }
            defaults.set(enabled, forKey: "followCodex.v1")
            defaults.set(launchAtLogin, forKey: "launchAtLogin")
            refresh(copy: copy)
            return true
        } catch {
            failure = error.localizedDescription
            for mode in [method, other] {
                do { try setRegistered(mode, before[mode] == true) }
                catch { rollbackFailed = true }
            }
            refresh(copy: copy)
            return false
        }
    }

    private func isRegistered(_ method: StartupMethod) -> Bool {
        let status = registration.status(method)
        return status == .enabled || status == .requiresApproval
    }
    private func setRegistered(_ method: StartupMethod, _ value: Bool) throws {
        guard isRegistered(method) != value else { return }
        if value {
            do { try registration.register(method) }
            catch {
                guard registration.status(method) == .requiresApproval else { throw error }
            }
        } else { try registration.unregister(method) }
        guard isRegistered(method) == value else { throw StartupRegistrationError.unconfirmed }
    }
    func openSystemSettings() { SMAppService.openSystemSettingsLoginItems() }
}

private enum StartupRegistrationError: LocalizedError {
    case unconfirmed
    var errorDescription: String? { "macOS did not confirm the startup registration change." }
}
