import Foundation

public struct RateLimitWindowPatch: Sendable, Equatable {
    public var usedPercent: Double?
    public var windowDurationMinutes: Int?
    public var resetsAt: Date?

    public init(usedPercent: Double? = nil, windowDurationMinutes: Int? = nil, resetsAt: Date? = nil) {
        self.usedPercent = usedPercent
        self.windowDurationMinutes = windowDurationMinutes
        self.resetsAt = resetsAt
    }
}

public enum PatchValue<Value: Sendable & Equatable>: Sendable, Equatable {
    case absent
    case null
    case value(Value)
}

public struct RateLimitPatch: Sendable, Equatable {
    public var primary: PatchValue<RateLimitWindowPatch>
    public var secondary: PatchValue<RateLimitWindowPatch>

    public init(primary: PatchValue<RateLimitWindowPatch>, secondary: PatchValue<RateLimitWindowPatch>) {
        self.primary = primary
        self.secondary = secondary
    }
}

public enum RateLimitPayloadParser {
    public static func parse(_ data: Data) throws -> RateLimitPatch? {
        let raw = try JSONSerialization.jsonObject(with: data)
        guard let message = raw as? [String: Any] else { return nil }
        let envelope = (message["result"] as? [String: Any]) ?? (message["params"] as? [String: Any]) ?? message
        let bucket: [String: Any]?

        if let buckets = envelope["rateLimitsByLimitId"] as? [String: Any],
           let codex = buckets["codex"] as? [String: Any] {
            bucket = codex
        } else if let compatible = envelope["rateLimits"] as? [String: Any],
                  (compatible["limitId"] as? String ?? "codex") == "codex" {
            bucket = compatible
        } else if (envelope["limitId"] as? String ?? "") == "codex" {
            bucket = envelope
        } else {
            bucket = nil
        }

        guard let bucket else { return nil }
        return RateLimitPatch(
            primary: parseWindow(key: "primary", in: bucket),
            secondary: parseWindow(key: "secondary", in: bucket)
        )
    }

    private static func parseWindow(key: String, in bucket: [String: Any]) -> PatchValue<RateLimitWindowPatch> {
        guard bucket.keys.contains(key) else { return .absent }
        if bucket[key] is NSNull { return .null }
        guard let value = bucket[key] as? [String: Any] else { return .absent }

        let used = (value["usedPercent"] as? NSNumber)?.doubleValue
        let duration = (value["windowDurationMins"] as? NSNumber)?.intValue
        let resetSeconds = (value["resetsAt"] as? NSNumber)?.doubleValue
        let reset = resetSeconds.map(Date.init(timeIntervalSince1970:))
        return .value(RateLimitWindowPatch(usedPercent: used, windowDurationMinutes: duration, resetsAt: reset))
    }
}

public struct RateLimitAccumulator: Sendable {
    private var byKind: [QuotaWindowKind: QuotaWindow] = [:]

    public init(snapshot: QuotaSnapshot? = nil) {
        for window in snapshot?.windows ?? [] { byKind[window.kind] = window }
    }

    public mutating func merge(
        _ patch: RateLimitPatch,
        observedAt: Date = .now,
        source: QuotaDataSource = .appServer
    ) -> QuotaSnapshot? {
        merge(patch.primary, kind: .primary)
        merge(patch.secondary, kind: .secondary)
        guard !byKind.isEmpty else { return nil }
        return QuotaSnapshot(state: .live, source: source, observedAt: observedAt, windows: Array(byKind.values))
    }

    private mutating func merge(_ value: PatchValue<RateLimitWindowPatch>, kind: QuotaWindowKind) {
        switch value {
        case .absent:
            break
        case .null:
            byKind[kind] = nil
        case .value(let patch):
            let current = byKind[kind]
            guard let used = patch.usedPercent ?? current?.usedPercent,
                  let duration = patch.windowDurationMinutes ?? current?.windowDurationMinutes,
                  let reset = patch.resetsAt ?? current?.resetsAt else { return }
            byKind[kind] = QuotaWindow(
                kind: kind,
                usedPercent: used,
                windowDurationMinutes: duration,
                resetsAt: reset
            )
        }
    }
}
