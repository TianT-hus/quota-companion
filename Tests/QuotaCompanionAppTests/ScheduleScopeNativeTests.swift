import AppKit
import SwiftUI
import Testing
import QuotaCore
@testable import QuotaCompanionApp

@Suite(.serialized) @MainActor
struct ScheduleScopeNativeTests {
    @Test func failedSaveDoesNotChangeScope() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = SecretaryModel(directory: root)
        let event = ScheduleBlock(start: 540,end: 600,title: "Example")
        try model.commitEvent(model.data.resolving(event, on: Date()))
        let before = model.data
        let plan = try model.data.resolving(event, on: Date(), weekdays: [1,3,5])
        try FileManager.default.removeItem(at: root.appendingPathComponent("secretary-v2.json"))
        try FileManager.default.createDirectory(at: root.appendingPathComponent("secretary-v2.json"), withIntermediateDirectories: true)
        #expect(throws: (any Error).self) { try model.commitEvent(plan) }
        #expect(model.data == before)
        #expect(model.data.editingScope(for: event.id, on: Date()).weekdays == nil)
    }
    @Test func nativePartialSelectionScreenshots() async throws {
        guard let path = ProcessInfo.processInfo.environment["QUOTA_SCOPE_PREVIEW"] else { return }
        _ = NSApplication.shared
        let out = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = SecretaryModel(directory: root)
        let date = SecretaryData.date("2026-09-24")!
        let event = ScheduleBlock(start: 540,end: 630,title: "示例：专注工作")
        try model.commitEvent(model.data.resolving(event, on: date))
        try model.commitEvent(model.data.resolving(event, on: date, weekdays: [1,3,4]))
        let reopened = SecretaryModel(directory: root)
        #expect(reopened.data.editingScope(for: event.id, on: date).weekdays == [1,3,4])
        reopened.editEvent(on: date, block: event)
        for increased in [false,true] {
            let copy = Copybook(language: .zhHans)
            let editor = ScheduleEventEditor(secretary: reopened, navigation: SettingsNavigation(), copy: copy)
            let host = NSHostingView(rootView: editor)
            host.appearance = NSAppearance(named: increased ? .accessibilityHighContrastAqua : .aqua)
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: host.fittingSize), styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.contentView = host; window.orderFront(nil)
            try await Task.sleep(for: .milliseconds(200))
            host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try #require(bitmap.representation(using: .png, properties: [:])).write(to: out.appendingPathComponent(increased ? "weekly-high-contrast.png" : "weekly-selection.png"))
            window.close()
        }
    }
}
