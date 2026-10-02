import AppKit
import SwiftUI
import Testing
@testable import QuotaCompanionApp

@MainActor private final class StatusTarget229:NSObject {
    var calls=0
    @objc func activate(_ sender:Any?) { calls += 1 }
}
@MainActor private final class Key229:SpeechCredentials {
    var reads=0
    func read() throws -> String { reads += 1; return "fixture" }
    func save(_ value:String) throws {}
}
@Suite(.serialized) @MainActor struct SpeechStatus229Tests {
    private func setup() -> (NSWindow,SpeechStatusButton,StatusTarget229) {
        let w=NSWindow(contentRect:.init(x:240,y:200,width:400,height:200),styleMask:[.titled],backing:.buffered,defer:false)
        w.isReleasedWhenClosed=false
        let b=SpeechStatusButton(frame:.init(x:180,y:110,width:24,height:28)), t=StatusTarget229()
        b.setButtonType(.momentaryPushIn); b.isBordered=false; b.title=""; b.helpText="Click to test. No real request in this test."
        b.target=t; b.action = #selector(StatusTarget229.activate(_:)); w.contentView?.addSubview(b); w.makeKeyAndOrderFront(nil)
        return (w,b,t)
    }
    private func mouse(_ type:NSEvent.EventType,_ w:NSWindow,_ b:NSView) throws -> NSEvent {
        try #require(NSEvent.mouseEvent(with:type,location:b.convert(.init(x:12,y:14),to:nil),modifierFlags:[],timestamp:0,windowNumber:w.windowNumber,context:nil,eventNumber:1,clickCount:1,pressure:type == .leftMouseDown ? 1:0))
    }
    @Test func pointerHasNoRingAndKeyboardKeepsFocus() throws {
        let (w,b,_)=setup(); defer { w.close(); SettingsInputFocus.setKeyboard(true) }
        SettingsInputFocus.setKeyboard(false); w.makeFirstResponder(b)
        #expect(!b.showsKeyboardFocus && b.focusRingType == .none)
        #expect(SpeechStatusButton.visibleHelpCount == 0)
        SettingsInputFocus.setKeyboard(true); #expect(b.showsKeyboardFocus && b.focusRingType == .none)
        SettingsInputFocus.setKeyboard(false); b.isEnabled=false; b.mouseDown(with:try mouse(.leftMouseDown,w,b))
        #expect(!b.showsKeyboardFocus && SpeechStatusButton.visibleHelpCount == 1)
    }
    @Test func tooltipNeverTakesFocusAndActionDispatchesOnce() async throws {
        let (w,b,t)=setup(); defer { b.phase = .unknown; w.close(); SettingsInputFocus.setKeyboard(true) }
        SettingsInputFocus.setKeyboard(true); w.makeFirstResponder(nil); w.makeFirstResponder(b)
        let help=try #require(w.childWindows?.compactMap{$0 as? SpeechStatusHelpPanel}.first)
        #expect(help.ignoresMouseEvents && !help.canBecomeKey && !help.canBecomeMain && w.firstResponder === b)
        b.helpText="Updated status without another click"
        #expect(SpeechStatusButton.visibleHelpCount == 1 && w.firstResponder === b)
        // Target/action is covered here; physical mouse tracking is checked in isolated QA.
        // Do not inject events into XCTest's application loop: it can terminate the runner.
        SettingsInputFocus.setKeyboard(false); _ = b.sendAction(b.action,to:b.target)
        #expect(t.calls == 1 && !b.showsKeyboardFocus && SpeechStatusButton.visibleHelpCount == 0)
        _ = b.sendAction(b.action,to:b.target); #expect(t.calls == 2)
        b.phase = .testing; b.isEnabled=false
        b.mouseDown(with:try mouse(.leftMouseDown,w,b)); #expect(t.calls == 2)
    }
    @Test func hoverDelayDoesNotActivateOrDispatch() async throws {
        let (w,b,t)=setup(); defer { w.close(); SettingsInputFocus.setKeyboard(true) }
        SettingsInputFocus.setKeyboard(false); w.makeFirstResponder(w.contentView)
        let before=w.firstResponder
        let entered=try #require(NSEvent.enterExitEvent(with:.mouseEntered,location:.zero,modifierFlags:[],timestamp:0,windowNumber:w.windowNumber,context:nil,eventNumber:1,trackingNumber:1,userData:nil))
        b.mouseEntered(with:entered)
        #expect(SpeechStatusButton.visibleHelpCount == 0)
        try await Task.sleep(for:.milliseconds(480))
        #expect(SpeechStatusButton.visibleHelpCount == 1 && w.firstResponder === before && t.calls == 0 && !b.showsKeyboardFocus)
        b.mouseExited(with:entered); #expect(SpeechStatusButton.visibleHelpCount == 0)
    }
    @Test func missingConsentReportsReasonWithoutKeyOrRequest() throws {
        let suite="status229-"+UUID().uuidString, defaults=try #require(UserDefaults(suiteName:suite)), key=Key229()
        defer { defaults.removePersistentDomain(forName:suite) }
        let speech=CompanionSpeech(defaults:defaults,credentials:key)
        defer { speech.stop() }
        speech.testConnection(copy:Copybook(language:.zhHans))
        #expect(speech.apiStatus.phase == .failed && speech.apiStatus.detail.contains("配置 API"))
        #expect(key.reads == 0 && !speech.cloudBusy && speech.dialog == nil)
    }
}
