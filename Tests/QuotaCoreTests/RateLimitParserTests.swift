import Foundation
import Testing
@testable import QuotaCore

@Test func parsesCodexBucketAndIgnoresOtherBuckets() throws {
    let data = Data(#"{"result":{"rateLimits":{"limitId":"legacy","primary":{"usedPercent":99,"windowDurationMins":1,"resetsAt":100}},"rateLimitsByLimitId":{"spark":{"limitId":"spark","primary":{"usedPercent":90,"windowDurationMins":60,"resetsAt":100}},"codex":{"limitId":"codex","primary":{"usedPercent":25,"windowDurationMins":300,"resetsAt":200},"secondary":{"usedPercent":48,"windowDurationMins":10080,"resetsAt":300}}}}}"#.utf8)
    let parsed = try RateLimitPayloadParser.parse(data)
    let patch = try #require(parsed)
    var accumulator = RateLimitAccumulator()
    let merged = accumulator.merge(patch, observedAt: Date(timeIntervalSince1970: 10))
    let snapshot = try #require(merged)

    #expect(snapshot.windows.count == 2)
    #expect(snapshot.windows[0].remainingPercent == 75)
    #expect(snapshot.windows[1].windowDurationMinutes == 10_080)
}

@Test func fallsBackToCompatibleRateLimitsField() throws {
    let data = Data(#"{"result":{"rateLimits":{"limitId":"codex","primary":{"usedPercent":10,"windowDurationMins":120,"resetsAt":200},"secondary":null}}}"#.utf8)
    let parsed = try RateLimitPayloadParser.parse(data)
    let patch = try #require(parsed)
    var accumulator = RateLimitAccumulator()
    let merged = accumulator.merge(patch)
    let snapshot = try #require(merged)
    #expect(snapshot.windows.count == 1)
    #expect(snapshot.windows[0].remainingPercent == 90)
}

@Test func sparseNotificationMergesWithoutDeletingAbsentWindow() throws {
    let reset = Date(timeIntervalSince1970: 200)
    let initial = QuotaSnapshot(state: .live, source: .appServer, observedAt: .now, windows: [
        QuotaWindow(kind: .primary, usedPercent: 10, windowDurationMinutes: 300, resetsAt: reset),
        QuotaWindow(kind: .secondary, usedPercent: 20, windowDurationMinutes: 10_080, resetsAt: reset),
    ])
    let data = Data(#"{"method":"account/rateLimits/updated","params":{"rateLimits":{"limitId":"codex","primary":{"usedPercent":35}}}}"#.utf8)
    let parsed = try RateLimitPayloadParser.parse(data)
    let patch = try #require(parsed)
    var accumulator = RateLimitAccumulator(snapshot: initial)
    let merged = accumulator.merge(patch)
    let snapshot = try #require(merged)

    #expect(snapshot.windows.count == 2)
    #expect(snapshot.windows.first(where: { $0.kind == .primary })?.usedPercent == 35)
    #expect(snapshot.windows.first(where: { $0.kind == .secondary })?.usedPercent == 20)
}

@Test func clampsRemainingPercentAndSelectsShorterTie() {
    let reset = Date(timeIntervalSince1970: 200)
    let negative = QuotaWindow(kind: .primary, usedPercent: 120, windowDurationMinutes: 300, resetsAt: reset)
    let over = QuotaWindow(kind: .secondary, usedPercent: -20, windowDurationMinutes: 10_080, resetsAt: reset)
    #expect(negative.remainingPercent == 0)
    #expect(over.remainingPercent == 100)

    let tieLong = QuotaWindow(kind: .secondary, usedPercent: 50, windowDurationMinutes: 10_080, resetsAt: reset)
    let tieShort = QuotaWindow(kind: .primary, usedPercent: 50, windowDurationMinutes: 300, resetsAt: reset)
    let snapshot = QuotaSnapshot(state: .live, source: .appServer, observedAt: .now, windows: [tieLong, tieShort])
    #expect(snapshot.limitingWindow?.kind == .primary)
}
