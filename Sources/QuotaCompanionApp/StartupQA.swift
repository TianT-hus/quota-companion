import Foundation
import ServiceManagement

enum StartupQA {
    static var enabled: Bool {
        Bundle.main.object(forInfoDictionaryKey: "QuotaSecretaryPreview") as? Bool == true &&
        Bundle.main.object(forInfoDictionaryKey: "QuotaStartupMock") as? Bool == true
    }
}

/// Isolated native interaction fixture; never delegates to ServiceManagement.
@MainActor final class PreviewStartupRegistration: StartupRegistering {
    var supported: Bool { StartupQA.enabled }
    private var values: [StartupMethod: SMAppService.Status] = [:]
    init(defaults: UserDefaults) {
        let follow = defaults.bool(forKey: "followCodex.v1")
        values[.followCodex] = follow ? .enabled : .notRegistered
        values[.login] = !follow && defaults.bool(forKey: "launchAtLogin") ? .enabled : .notRegistered
    }
    func status(_ method: StartupMethod) -> SMAppService.Status { values[method] ?? .notRegistered }
    func register(_ method: StartupMethod) throws {
        guard supported else { throw CocoaError(.featureUnsupported) }
        values[method] = .enabled
    }
    func unregister(_ method: StartupMethod) throws {
        guard supported else { throw CocoaError(.featureUnsupported) }
        values[method] = .notRegistered
    }
}
