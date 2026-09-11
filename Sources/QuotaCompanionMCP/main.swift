import AppKit
import Foundation
import QuotaCore

@main
enum QuotaCompanionMCP {
    static func main() async {
        while let line = readLine() {
            guard let data = line.data(using: .utf8),
                  let request = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            if let response = await handle(request) { write(response) }
        }
    }

    private static func handle(_ request: [String: Any]) async -> [String: Any]? {
        let method = request["method"] as? String ?? ""
        let id = request["id"]
        switch method {
        case "initialize":
            return success(id: id, result: [
                "protocolVersion": "2025-06-18",
                "capabilities": ["tools": ["listChanged": false], "resources": ["subscribe": false, "listChanged": false]],
                "serverInfo": ["name": "quota-companion", "version": "0.1.12"],
            ])
        case "notifications/initialized":
            return nil
        case "ping":
            return success(id: id, result: [:])
        case "tools/list":
            return success(id: id, result: ["tools": toolDefinitions])
        case "tools/call":
            let params = request["params"] as? [String: Any]
            let name = params?["name"] as? String ?? ""
            return success(id: id, result: await callTool(name))
        case "resources/list":
            return success(id: id, result: ["resources": [[
                "uri": cardURI,
                "name": "Codex quota liquid card",
                "description": "Inline liquid-level visualization for the main Codex quota.",
                "mimeType": "text/html;profile=mcp-app",
            ]]])
        case "resources/read":
            let uri = (request["params"] as? [String: Any])?["uri"] as? String
            guard uri == cardURI else { return error(id: id, code: -32002, message: "Resource not found") }
            return success(id: id, result: ["contents": [[
                "uri": cardURI,
                "mimeType": "text/html;profile=mcp-app",
                "text": loadCardHTML(),
                "_meta": ["ui": ["prefersBorder": true]],
            ]]])
        default:
            return error(id: id, code: -32601, message: "Method not found")
        }
    }

    private static let cardURI = "ui://quota-companion/liquid-card.html"

    private static var toolDefinitions: [[String: Any]] {
        [
            [
                "name": "get_quota_status",
                "title": "Get Codex quota status",
                "description": "Read the current main Codex quota windows without exposing account identity or changing the account.",
                "inputSchema": ["type": "object", "properties": [:], "additionalProperties": false],
                "annotations": ["readOnlyHint": true, "destructiveHint": false],
                "_meta": ["ui/outputTemplate": cardURI],
            ],
            controlDefinition(name: "show_companion", title: "Show quota companion", description: "Launch and expand the local quota companion."),
            controlDefinition(name: "collapse_companion", title: "Collapse quota companion", description: "Hide details while keeping the pixel cat visible."),
            controlDefinition(name: "open_companion_settings", title: "Open quota companion settings", description: "Open the local quota companion settings window."),
        ]
    }

    private static func controlDefinition(name: String, title: String, description: String) -> [String: Any] {
        [
            "name": name,
            "title": title,
            "description": description,
            "inputSchema": ["type": "object", "properties": [:], "additionalProperties": false],
            "annotations": ["readOnlyHint": false, "destructiveHint": false],
        ]
    }

    private static func callTool(_ name: String) async -> [String: Any] {
        switch name {
        case "get_quota_status":
            let snapshot = await readSnapshot()
            let structured = structuredSnapshot(snapshot)
            return [
                "content": [["type": "text", "text": readableSnapshot(snapshot)]],
                "structuredContent": structured,
                "_meta": ["quotaCompanion": structured],
            ]
        case "show_companion":
            return control(host: "show", message: "额度水滴已启动并展开。")
        case "collapse_companion":
            return control(host: "collapse", message: "详情已收起，像素小猫保持显示。")
        case "open_companion_settings":
            return control(host: "settings", message: "已打开额度水滴设置。")
        default:
            return toolError("Unknown tool: \(name)")
        }
    }

    private static func readSnapshot() async -> QuotaSnapshot {
        let store = SnapshotStore()
        if let data = QuotaSocketClient.read(path: store.socketURL.path),
           let live = decodeSnapshot(data) {
            return live
        }

        let client = CodexAppServerClient()
        do {
            let data = try await client.readRateLimits()
            defer { Task { await client.stop() } }
            guard let patch = try RateLimitPayloadParser.parse(data) else { return cachedOrUnavailable(store) }
            var accumulator = RateLimitAccumulator()
            return accumulator.merge(patch) ?? cachedOrUnavailable(store)
        } catch {
            await client.stop()
            return cachedOrUnavailable(store)
        }
    }

    private static func cachedOrUnavailable(_ store: SnapshotStore) -> QuotaSnapshot {
        store.loadSnapshot()?.markedStale() ?? .unavailable()
    }

    private static func decodeSnapshot(_ data: Data) -> QuotaSnapshot? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(QuotaSnapshot.self, from: data)
    }

    private static func structuredSnapshot(_ snapshot: QuotaSnapshot) -> [String: Any] {
        let formatter = ISO8601DateFormatter()
        let windows = snapshot.windows.map { window -> [String: Any] in
            [
                "kind": window.kind.rawValue,
                "label": window.compactLabel(locale: Locale(identifier: "zh-Hans")),
                "remainingPercent": window.remainingPercent,
                "usedPercent": window.usedPercent,
                "windowDurationMins": window.windowDurationMinutes,
                "resetsAt": formatter.string(from: window.resetsAt),
            ]
        }
        var value: [String: Any] = [
            "status": snapshot.state.rawValue,
            "observedAt": formatter.string(from: snapshot.observedAt),
            "source": snapshot.source.rawValue,
            "windows": windows,
        ]
        if let limiting = snapshot.limitingWindow {
            value["limitingWindow"] = [
                "kind": limiting.kind.rawValue,
                "label": limiting.compactLabel(locale: Locale(identifier: "zh-Hans")),
                "remainingPercent": limiting.remainingPercent,
                "windowDurationMins": limiting.windowDurationMinutes,
            ]
        }
        return value
    }

    private static func readableSnapshot(_ snapshot: QuotaSnapshot) -> String {
        guard !snapshot.windows.isEmpty else { return "当前无法读取主 Codex 额度。请先在本机 Codex 登录，并检查 CLI 路径和网络后重试。" }
        let state = snapshot.state == .live ? "实时" : "缓存（非实时）"
        let rows = snapshot.windows.map { window in
            "- \(window.accessibleLabel(locale: Locale(identifier: "zh-Hans")))：剩余 \(Int(window.remainingPercent.rounded()))%，重置时间 \(window.resetsAt.formatted(.iso8601))"
        }.joined(separator: "\n")
        return "主 Codex 额度（\(state)）：\n\(rows)"
    }

    private static func control(host: String, message: String) -> [String: Any] {
        let store = SnapshotStore()
        if let response = QuotaSocketClient.request(path: store.socketURL.path, message: host),
           let object = try? JSONSerialization.jsonObject(with: response) as? [String: Any],
           object["ok"] as? Bool == true {
            return ["content": [["type": "text", "text": message]]]
        }
        guard !IsolatedRuntime.enabled else { return toolError("Isolated QA app is not running; LaunchServices fallback is disabled.") }
        guard let url = URL(string: "quota-companion://\(host)"), NSWorkspace.shared.open(url) else {
            guard launchInstalledApp(command: host) else {
                return toolError("未找到额度水滴应用。请先安装并启动 macOS 应用。")
            }
            return ["content": [["type": "text", "text": message]]]
        }
        return ["content": [["type": "text", "text": message]]]
    }

    private static func launchInstalledApp(command: String) -> Bool {
        let homeApplications = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/额度水滴 Dev.app")
        let candidates = [
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: "dev.quota-companion.mac"),
            URL(fileURLWithPath: "/Applications/额度水滴 Dev.app"),
            homeApplications,
        ].compactMap { $0 }
        guard let application = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else { return false }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = [application.path, "--args", "--quota-command", command]
        do {
            try process.run()
            return true
        } catch {
            return false
        }
    }

    private static func toolError(_ message: String) -> [String: Any] {
        ["content": [["type": "text", "text": message]], "isError": true]
    }

    private static func success(id: Any?, result: [String: Any]) -> [String: Any] {
        var value: [String: Any] = ["jsonrpc": "2.0", "result": result]
        value["id"] = id ?? NSNull()
        return value
    }

    private static func error(id: Any?, code: Int, message: String) -> [String: Any] {
        var value: [String: Any] = ["jsonrpc": "2.0", "error": ["code": code, "message": message]]
        value["id"] = id ?? NSNull()
        return value
    }

    private static func write(_ object: [String: Any]) {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object),
              let line = String(data: data, encoding: .utf8) else { return }
        FileHandle.standardOutput.write(Data((line + "\n").utf8))
    }

    private static func loadCardHTML() -> String {
        let executable = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        let asset = executable.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("assets/liquid-card.html")
        return (try? String(contentsOf: asset, encoding: .utf8)) ?? embeddedCardHTML
    }

    private static let embeddedCardHTML = """
    <!doctype html><html><head><meta charset="utf-8"><style>body{font:14px system-ui;color:#10233c;margin:0}.card{padding:18px;border-radius:22px;background:#eafbff}.orb{width:70px;height:70px;border-radius:50%;background:linear-gradient(#fff9 30%,#2f88ff 31%);display:grid;place-items:center;font:700 16px ui-monospace}</style></head><body><div class="card"><div class="orb" id="orb">—</div><p id="rows">正在读取主 Codex 额度…</p></div><script>function render(d){if(!d)return;const w=d.limitingWindow;document.getElementById('orb').textContent=w?Math.round(w.remainingPercent)+'%':'—';document.getElementById('rows').textContent=(d.windows||[]).map(x=>x.label+' · '+Math.round(x.remainingPercent)+'%').join('  ')||'当前不可用';}render(window.openai&&window.openai.toolOutput);window.addEventListener('openai:set_globals',e=>render(e.detail&&e.detail.globals&&e.detail.globals.toolOutput));</script></body></html>
    """
}
