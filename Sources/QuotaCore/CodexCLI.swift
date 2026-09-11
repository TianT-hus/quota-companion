import Foundation

public enum CodexCLI {
    public static func locate(customPath: String? = nil) -> String? {
        let candidates = [
            customPath,
            "/Applications/ChatGPT.app/Contents/Resources/codex",
            "/Applications/Codex.app/Contents/Resources/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
        ].compactMap { $0 }

        for path in candidates where FileManager.default.isExecutableFile(atPath: path) { return path }

        let pathEntries = ProcessInfo.processInfo.environment["PATH"]?.split(separator: ":").map(String.init) ?? []
        for directory in pathEntries {
            let path = URL(fileURLWithPath: directory).appendingPathComponent("codex").path
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        return nil
    }
}
