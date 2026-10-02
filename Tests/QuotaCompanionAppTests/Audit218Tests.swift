import AppKit
import Testing
import QuotaCore
@testable import QuotaCompanionApp

@MainActor private final class SwitchActionCounter: NSObject {
    var count = 0
    @objc func changed(_ sender: NSButton) { count += 1 }
}

@Suite(.serialized) @MainActor struct Audit218Tests {
    @Test func switchTogglesExactlyOnceAndHonorsDisabledState() {
        let control = SettingsCapsuleSwitch(frame: NSRect(x: 0,y: 0,width: 40,height: 24))
        control.setButtonType(.switch); control.title = ""; control.isBordered = false
        let counter = SwitchActionCounter(); control.target = counter; control.action = #selector(SwitchActionCounter.changed(_:))
        for index in 1...6 {
            control.performClick(nil)
            #expect(counter.count == index)
            #expect(control.state == (index.isMultiple(of: 2) ? .off : .on))
        }
        control.isEnabled = false; control.performClick(nil)
        #expect(counter.count == 6 && control.state == .off)
    }

    @Test func nativeSwitchStateSequence() async throws {
        guard let path = ProcessInfo.processInfo.environment["QUOTA_AUDIT_0218_PREVIEW"] else { return }
        let output = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let root = NSView(frame: NSRect(x:0,y:0,width:240,height:90))
        root.wantsLayer = true; root.layer?.backgroundColor = NSColor.white.cgColor
        let control = SettingsCapsuleSwitch(frame: NSRect(x:100,y:33,width:40,height:24))
        control.setButtonType(.switch); control.title = ""; control.isBordered = false
        root.addSubview(control)
        let window = NSWindow(contentRect: root.frame, styleMask:[.titled],backing:.buffered,defer:false)
        window.isReleasedWhenClosed = false; window.contentView = root; window.makeKeyAndOrderFront(nil)
        defer { window.close() }
        for step in 0...7 {
            control.isEnabled = step != 6; control.highContrast = step == 7
            control.state = step == 0 || step == 4 ? .off : .on
            control.focusRingType = step == 1 ? .default : .none // Reproduce the old system checkbox focus mask.
            window.makeFirstResponder([1,2,3,4,7].contains(step) ? control : nil)
            control.highlight(step == 3)
            control.needsDisplay = true
            try await Task.sleep(for: .milliseconds(120)); root.displayIfNeeded()
            let bitmap = try #require(root.bitmapImageRepForCachingDisplay(in:root.bounds))
            root.cacheDisplay(in:root.bounds,to:bitmap)
            try #require(bitmap.representation(using:.png,properties:[:])).write(to:output.appendingPathComponent("switch-\(step).png"))
        }
    }
    @Test func statusMenuLocalizesEveryCommand() {
        #expect(AppDelegate.statusMenuTitles(Copybook(language: .english)) == ["Show Zhaoxi", "Collapse details", "Refresh now", "Today's schedule", "Settings", "Quit Zhaoxi"])
        #expect(AppDelegate.statusMenuTitles(Copybook(language: .zhHans)).count == 6)
    }
    @Test func switchOwnsOnlyOneFocusDrawingPath() {
        let control = SettingsCapsuleSwitch(frame: NSRect(x: 0, y: 0, width: 40, height: 24))
        control.setButtonType(.switch)
        #expect(control.focusRingType == .none)
    }

    @Test func keyboardTraversalSkipsHiddenAncestors() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        let window = NSWindow(contentRect: root.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = root
        defer { window.close() }
        let first = SettingsCapsuleSwitch(frame: NSRect(x: 0,y: 150,width: 40,height: 24))
        let hidden = NSView(frame: NSRect(x: 0,y: 80,width: 100,height: 40))
        let skipped = SettingsCapsuleSwitch(frame: NSRect(x: 0,y: 0,width: 40,height: 24))
        let last = SettingsCapsuleSwitch(frame: NSRect(x: 0,y: 10,width: 40,height: 24))
        hidden.addSubview(skipped); root.addSubview(first); root.addSubview(hidden); root.addSubview(last)
        hidden.isHidden = true
        window.makeFirstResponder(first)
        moveSettingsControlFocus(from: first, backwards: false)
        #expect(window.firstResponder === last)
    }

    @Test func stoppedReminderRefreshCannotCommitLateData() async {
        let provider = FakeReminderStore(), persistence = MemoryReminderPersistence()
        let model = RemindersModel(directory: .temporaryDirectory, provider: provider, persistence: persistence)
        await model.setEnabled(true); await model.select("work", selected: true)
        let before = model.state
        provider.items = [.init(id: "late", listID: "work", title: "Late", completed: false)]
        provider.onFetch = { model.stop() }
        await model.refresh()
        #expect(model.state.cache == before.cache)
        #expect(!model.usable)
        #expect(provider.changed == nil)
    }

    @Test func backgroundApplyFailureKeepsDraftAndSelection() async throws {
        let suite = "audit-background-\(UUID())", root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        let model = CompanionModel(defaults: defaults, store: SnapshotStore(directory: root))
        let draft = BackgroundDraft(image: NSImage(size: NSSize(width: 100,height: 100)), prepared: nil, composition: BackgroundComposition())
        model.backgroundDraft = draft
        model.applyBackgroundDraft(draft, composition: draft.composition)
        for _ in 0..<100 {
            if !model.isImportingBackground { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(model.backgroundDraft?.id == draft.id)
        #expect(model.customBackgroundName == nil && model.background == nil)
        #expect(model.backgroundDialog != nil)
    }
}
