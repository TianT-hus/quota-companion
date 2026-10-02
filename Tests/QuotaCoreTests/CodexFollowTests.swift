import Testing
@testable import QuotaCore

struct CodexFollowTests {
    @Test func followsProcessTransitionsNotWindowOrManualCompanionQuit() {
        var state = CodexFollowPolicy()
        #expect(state.observe(codexRunning: false) == .quitCompanion)
        #expect(state.observe(codexRunning: false) == .none)
        #expect(state.observe(codexRunning: true) == .launchCompanion)
        #expect(state.observe(codexRunning: true) == .none) // window closed, app still running
        #expect(state.observe(codexRunning: true) == .none) // manual companion quit isn't a restart loop
        #expect(state.observe(codexRunning: false) == .quitCompanion)
        #expect(state.observe(codexRunning: true) == .launchCompanion)
        var login = CodexFollowPolicy()
        #expect(login.observe(codexRunning: true) == .launchCompanion)
    }
}
