import Foundation

public enum QuotaWindowKind: String, Codable, Sendable, CaseIterable {
    case primary
    case secondary
}

public struct QuotaWindow: Codable, Identifiable, Hashable, Sendable {
    public var kind: QuotaWindowKind
    public var usedPercent: Double
    public var windowDurationMinutes: Int
    public var resetsAt: Date

    public init(
        kind: QuotaWindowKind,
        usedPercent: Double,
        windowDurationMinutes: Int,
        resetsAt: Date
    ) {
        self.kind = kind
        self.usedPercent = usedPercent
        self.windowDurationMinutes = windowDurationMinutes
        self.resetsAt = resetsAt
    }

    public var id: String { kind.rawValue }
    public var remainingPercent: Double { min(max(100 - usedPercent, 0), 100) }

    public func compactLabel(locale: Locale = .current) -> String {
        let isChinese = locale.language.languageCode?.identifier == "zh"
        if windowDurationMinutes == 10_080 { return isChinese ? "周" : "7d" }
        if windowDurationMinutes % 1_440 == 0 {
            return "\(windowDurationMinutes / 1_440)d"
        }
        if windowDurationMinutes % 60 == 0 {
            return "\(windowDurationMinutes / 60)h"
        }
        return "\(windowDurationMinutes)m"
    }

    public func accessibleLabel(locale: Locale = .current) -> String {
        let isChinese = locale.language.languageCode?.identifier == "zh"
        if windowDurationMinutes == 10_080 { return isChinese ? "每周额度" : "Weekly quota" }
        if windowDurationMinutes % 1_440 == 0 {
            let days = windowDurationMinutes / 1_440
            return isChinese ? "\(days) 天额度" : "\(days)-day quota"
        }
        if windowDurationMinutes % 60 == 0 {
            let hours = windowDurationMinutes / 60
            return isChinese ? "\(hours) 小时额度" : "\(hours)-hour quota"
        }
        return isChinese ? "\(windowDurationMinutes) 分钟额度" : "\(windowDurationMinutes)-minute quota"
    }
}

public enum QuotaDataState: String, Codable, Sendable {
    case live
    case stale
    case unavailable
}

public enum QuotaDataSource: String, Codable, Sendable {
    case appServer
    case cache
    case demo
    case none
}

public struct QuotaSnapshot: Codable, Equatable, Sendable {
    public var state: QuotaDataState
    public var source: QuotaDataSource
    public var observedAt: Date
    public var windows: [QuotaWindow]

    public init(
        state: QuotaDataState,
        source: QuotaDataSource,
        observedAt: Date,
        windows: [QuotaWindow]
    ) {
        self.state = state
        self.source = source
        self.observedAt = observedAt
        self.windows = windows.sorted { $0.windowDurationMinutes < $1.windowDurationMinutes }
    }

    public var limitingWindow: QuotaWindow? {
        windows.min {
            if $0.remainingPercent == $1.remainingPercent {
                return $0.windowDurationMinutes < $1.windowDurationMinutes
            }
            return $0.remainingPercent < $1.remainingPercent
        }
    }

    public var petLabelWindows: [QuotaWindow] {
        Array(windows.sorted {
            $0.remainingPercent == $1.remainingPercent
                ? $0.windowDurationMinutes < $1.windowDurationMinutes
                : $0.remainingPercent < $1.remainingPercent
        }.prefix(2)).sorted { $0.windowDurationMinutes < $1.windowDurationMinutes }
    }

    public func markedStale() -> QuotaSnapshot {
        QuotaSnapshot(state: windows.isEmpty ? .unavailable : .stale, source: .cache, observedAt: observedAt, windows: windows)
    }

    public static func unavailable(now: Date = .now) -> QuotaSnapshot {
        QuotaSnapshot(state: .unavailable, source: .none, observedAt: now, windows: [])
    }

    public static func demo(now: Date = .now) -> QuotaSnapshot {
        QuotaSnapshot(
            state: .stale,
            source: .demo,
            observedAt: now,
            windows: [
                QuotaWindow(kind: .primary, usedPercent: 32, windowDurationMinutes: 300, resetsAt: now.addingTimeInterval(2 * 3_600 + 41 * 60)),
                QuotaWindow(kind: .secondary, usedPercent: 53, windowDurationMinutes: 10_080, resetsAt: now.addingTimeInterval(3 * 86_400 + 4 * 3_600)),
            ]
        )
    }
}

public enum QuotaColorBand: String, Codable, Sendable {
    case healthy
    case warning
    case low
    case critical

    public static func forRemaining(_ value: Double) -> Self {
        if value <= 5 { return .critical }
        if value <= 15 { return .low }
        if value <= 30 { return .warning }
        return .healthy
    }
}
