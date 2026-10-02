import AppKit
import QuotaCore
import Testing
@testable import QuotaCompanionApp

@Suite(.serialized)
@MainActor
struct NativeMascotTests {
    @Test func freshInstallHasNoInventedQuotaAndKeepsLegacyPosition() throws {
        _ = NSApplication.shared
        let suite = "quota-migration-test-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        // Match the unchanged controller's initial 72×80 frame, not the screen
        // of whichever other application's key window happens to be active.
        let screen = try #require(NSScreen.screens.first { $0.frame.contains(CGPoint(x: 36, y: 40)) } ?? NSScreen.main)
        let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
        let old = CGRect(x: screen.visibleFrame.maxX - 80, y: screen.visibleFrame.minY + 24, width: 56, height: 56)
        let key = "panelOrigin.\(id)"
        defaults.set(NSStringFromPoint(old.origin), forKey: key)
        defaults.set("preserved-unused-image.png", forKey: "customMascotPath")
        let model = CompanionModel(defaults: defaults, store: SnapshotStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(suite)))
        #expect(model.snapshot.state == .unavailable && model.snapshot.limitingWindow == nil)
        let controller = PanelController(model: model, positionDefaults: defaults, monitorsSystem: false)
        controller.show(); defer { controller.close() }
        #expect(controller.nativeWindow.frame.maxX == old.maxX)
        #expect(controller.nativeWindow.frame.minY == old.minY)
        #expect(defaults.string(forKey: key) == NSStringFromPoint(old.origin))
        #expect(defaults.string(forKey: "customMascotPath") == "preserved-unused-image.png")
        #expect(defaults.string(forKey: "pixelPetOrigin.\(id)") != nil)
    }
    @Test func twoRealPanelsKeepPetFixedForOneHundredCycles() async throws {
        _ = NSApplication.shared
        let suite = "quota-native-test-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SnapshotStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(suite))
        let model = CompanionModel(defaults: defaults, store: store)
        model.snapshot = QuotaSnapshot(state: .live, source: .appServer, observedAt: .now,
                                      windows: Array(QuotaSnapshot.demo().windows.prefix(1)))
        let controller = PanelController(model: model, positionDefaults: defaults, monitorsSystem: false)
        defer { controller.close() }
        controller.show()
        let original = controller.nativeWindow.frame
        #expect(original.size == PetPanelLayout.petSize)
        for _ in 0..<100 {
            model.showExpanded()
            #expect(controller.nativeWindow.frame == original)
            #expect(controller.detailWindow.frame.size == CGSize(width: 300, height: 160))
            #expect(controller.detailWindow.contentView?.bounds.size == controller.detailWindow.frame.size)
            #expect(controller.layoutMilliseconds < 300)
            #expect(controller.detailWindow.isVisible)
            model.collapse()
            #expect(controller.nativeWindow.frame == original)
        }
        try await Task.sleep(for: .milliseconds(320))
        #expect(!controller.detailWindow.isVisible)
        #expect(controller.nativeWindow.backgroundColor == .clear)
        #expect(!controller.nativeWindow.isOpaque && !controller.detailWindow.isOpaque)
        #expect(controller.nativeWindow.contentView?.bounds.size == PetPanelLayout.petSize)
        model.showExpanded(); model.snapshot = .demo()
        try await Task.sleep(for: .milliseconds(320))
        #expect(controller.detailWindow.frame.size == CGSize(width: 300, height: 160))
        #expect(controller.nativeWindow.frame == original)
        model.collapse(); model.showExpanded()
        controller.nativeWindow.contentView?.frame.size = CGSize(width: 50, height: 50)
        try await Task.sleep(for: .milliseconds(350))
        #expect(controller.nativeWindow.contentView?.bounds.size == PetPanelLayout.petSize)
        controller.close()
        let restarted = PanelController(model: CompanionModel(defaults: defaults, store: store), positionDefaults: defaults, monitorsSystem: false)
        restarted.show(); defer { restarted.close() }
        #expect(restarted.nativeWindow.frame == original)
        #expect(!restarted.detailWindow.isVisible)
    }
}
