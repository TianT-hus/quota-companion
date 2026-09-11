import Foundation
import Testing
@testable import QuotaCore

@Test func compactQuotaLabelsAndResetTimes() {
    let now = Date(timeIntervalSince1970: 100)
    let week = QuotaWindow(kind: .secondary, usedPercent: 21, windowDurationMinutes: 10080, resetsAt: now.addingTimeInterval(6 * 86400 + 12 * 3600))
    let short = QuotaWindow(kind: .primary, usedPercent: 38, windowDurationMinutes: 300, resetsAt: now.addingTimeInterval(2 * 3600 + 18 * 60))
    let snapshot = QuotaSnapshot(state: .live, source: .appServer, observedAt: now, windows: [week, short])
    #expect(snapshot.petLabelWindows == [short, week])
    #expect(snapshot.limitingWindow == short)
    #expect(week.shortResetText(now: now, locale: Locale(identifier: "zh-Hans")) == "6天12时")
    #expect(short.shortResetText(now: now, locale: Locale(identifier: "en")) == "2h18m")
    #expect(short.shortResetText(now: now.addingTimeInterval(99999), locale: Locale(identifier: "zh-Hans")) == "0分0秒")
}

@Test func compactOverlapKeepsPetAndCardAligned() {
    let pet = CGRect(x: 300, y: 200, width: 72, height: 80)
    let layout = PetPanelLayout(pet: pet, windowCount: 2, screen: CGRect(x: 0, y: 0, width: 1000, height: 800))
    #expect(layout.detail.size == PetPanelLayout.detailSize)
    #expect(layout.pet.intersection(layout.detail).width == 36)
    #expect(layout.pet.union(layout.detail).size == CGSize(width: 272, height: 80))
    #expect(layout.contains(CGPoint(x: pet.maxX - 8, y: pet.midY)))
}
