import Foundation

public enum CodexCLI {
    public static func locate(customPath: String? = nil) -> String? {
        locate(customPath: customPath, environmentPath: ProcessInfo.processInfo.environment["PATH"],
               isExecutable: FileManager.default.isExecutableFile(atPath:))
    }

    // GUI launches do not necessarily inherit the shell PATH. Check bundled
    // layouts explicitly, including the nested CLI shipped by newer ChatGPT.
    static func locate(customPath: String?, environmentPath: String?, isExecutable: (String) -> Bool) -> String? {
        let candidates = [
            customPath,
            "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
            "/Applications/ChatGPT.app/Contents/Resources/codex",
            "/Applications/Codex.app/Contents/Resources/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
        ].compactMap { $0 }

        for path in candidates where isExecutable(path) { return path }

        let pathEntries = environmentPath?.split(separator: ":").map(String.init) ?? []
        for directory in pathEntries {
            let path = URL(fileURLWithPath: directory).appendingPathComponent("codex").path
            if isExecutable(path) { return path }
        }
        return nil
    }
}
