import AppKit
import SwiftUI
import Testing
@testable import QuotaCompanionApp

@MainActor private final class Presentation223: ObservableObject {
    @Published var presented = true
    @Published var nested = false
}
private struct PresentationFixture223: View {
    @ObservedObject var state: Presentation223
    var body: some View {
        Text("Root").ownedSheet(isPresented: $state.presented) {
            Text("Editor").frame(width: 360, height: 240)
                .ownedSheet(isPresented: $state.nested) { Text("Nested").frame(width: 200, height: 100) }
        }
    }
}
private struct ColorPresentationFixture223: View {
    @ObservedObject var state: Presentation223
    var body: some View {
        Text("Root").ownedSheet(isPresented: $state.presented) {
            ColorEditor(copy: Copybook(language: .zhHans), draft: ColorEditorDraft(target: .quota), onSave: { _ in }, onCancel: {})
        }
    }
}

@Suite(.serialized) @MainActor struct Experience223Tests {
    private func window<V: View>(_ view: V, size: CGSize = .init(width: 500, height: 180)) -> NSWindow {
        let window = NSWindow(contentRect: .init(x: 240, y: 220, width: size.width, height: size.height), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: view.frame(width: size.width, height: size.height).environment(\.colorScheme, .light))
        window.makeKeyAndOrderFront(nil)
        return window
    }
    private func all(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(all) }
    @Test func colorEditorUsesStableManualContentSize() async throws {
        let state = Presentation223()
        let parent = window(ColorPresentationFixture223(state: state), size: .init(width:780,height:620))
        defer { state.presented = false; parent.close() }
        try await Task.sleep(for: .milliseconds(350))
        let editor = try #require(parent.childWindows?.first)
        let controller = try #require(editor.contentViewController as? NSHostingController<AnyView>)
        #expect(controller.sizingOptions.isEmpty)
        let size = editor.contentView!.bounds.size
        #expect(abs(size.width - 480) < 1 && size.height > 300 && size.height < 620)
        for _ in 0..<10 { editor.updateConstraintsIfNeeded(); editor.displayIfNeeded() }
        try await Task.sleep(for: .milliseconds(350))
        #expect(editor.contentView!.bounds.size == size)
    }
    @Test func switchesAndPickersShareTrailingEdge() async throws {
        let w = window(VStack {
            SettingsToggle("A long setting name that can wrap", isOn: .constant(true))
            SettingsPicker("Language", selection: .constant("en"), options: [SettingsChoice("en", "English")])
        }.padding(16))
        defer { w.close() }
        try await Task.sleep(for: .milliseconds(150))
        let root = try #require(w.contentView)
        let controls = all(root).filter { $0 is SettingsCapsuleSwitch || $0 is SettingsPopUpButton }
        #expect(controls.count == 2)
        for control in controls { #expect(abs(control.convert(control.bounds, to: root).maxX - 484) < 1) }
    }
    @Test func adjustmentUsesSystemCellAndDisabledState() async throws {
        let w = window(SettingsAdjustmentSlider(value: .constant(0.4), range: 0...1, title: "Rate").disabled(true).padding(16))
        defer { w.close() }
        try await Task.sleep(for: .milliseconds(100))
        let root = try #require(w.contentView)
        let slider = try #require(all(root).compactMap { $0 as? SettingsPercentSlider }.first)
        let cell = try #require(slider.cell)
        #expect(type(of: cell) == NSSliderCell.self)
        #expect(!slider.isEnabled && slider.doubleValue == 0.4)
        #expect(slider.trackFillColor != nil)
    }
    @Test func helpIsSingleAndHasNoNativeTooltip() async throws {
        let w = NSWindow(contentRect: .init(x:240,y:220,width:400,height:180), styleMask:[.titled], backing:.buffered, defer:false)
        w.isReleasedWhenClosed = false; defer { w.close() }
        let first = SpeechStatusButton(frame: .init(x:30,y:40,width:24,height:28))
        let second = SpeechStatusButton(frame: .init(x:100,y:40,width:24,height:28))
        first.helpText = "Current speech status"; second.helpText = "Test API connection. Charges may apply."
        w.contentView?.addSubview(first); w.contentView?.addSubview(second); w.makeKeyAndOrderFront(nil)
        w.makeFirstResponder(first)
        try await Task.sleep(for: .milliseconds(100))
        #expect(SpeechStatusButton.visibleHelpCount == 1 && first.toolTip == nil)
        w.makeFirstResponder(second)
        try await Task.sleep(for: .milliseconds(100))
        #expect(SpeechStatusButton.visibleHelpCount == 1 && second.toolTip == nil)
        w.makeFirstResponder(nil)
        #expect(SpeechStatusButton.visibleHelpCount == 0)
    }
    @Test func explicitAlertParentWinsAndMovesWithParent() throws {
        let parent = window(Text("Parent"), size: .init(width:780,height:620))
        let unrelated = window(Text("Unrelated"), size: .init(width:200,height:100))
        defer { unrelated.close(); parent.close() }
        let alert = NSAlert(); alert.messageText = "Choose an announcement preview"
        alert.addButton(withTitle: "Schedule"); alert.addButton(withTitle: "Cancel")
        alert.layout()
        OwnedDialogs.shared.track(alert.window, parent: parent)
        #expect(alert.window.parent === parent)
        let p = parent.convertToScreen(parent.contentView!.frame)
        #expect(abs(alert.window.frame.midX-p.midX) < 1)
        #expect(abs(alert.window.frame.midY-p.midY) < 1)
        parent.setFrameOrigin(.init(x:260,y:230)); OwnedDialogs.shared.reposition()
        let moved = parent.convertToScreen(parent.contentView!.frame)
        #expect(abs(alert.window.frame.midX-moved.midX) < 1)
        OwnedDialogs.shared.release(alert.window)
        #expect(!OwnedDialogs.shared.hasChild(parent))
    }
    @Test func ownedEditorAndNestedEditorRestoreAndRelease() async throws {
        let state = Presentation223()
        let parent = window(PresentationFixture223(state: state), size: .init(width:780,height:620))
        defer { state.nested = false; state.presented = false; parent.close() }
        try await Task.sleep(for: .milliseconds(350))
        let editor = try #require(parent.childWindows?.first)
        let p = parent.convertToScreen(parent.contentView!.frame)
        #expect(abs(editor.frame.midX-p.midX) < 1 && abs(editor.frame.midY-p.midY) < 1)
        state.nested = true
        try await Task.sleep(for: .milliseconds(300))
        let nested = try #require(editor.childWindows?.first)
        #expect(nested.parent === editor && parent.childWindows?.count == 1)
        state.nested = false
        try await Task.sleep(for: .milliseconds(200))
        #expect(!OwnedDialogs.shared.hasChild(editor))
        state.presented = false
        try await Task.sleep(for: .milliseconds(200))
        #expect(!OwnedDialogs.shared.hasChild(parent))
    }
}
