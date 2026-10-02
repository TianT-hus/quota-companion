import Testing
@testable import QuotaCore

struct CodexCLITests {
    private let bundled = "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex"

    @Test func nestedBundleWithoutShellPath() {
        #expect(CodexCLI.locate(customPath: nil, environmentPath: nil, isExecutable: { $0 == bundled }) == bundled)
    }

    @Test func customPathKeepsPriority() {
        #expect(CodexCLI.locate(customPath: "/custom/codex", environmentPath: nil,
                                isExecutable: { $0 == bundled || $0 == "/custom/codex" }) == "/custom/codex")
    }

    @Test func oldLayoutsStillWork() {
        for path in ["/Applications/ChatGPT.app/Contents/Resources/codex", "/Applications/Codex.app/Contents/Resources/codex", "/opt/homebrew/bin/codex", "/usr/local/bin/codex"] {
            #expect(CodexCLI.locate(customPath: "/missing", environmentPath: nil, isExecutable: { $0 == path }) == path)
        }
    }

    @Test func shellFallbackAndMissingExecutable() {
        #expect(CodexCLI.locate(customPath: nil, environmentPath: "/example/bin:/another/bin",
                                isExecutable: { $0 == "/another/bin/codex" }) == "/another/bin/codex")
        #expect(CodexCLI.locate(customPath: nil, environmentPath: nil, isExecutable: { _ in false }) == nil)
    }
}
