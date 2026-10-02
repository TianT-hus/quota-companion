import Foundation
import Testing
@testable import QuotaCore

@Test func absoluteResetDatesRespectZoneYearAndLanguage() throws {
    let date = try #require(ISO8601DateFormatter().date(from: "2026-12-31T16:43:00Z"))
    let window = QuotaWindow(kind: .secondary, usedPercent: 21, windowDurationMinutes: 10080, resetsAt: date)
    let shanghai = try #require(TimeZone(identifier: "Asia/Shanghai"))
    let utc = try #require(TimeZone(secondsFromGMT: 0))
    #expect(window.resetTimestampText(locale: Locale(identifier: "zh-Hans"), timeZone: shanghai) == "01/01 00:43 重置")
    #expect(window.resetTimestampText(locale: Locale(identifier: "en"), timeZone: utc) == "Resets 12/31 16:43")
    #expect(window.resetTimestampText(locale: Locale(identifier: "zh-Hans"), timeZone: shanghai, full: true).contains("2027/01/01 00:43"))
    #expect(window.resetTimestampText(locale: Locale(identifier: "en"), timeZone: utc, full: true).contains("GMT"))
}

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
