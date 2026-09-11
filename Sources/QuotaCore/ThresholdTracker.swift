import Foundation

public struct ThresholdEvent: Equatable, Sendable {
    public let window: QuotaWindow
    public let threshold: Int
}

public struct ThresholdTracker: Codable, Sendable {
    public static let thresholds = [30, 15, 5]
    private var notifiedByCycle: [String: Set<Int>] = [:]

    public init() {}

    public mutating func events(previous: QuotaSnapshot?, current: QuotaSnapshot) -> [ThresholdEvent] {
        var output: [ThresholdEvent] = []
        for window in current.windows {
            let cycle = cycleKey(window)
            let old = previous?.windows.first(where: { $0.kind == window.kind })

            notifiedByCycle = notifiedByCycle.filter { key, _ in
                !key.hasPrefix("\(window.kind.rawValue):") || key == cycle
            }

            guard let old, old.resetsAt == window.resetsAt else { continue }
            for threshold in Self.thresholds where old.remainingPercent > Double(threshold) && window.remainingPercent <= Double(threshold) {
                if !(notifiedByCycle[cycle] ?? []).contains(threshold) {
                    output.append(ThresholdEvent(window: window, threshold: threshold))
                    notifiedByCycle[cycle, default: []].insert(threshold)
                }
            }
        }
        return output
    }

    private func cycleKey(_ window: QuotaWindow) -> String {
        "\(window.kind.rawValue):\(Int(window.resetsAt.timeIntervalSince1970))"
    }
}
