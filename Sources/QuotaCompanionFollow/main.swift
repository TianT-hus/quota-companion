import AppKit
import QuotaCore

/// Registered only by the explicit Follow Codex switch. No quota or schedule data.
@MainActor final class FollowDelegate: NSObject, NSApplicationDelegate {
    private var policy = CodexFollowPolicy()
    private var pending: DispatchWorkItem?
    private let codexID = "com.openai.codex"
    private let companionID = "dev.quota-companion.mac"
    private var companionURL: URL {
        // ServiceManagement may supply a bundle-relative argv[0]. Never resolve
        // that against launchd's working directory when locating the parent app.
        if Bundle.main.bundleIdentifier == companionID { return Bundle.main.bundleURL.standardizedFileURL }
        return URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.prohibited)
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(changed(_:)), name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        center.addObserver(self, selector: #selector(changed(_:)), name: NSWorkspace.didTerminateApplicationNotification, object: nil)
        reconcile()
    }
    @objc private func changed(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication, app.bundleIdentifier == codexID else { return }
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.reconcile() }
        pending = work; DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }
    private func reconcile() {
        let ownURL = companionURL.standardizedFileURL
        guard Bundle(url: ownURL)?.bundleIdentifier == companionID else { NSApp.terminate(nil); return }
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: codexID).contains { !$0.isTerminated }
        let companions = NSRunningApplication.runningApplications(withBundleIdentifier: companionID).filter {
            $0.bundleURL?.standardizedFileURL == ownURL && !$0.isTerminated
        }
        switch policy.observe(codexRunning: running) {
        case .launchCompanion:
            guard companions.isEmpty else { return }
            let configuration = NSWorkspace.OpenConfiguration(); configuration.activates = false
            NSWorkspace.shared.openApplication(at: ownURL, configuration: configuration)
        case .quitCompanion: companions.forEach { _ = $0.terminate() }
        case .none: break
        }
    }
}

let app = NSApplication.shared
let delegate = FollowDelegate()
app.delegate = delegate
app.run()
