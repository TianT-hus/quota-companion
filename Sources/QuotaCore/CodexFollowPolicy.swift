/// Event-driven process lifecycle, not a poller. Closing a window is not an event.
public struct CodexFollowPolicy: Sendable {
    public enum Action: Equatable, Sendable { case none, launchCompanion, quitCompanion }
    private var previous: Bool?
    public init() {}
    public mutating func observe(codexRunning: Bool) -> Action {
        defer { previous = codexRunning }
        guard previous != codexRunning else { return .none }
        return codexRunning ? .launchCompanion : .quitCompanion
    }
}
