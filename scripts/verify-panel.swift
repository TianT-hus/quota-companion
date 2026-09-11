import AppKit
import CoreGraphics
import Foundation

// Read-only window diagnostics plus the app's existing local controls.
// No auth files, credentials or quota amounts are logged.
@main enum VerifyPanel {
    static func main() throws {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "dev.quota-companion.mac").first else {
            fatalError("Companion is not running")
        }
        let socket = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("QuotaCompanion/quota.sock").path
        func send(_ command: String) throws -> Data {
            guard let data = QuotaSocketClient.request(path: socket, message: command) else { throw NSError(domain: "QuotaPanelQA", code: 1) }
            return data
        }
        func diagnostics() throws -> [String: Any] { try JSONSerialization.jsonObject(with: send("presentation")) as? [String: Any] ?? [:] }
        func windows() -> [CGRect] {
            let all = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
            return all.filter { ($0[kCGWindowOwnerPID as String] as? Int32) == app.processIdentifier && ($0[kCGWindowLayer as String] as? Int) == 3 }
                .compactMap { ($0[kCGWindowBounds as String] as? NSDictionary).flatMap { CGRect(dictionaryRepresentation: $0) } }
        }
        let command = CommandLine.arguments.dropFirst().first ?? "status"
        if command == "stress" {
            let initial = try diagnostics()["pet"] as? [String: Double]
            var failures = 0, internalFailures = 0
            var maxLayout = 0.0, maxExternal = 0.0
            for index in 0..<200 {
                let expanded = index % 2 == 0
                let before = try diagnostics()["sequence"] as? Int ?? 0
                let started = ProcessInfo.processInfo.systemUptime
                _ = try send(expanded ? "show" : "collapse")
                var observed = false
                var latest: [String: Any] = [:]
                repeat {
                    latest = try diagnostics()
                    let frames = windows()
                    let p = latest["pet"] as? [String: Double] ?? [:]
                    let hasPet = frames.contains { $0.width == p["width"] && $0.height == p["height"] }
                    let d = latest["detail"] as? [String: Double] ?? [:]
                    let hasDetail = frames.contains { $0.width == d["width"] && $0.height == d["height"] }
                    observed = (latest["sequence"] as? Int ?? 0) > before && hasPet && hasDetail == expanded &&
                        (latest["mode"] as? String == (expanded ? "hoverDetails" : "petOnly"))
                    if observed { break }
                    Thread.sleep(forTimeInterval: 0.005)
                } while ProcessInfo.processInfo.systemUptime - started < 0.3
                let external = (ProcessInfo.processInfo.systemUptime - started) * 1000
                let internalMS = latest["layoutMilliseconds"] as? Double ?? .infinity
                maxLayout = max(maxLayout, internalMS); maxExternal = max(maxExternal, external)
                if !observed || external > 300 { failures += 1; print("externalLate transition=\(index + 1) ms=\(external)") }
                if internalMS >= 300 || latest["pet"] as? [String: Double] != initial { internalFailures += 1 }
                Thread.sleep(forTimeInterval: max(0, 0.32 - external / 1000))
                if index % 40 == 39 { print("transitions=\(index + 1) externalFailures=\(failures) internalFailures=\(internalFailures)"); fflush(stdout) }
            }
            print("cycles=100 hoverDelayMs=150(maximum requires pointer QA) maxLayoutMs=\(maxLayout) maxExternalMs=\(maxExternal) externalFailures=\(failures) internalFailures=\(internalFailures)")
            if failures + internalFailures > 0 { exit(1) }
        } else if command == "show" || command == "collapse" {
            _ = try send(command); print("control=\(command)")
        } else {
            print("pid=\(app.processIdentifier) windows=\(windows())")
            print(String(data: try send("presentation"), encoding: .utf8) ?? "unavailable")
            let snapshot = try JSONSerialization.jsonObject(with: send("snapshot")) as? [String: Any]
            print("state=\(snapshot?["state"] ?? "unknown") windows=\((snapshot?["windows"] as? [Any])?.count ?? 0)")
        }
    }
}
