import AppKit
import Foundation
import ServiceManagement
import QuotaCore
import Testing
@testable import QuotaCompanionApp

@MainActor private final class FakeStartup: StartupRegistering {
    var supported = true
    var values: [StartupMethod: SMAppService.Status] = [:]
    var calls: [String] = []
    var failRegister: Set<StartupMethod> = []
    var failUnregister: Set<StartupMethod> = []
    var requireApproval = false
    var noOp = false
    func status(_ method: StartupMethod) -> SMAppService.Status { values[method] ?? .notRegistered }
    func register(_ method: StartupMethod) throws {
        calls.append("register.\(method)")
        if failRegister.contains(method) { throw CocoaError(.fileWriteNoPermission) }
        if !noOp { values[method] = requireApproval ? .requiresApproval : .enabled }
    }
    func unregister(_ method: StartupMethod) throws {
        calls.append("unregister.\(method)")
        if failUnregister.contains(method) { throw CocoaError(.fileWriteNoPermission) }
        if !noOp { values[method] = .notRegistered }
    }
}

@Suite(.serialized) @MainActor struct StartupLanguage230Tests {
    private let copy = Copybook(language: .zhHans)
    private func fixture(_ run: (UserDefaults, FakeStartup) throws -> Void) throws {
        let name = "startup-230-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        try run(defaults, FakeStartup())
    }

    @Test func openingAndCancelPreserveLegacySuspendedPreference() throws {
        try fixture { defaults, service in
            defaults.set(true, forKey: "followCodex.v1")
            defaults.set(true, forKey: "launchAtLogin")
            service.values[.followCodex] = .enabled
            let settings = CodexFollowSettings(defaults: defaults, registration: service)
            settings.refresh(copy: copy)
            #expect(settings.enabled && !settings.launchAtLogin && service.calls.isEmpty)
            var confirmations = 0
            #expect(!settings.request(.login, enabled: true, copy: copy) { confirmations += 1; return false })
            #expect(confirmations == 1 && service.calls.isEmpty && !settings.changing)
            #expect(defaults.bool(forKey: "followCodex.v1") && defaults.bool(forKey: "launchAtLogin"))
        }
    }
    @Test func confirmedSwitchIsExclusiveAndPersistsBothDirections() throws {
        try fixture { defaults, service in
            defaults.set(true, forKey: "followCodex.v1"); service.values[.followCodex] = .enabled
            let settings = CodexFollowSettings(defaults: defaults, registration: service)
            #expect(settings.request(.login, enabled: true, copy: copy) { true })
            #expect(service.calls == ["unregister.followCodex", "register.login"])
            #expect(!settings.enabled && settings.launchAtLogin)
            let restored = CodexFollowSettings(defaults: defaults, registration: service)
            #expect(!restored.enabled && restored.launchAtLogin)
            #expect(restored.request(.followCodex, enabled: true, copy: copy) { true })
            #expect(restored.enabled && !restored.launchAtLogin)
            #expect(defaults.bool(forKey: "followCodex.v1") && !defaults.bool(forKey: "launchAtLogin"))
        }
    }
    @Test func turningOffDoesNotRestoreSuspendedLogin() throws {
        try fixture { defaults, service in
            defaults.set(true, forKey: "followCodex.v1"); defaults.set(true, forKey: "launchAtLogin")
            service.values[.followCodex] = .enabled
            let settings = CodexFollowSettings(defaults: defaults, registration: service)
            #expect(settings.request(.followCodex, enabled: false, copy: copy) { Issue.record("Unexpected confirmation"); return false })
            #expect(!settings.enabled && !settings.launchAtLogin)
            #expect(service.calls == ["unregister.followCodex"])
            #expect(!defaults.bool(forKey: "launchAtLogin"))
        }
    }
    @Test func failedTargetRestoresOldServiceWithoutCommitting() throws {
        try fixture { defaults, service in
            defaults.set(true, forKey: "followCodex.v1"); service.values[.followCodex] = .enabled
            service.failRegister = [.login]
            let settings = CodexFollowSettings(defaults: defaults, registration: service)
            #expect(!settings.request(.login, enabled: true, copy: copy) { true })
            #expect(service.calls == ["unregister.followCodex", "register.login", "register.followCodex"])
            #expect(settings.enabled && !settings.launchAtLogin)
            #expect(service.status(.followCodex) == .enabled && service.status(.login) == .notRegistered)
            #expect(defaults.bool(forKey: "followCodex.v1") && !defaults.bool(forKey: "launchAtLogin"))
            settings.refresh(copy: copy)
            #expect(settings.message.contains("原偏好已保留"))
        }
    }
    @Test func failedUnregisterNeverEnablesOtherMode() throws {
        try fixture { defaults, service in
            defaults.set(true, forKey: "launchAtLogin"); service.values[.login] = .enabled
            service.failUnregister = [.login]
            let settings = CodexFollowSettings(defaults: defaults, registration: service)
            #expect(!settings.request(.followCodex, enabled: true, copy: copy) { true })
            #expect(service.calls == ["unregister.login"])
            #expect(settings.launchAtLogin && !settings.enabled)
        }
    }
    @Test func rollbackFailureIsExplicitAndNotClaimedRestored() throws {
        try fixture { defaults, service in
            defaults.set(true, forKey: "followCodex.v1"); service.values[.followCodex] = .enabled
            service.failRegister = [.login, .followCodex]
            let settings = CodexFollowSettings(defaults: defaults, registration: service)
            #expect(!settings.request(.login, enabled: true, copy: copy) { true })
            #expect(settings.message.contains("未能完全恢复"))
            #expect(defaults.bool(forKey: "followCodex.v1"))
        }
    }
    @Test func pendingApprovalAndExternalRevocationAreVisibleWithoutSideEffects() throws {
        try fixture { defaults, service in
            service.requireApproval = true
            let settings = CodexFollowSettings(defaults: defaults, registration: service)
            #expect(settings.request(.login, enabled: true, copy: copy) { false })
            #expect(settings.launchAtLogin && settings.pendingApproval && settings.message.contains("等待系统批准"))
            let calls = service.calls
            service.values[.login] = .enabled; settings.refresh(copy: copy)
            #expect(!settings.pendingApproval && settings.message.isEmpty)
            service.values[.login] = .notRegistered; settings.refresh(copy: copy)
            #expect(settings.message.contains("系统尚未启用") && service.calls == calls)
        }
    }
    @Test func unsupportedOrUnconfirmedRegistrationDoesNotPersistSuccess() throws {
        try fixture { defaults, service in
            let settings = CodexFollowSettings(defaults: defaults, registration: service)
            service.supported = false
            #expect(!settings.request(.login, enabled: true, copy: copy) { true })
            #expect(service.calls.isEmpty && !settings.launchAtLogin)
            service.supported = true; service.noOp = true
            #expect(!settings.request(.login, enabled: true, copy: copy) { true })
            #expect(!settings.launchAtLogin && !defaults.bool(forKey: "launchAtLogin"))
        }
    }
    @Test func reentrantRequestWhileConfirmingIsIgnored() throws {
        try fixture { defaults, service in
            defaults.set(true, forKey: "followCodex.v1"); service.values[.followCodex] = .enabled
            let settings = CodexFollowSettings(defaults: defaults, registration: service)
            let result = settings.request(.login, enabled: true, copy: copy) {
                #expect(!settings.request(.login, enabled: true, copy: copy) { Issue.record("Duplicate confirmation"); return true })
                return true
            }
            #expect(result)
            #expect(service.calls.count == 2 && !settings.changing)
        }
    }
    @Test func languagePersistsWithoutChangingSpeechOrStartup() throws {
        try fixture { defaults, _ in
            let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            defaults.set(true, forKey: "followCodex.v1")
            let model = CompanionModel(defaults: defaults, store: SnapshotStore(directory: root))
            let spoken = model.speech.cloudLanguage
            model.language = .english
            #expect(model.copy.text("设置", "Settings") == "Settings")
            #expect(AppDelegate.statusMenuTitles(model.copy).contains("Settings"))
            let restored = CompanionModel(defaults: defaults, store: SnapshotStore(directory: root))
            #expect(restored.language == .english && restored.speech.cloudLanguage == spoken)
            #expect(restored.codexFollow.enabled && !restored.codexFollow.launchAtLogin)
            restored.language = .zhHans
            #expect(restored.copy.text("设置", "Settings") == "设置")
            #expect(defaults.string(forKey: "language") == "zhHans")
            #expect(AppLanguage.allCases.map(\.title) == ["跟随系统 / System", "简体中文", "English"])
        }
    }

    @Test func nativeLanguageMenuDispatchesSelectionAndUpdatesWindow() async throws {
        let name = "language-menu-230-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        let root = URL.temporaryDirectory.appendingPathComponent(name)
        defer { defaults.removePersistentDomain(forName: name); try? FileManager.default.removeItem(at: root) }
        let model = CompanionModel(defaults: defaults, store: SnapshotStore(directory: root))
        model.language = .zhHans
        let controller = SettingsWindowController(model: model)
        controller.show(page: .general, activate: false)
        let window = try #require(controller.window)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(150))
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        let view = try #require(window.contentView)
        let picker = try #require(descendants(view).compactMap { $0 as? NSPopUpButton }.first { $0.itemTitles.contains("English") })
        for (title, language) in [("English", AppLanguage.english), ("简体中文", .zhHans), ("跟随系统 / System", .system)] {
            picker.selectItem(withTitle: title)
            #expect(picker.sendAction(picker.action, to: picker.target))
            try await Task.sleep(for: .milliseconds(80))
            #expect(model.language == language && defaults.string(forKey: "language") == language.rawValue)
            #expect(window.title == model.copy.text("设置", "Settings"))
        }
    }
}
