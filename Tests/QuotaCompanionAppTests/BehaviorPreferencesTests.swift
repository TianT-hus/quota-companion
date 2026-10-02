import AppKit
import SwiftUI
import QuotaCore
import Testing
@testable import QuotaCompanionApp

@Suite(.serialized) @MainActor
struct BehaviorPreferencesTests {
    @Test func renderBehaviorControls() async throws {
        guard let path = ProcessInfo.processInfo.environment["QUOTA_BEHAVIOR_PREVIEW"] else { return }
        let out = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let suite = "behavior-preview-\(UUID())", root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        let model = CompanionModel(defaults: defaults, store: SnapshotStore(directory: root))
        model.language = .zhHans
        if let path = ProcessInfo.processInfo.environment["QUOTA_TOSS_CHARACTER"] {
            while model.characterLibrary.isBusy { try await Task.sleep(for: .milliseconds(20)) }
            model.characterLibrary.importPackage(URL(fileURLWithPath: path), copy: model.copy)
            while model.characterLibrary.isBusy { try await Task.sleep(for: .milliseconds(20)) }
        }
        let views: [(String, AnyView, CGFloat)] = [
            ("speech", AnyView(SpeechPreferences(model: model, speech: model.speech, group: .voice)), 420),
            ("animation", AnyView(CharacterSettings(library: model.characterLibrary, copy: model.copy)), 290),
            ("startup", AnyView(StartupPreferences(model: model, follow: model.codexFollow)), 250)
        ]
        for (name, content, height) in views {
            let host = NSHostingView(rootView: content.padding(20).frame(width: 540, height: height).background(Color(red: 0.97, green: 0.98, blue: 1)).environment(\.colorScheme, .light))
            let panel = NSPanel(contentRect: CGRect(x: 0,y: 0,width: 540,height: height), styleMask: .borderless, backing: .buffered, defer: false)
            panel.contentView = host; panel.orderFrontRegardless()
            try await Task.sleep(for: .milliseconds(100)); host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try #require(bitmap.representation(using: .png, properties: [:])).write(to: out.appendingPathComponent(name + ".png"))
            panel.close()
        }
    }
    @Test func longTitlesFitWithoutTruncationAtEveryScale() {
        for scale in [1.0, 1.5, 2.0] {
            for title in ["工作", "洗漱＋做早餐＋检查 Kiki 的水和粮", "休息／工作收尾＋入睡", "An especially long English task with every word preserved", "第一行\n第二行", String(repeating: "测试", count: 100)] {
                let width = 56 * scale
                let font = NSFont.systemFont(ofSize: 8 * scale, weight: .semibold)
                let fit = SingleLineFit.size(title, font: font, width: width)
                let actual = NSFont(descriptor: font.fontDescriptor, size: fit)!
                let measured = (SingleLineFit.normalized(title) as NSString).size(withAttributes: [.font: actual]).width
                #expect(fit <= font.pointSize && fit > 0)
                #expect(measured <= width + 0.1)
            }
        }
        #expect(CompactHoverMetrics.size == CGSize(width: 150, height: 80))
    }
    @Test func preferencesPersistAndDoNotOptIntoNewServices() throws {
        let suite = "behavior-\(UUID())", root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        let model = CompanionModel(defaults: defaults, store: SnapshotStore(directory: root))
        #expect(!model.codexFollow.enabled && !model.speech.scheduleEnabled)
        #expect(model.characterLibrary.animationFrequency == .natural)
        model.speech.voiceID = "test-unavailable-voice"
        model.speech.rate = 0.4; model.speech.volume = 0.65; model.speech.scheduleEnabled = true
        model.characterLibrary.animationFrequency = .four
        let restored = CompanionModel(defaults: defaults, store: SnapshotStore(directory: root))
        #expect(restored.speech.voiceID == "test-unavailable-voice" && restored.speech.scheduleEnabled)
        #expect(restored.speech.rate == 0.4 && restored.speech.volume == 0.65)
        #expect(restored.characterLibrary.animationFrequency == .four && !restored.codexFollow.enabled)
    }
    @Test func scheduleAnnouncementAndPersistentDelivery() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let date = Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 21, hour: 13))!
        let block = ScheduleBlock(start: 780, end: 1050, title: "工作")
        #expect(CompanionSpeech.announcement(block, chinese: true) == "现在是十三点到十七点半，工作。")
        let secretary = SecretaryModel(directory: root)
        #expect(secretary.saveRows([ScheduleImportRow(days: Set(1...7), block: block)], days: Set(1...7), today: false))
        var deliveries = 0
        secretary.onReminder = { _, _ in deliveries += 1 }
        secretary.setVisible(true)
        secretary.refresh(at: date); secretary.refresh(at: date.addingTimeInterval(60))
        #expect(deliveries == 1)
        let restored = SecretaryModel(directory: root)
        restored.onReminder = { _, _ in deliveries += 1 }
        restored.setVisible(true); restored.refresh(at: date.addingTimeInterval(120))
        #expect(deliveries == 1)
        restored.refresh(at: date.addingTimeInterval(5*3600))
        #expect(deliveries == 1) // no expired catch-up
        secretary.stop(); restored.stop()
    }
}
