import Foundation
import Testing
@testable import QuotaCore

@Test func notifiesOnlyOnDownwardCrossingOncePerCycle() {
    let reset = Date(timeIntervalSince1970: 500)
    func snapshot(_ remaining: Double) -> QuotaSnapshot {
        QuotaSnapshot(state: .live, source: .appServer, observedAt: .now, windows: [
            QuotaWindow(kind: .primary, usedPercent: 100 - remaining, windowDurationMinutes: 300, resetsAt: reset),
        ])
    }
    var tracker = ThresholdTracker()
    #expect(tracker.events(previous: snapshot(31), current: snapshot(30)).map(\.threshold) == [30])
    #expect(tracker.events(previous: snapshot(30), current: snapshot(29)).isEmpty)
    #expect(tracker.events(previous: snapshot(16), current: snapshot(4)).map(\.threshold) == [15, 5])
    #expect(tracker.events(previous: snapshot(31), current: snapshot(4)).isEmpty)
}

@Test func newResetCycleAllowsThresholdAgain() {
    let oldReset = Date(timeIntervalSince1970: 500)
    let newReset = Date(timeIntervalSince1970: 800)
    func window(_ remaining: Double, reset: Date) -> QuotaWindow {
        QuotaWindow(kind: .primary, usedPercent: 100 - remaining, windowDurationMinutes: 300, resetsAt: reset)
    }
    var tracker = ThresholdTracker()
    let oldAbove = QuotaSnapshot(state: .live, source: .appServer, observedAt: .now, windows: [window(31, reset: oldReset)])
    let oldBelow = QuotaSnapshot(state: .live, source: .appServer, observedAt: .now, windows: [window(29, reset: oldReset)])
    #expect(tracker.events(previous: oldAbove, current: oldBelow).count == 1)

    let newAbove = QuotaSnapshot(state: .live, source: .appServer, observedAt: .now, windows: [window(31, reset: newReset)])
    let newBelow = QuotaSnapshot(state: .live, source: .appServer, observedAt: .now, windows: [window(29, reset: newReset)])
    #expect(tracker.events(previous: newAbove, current: newBelow).count == 1)
}

@Test func firstObservationDoesNotPretendToBeACrossing() {
    let current = QuotaSnapshot(state: .live, source: .appServer, observedAt: .now, windows: [
        QuotaWindow(kind: .primary, usedPercent: 99, windowDurationMinutes: 300, resetsAt: Date(timeIntervalSince1970: 900)),
    ])
    var tracker = ThresholdTracker()
    #expect(tracker.events(previous: nil, current: current).isEmpty)
}
