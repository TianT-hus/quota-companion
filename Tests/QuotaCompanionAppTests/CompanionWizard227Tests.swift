import AppKit
import SwiftUI
import Testing
import QuotaCore
@testable import QuotaCompanionApp

@Suite(.serialized) @MainActor struct CompanionWizard227Tests {
    let copy = Copybook(language:.zhHans)
    private func waitForLibrary(_ library:CharacterLibrary) async throws {
        for _ in 0..<300 { if !library.isBusy { return }; try await Task.sleep(for:.milliseconds(10)) }
        Issue.record("Library load timed out")
    }
    private func imageFile(_ root:URL) throws -> URL {
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        let url=root.appendingPathComponent("fixture.png")
        try NSBitmapImageRep(cgImage:FantasyCatTexture.shared.body).representation(using:.png,properties:[:])!.write(to:url)
        return url
    }
    @Test func readyImageSavesOnceWithoutSwitchAndSurvivesRestart() async throws {
        let root=URL.temporaryDirectory.appendingPathComponent("wizard227-\(UUID())"), suite="wizard227-\(UUID())"
        let defaults=try #require(UserDefaults(suiteName:suite))
        defer { defaults.removePersistentDomain(forName:suite); try? FileManager.default.removeItem(at:root) }
        let file=try imageFile(root), original=try Data(contentsOf:file)
        let library=CharacterLibrary(directory:root.appendingPathComponent("library"),defaults:defaults); try await waitForLibrary(library)
        let prior=ImageCharacterDraft(); prior.image=FantasyCatTexture.shared.body
        let selected=try library.importPrepared(prior.prepared(),name:"原桌宠",copy:copy); library.select(selected)
        let s=CompanionWizardSession()
        #expect(!s.dirty && s.stepCount == 7 && s.step == 0)
        s.advance(library:library,copy:copy); #expect(s.page == .image && !s.canAdvance)
        s.loadImage(file,result:false); #expect(s.dirty && s.canAdvance)
        s.advance(library:library,copy:copy); #expect(s.page == .purpose)
        s.advance(library:library,copy:copy); #expect(s.page == .arrange && s.step == 3)
        s.source.zoom=0.75; s.source.offset = .init(x:3,y:5)
        s.advance(library:library,copy:copy); #expect(s.page == .quota)
        s.advance(library:library,copy:copy); #expect(s.page == .imageName && !s.canAdvance)
        s.imageName="小棉花"; s.advance(library:library,copy:copy)
        #expect(s.completed && !s.dirty && s.savedCharacter != nil)
        #expect(library.selectedID == selected && library.characters.count == 2)
        s.advance(library:library,copy:copy); #expect(library.characters.count == 2)
        #expect(try Data(contentsOf:file) == original)
        let reloaded=CharacterLibrary(directory:library.storage.directory,defaults:defaults); try await waitForLibrary(reloaded)
        #expect(reloaded.characters.count == 2 && reloaded.selectedID == selected)
        let saved=try #require(s.savedCharacter)
        #expect(reloaded.displayName(for:saved.id,copy:copy) == "小棉花")
        #expect(try reloaded.storage.load(id:saved.id).manifest.version == 4)
    }
    @Test func referenceBranchRetainsBothDraftsAndPrompt() async throws {
        let root=URL.temporaryDirectory.appendingPathComponent("wizard227-\(UUID())"), suite="wizard227-\(UUID())"
        let defaults=try #require(UserDefaults(suiteName:suite))
        defer { defaults.removePersistentDomain(forName:suite); try? FileManager.default.removeItem(at:root) }
        let file=try imageFile(root), library=CharacterLibrary(directory:root.appendingPathComponent("library"),defaults:defaults)
        try await waitForLibrary(library)
        let s=CompanionWizardSession(); s.loadImage(file,result:false)
        s.source.zoom=1.2; s.source.label.x=5
        s.advance(library:library,copy:copy); s.advance(library:library,copy:copy)
        s.purpose = .reference; s.advance(library:library,copy:copy)
        #expect(s.page == .prompt && s.step == 2)
        s.characterDescription="蓝眼睛的猫\n完整尾巴"; s.artStyle="像素画"
        let prompt=s.promptText(copy:copy)
        #expect(prompt.contains(s.characterDescription) && prompt.contains("像素画") && prompt.contains("真正透明") && prompt.contains("PNG"))
        s.advance(library:library,copy:copy); #expect(s.page == .result && !s.canAdvance && s.step == 2)
        s.loadImage(file,result:true); s.result.zoom=0.8
        s.advance(library:library,copy:copy); #expect(s.page == .arrange && s.draft === s.result)
        s.back(); #expect(s.page == .result)
        s.back(); #expect(s.page == .prompt && s.characterDescription.contains("蓝眼睛"))
        s.back(); s.purpose = .ready; s.advance(library:library,copy:copy)
        #expect(s.page == .arrange && s.draft === s.source && s.source.zoom == 1.2 && s.result.zoom == 0.8)
        s.back(); s.back(); s.back(); s.route = .package; s.advance(library:library,copy:copy)
        #expect(s.page == .package && s.stepCount == 5 && s.source.image != nil)
        s.back(); s.route = .image; s.advance(library:library,copy:copy)
        #expect(s.page == .image && s.source.label.x == 5 && s.result.image != nil)
    }
    @Test func loadAndSaveFailureRetainDraftAndCancellationCannotSave() async throws {
        let root=URL.temporaryDirectory.appendingPathComponent("wizard227-\(UUID())"), suite="wizard227-\(UUID())"
        let defaults=try #require(UserDefaults(suiteName:suite))
        defer { defaults.removePersistentDomain(forName:suite); try? FileManager.default.removeItem(at:root) }
        let file=try imageFile(root), blocked=root.appendingPathComponent("not-a-folder")
        try Data("fixture".utf8).write(to:blocked)
        let library=CharacterLibrary(directory:blocked,defaults:defaults); try await waitForLibrary(library)
        let s=CompanionWizardSession(); s.loadImage(file,result:false); let original=s.source.image
        s.loadImage(root.appendingPathComponent("missing.png"),result:false)
        #expect(s.error != nil && s.source.image === original)
        s.previewPage(.imageName); s.imageName="保留草稿"; s.advance(library:library,copy:copy)
        #expect(s.page == .imageName && s.error != nil && s.dirty && s.savedCharacter == nil)
        #expect(s.imageName == "保留草稿" && library.characters.isEmpty)
        s.finish(); s.advance(library:library,copy:copy); s.loadImage(file,result:true)
        #expect(!s.canAdvance && s.result.image == nil && library.characters.isEmpty)
    }
    @Test func packageChecksSaveAndLateReadGuard() async throws {
        let root=URL.temporaryDirectory.appendingPathComponent("wizard227-\(UUID())"), suite="wizard227-\(UUID())"
        let defaults=try #require(UserDefaults(suiteName:suite))
        defer { defaults.removePersistentDomain(forName:suite); try? FileManager.default.removeItem(at:root) }
        let draft=ImageCharacterDraft(); draft.image=FantasyCatTexture.shared.body; draft.name="角色包"
        let store=CharacterPackageStore(directory:root.appendingPathComponent("source")), id=try store.save(draft.prepared())
        let folder=store.directory.appendingPathComponent(id), manifest=try Data(contentsOf:folder.appendingPathComponent("character.json"))
        let library=CharacterLibrary(directory:root.appendingPathComponent("library"),defaults:defaults); try await waitForLibrary(library)
        let s=CompanionWizardSession(); s.route = .package; s.advance(library:library,copy:copy); s.loadPackage(folder)
        #expect(s.loading && !s.canAdvance)
        for _ in 0..<300 { if !s.loading { break }; try await Task.sleep(for:.milliseconds(10)) }
        #expect(s.packageDraft != nil && s.canAdvance)
        s.loadPackage(root.appendingPathComponent("missing"))
        for _ in 0..<300 { if !s.loading { break }; try await Task.sleep(for:.milliseconds(10)) }
        #expect(s.packageDraft != nil && s.error != nil)
        s.advance(library:library,copy:copy); #expect(s.page == .check && s.step == 2)
        s.advance(library:library,copy:copy); s.packageName="导入猫咪"; s.advance(library:library,copy:copy)
        #expect(s.page == .packageDone && library.characters.count == 1 && library.selectedID == nil)
        #expect(try Data(contentsOf:folder.appendingPathComponent("character.json")) == manifest)
        let late=CompanionWizardSession(); late.loadPackage(folder); late.finish()
        try await Task.sleep(for:.milliseconds(150))
        #expect(late.packageDraft == nil && !late.loading && !late.canAdvance)
    }
    @Test func animationTimingPreservesPackageDurations() {
        let d=[1000,125,125,125,125,500,500,500]
        #expect(WizardPackagePreview.frameIndex(at:0.9,durations:d) == 0)
        #expect(WizardPackagePreview.frameIndex(at:1.1,durations:d) == 1)
        #expect(WizardPackagePreview.frameIndex(at:2.75,durations:d) == 7)
        #expect(WizardPackagePreview.frameIndex(at:3.1,durations:d) == 0)
    }
    @Test func nativePageEvidence() async throws {
        guard let path=ProcessInfo.processInfo.environment["QUOTA_WIZARD_0227_PREVIEW"] else { return }
        _ = NSApplication.shared
        let out=URL(fileURLWithPath:path), root=URL.temporaryDirectory.appendingPathComponent("wizard227-render-\(UUID())"), suite="wizard227-render-\(UUID())"
        try FileManager.default.createDirectory(at:out,withIntermediateDirectories:true)
        let defaults=try #require(UserDefaults(suiteName:suite))
        defer { defaults.removePersistentDomain(forName:suite); try? FileManager.default.removeItem(at:root) }
        let model=CompanionModel(defaults:defaults,store:.init(directory:root)); model.language = .zhHans
        defer { model.secretary.stop(); model.reminders.stop(); model.speech.stop() }
        try await waitForLibrary(model.characterLibrary)
        let file=try imageFile(root), example=ImageCharacterDraft(); example.image=FantasyCatTexture.shared.body; example.name="小棉花"
        let cases:[(String,CompanionWizardSession.Page)] = [("01",.choice),("A02",.image),("A03",.purpose),("A04",.prompt),("A05",.result),("A06",.arrange),("A07",.quota),("A07b",.quota),("A08",.imageName),("A09",.imageDone),("B02",.package),("B03",.check),("B04",.packageName),("B05",.packageDone)]
        for language in [AppLanguage.zhHans,.english] {
            model.language=language
            for (id,page) in cases {
                let s=CompanionWizardSession()
                if id.hasPrefix("B") { s.route = .package }
                if id != "01" && id != "A02" && id != "B02" {
                    s.loadImage(file,result:false); s.imageName="小棉花"
                    if [.prompt,.result].contains(page) { s.purpose = .reference; s.loadImage(file,result:true) }
                    s.characterDescription=model.copy.text("奶油色长毛猫，蓝眼睛，坐姿，神情温柔。","A cream-colored longhair cat with blue eyes, sitting calmly.")
                    s.clothing=model.copy.text("不穿衣服，保留蓬松的尾巴。","No clothing; keep the fluffy tail.")
                    s.artStyle=model.copy.text("清晰、细腻的像素画，边缘干净。","Detailed pixel art with clean edges.")
                    try s.acceptPackage(example.prepared(),filename:"示例角色包")
                }
                if id == "A07b" { s.source.tintEnabled=true; s.source.commitStroke(.init(points:[.init(x:144,y:230)],radius:40,erasing:false)) }
                if [.imageDone,.packageDone].contains(page) {
                    s.previewPage(page == .imageDone ? .imageName : .packageName); s.advance(library:model.characterLibrary,copy:model.copy)
                    #expect(s.completed)
                } else { s.previewPage(page) }
                let host=NSHostingView(rootView:NewCompanionWizard(model:model,close:{},session:s).environment(\.colorScheme,.light))
                let window=NSWindow(contentRect:.init(x:0,y:0,width:868,height:728),styleMask:[.titled],backing:.buffered,defer:false)
                window.isReleasedWhenClosed=false; window.contentView=host; window.orderFront(nil)
                try await Task.sleep(for:.milliseconds(250)); host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
                let full=host.superview ?? host
                let bitmap=try #require(full.bitmapImageRepForCachingDisplay(in:full.bounds)); full.cacheDisplay(in:full.bounds,to:bitmap)
                try #require(bitmap.representation(using:.png,properties:[:])).write(to:out.appendingPathComponent("\(language.rawValue)-\(id).png"))
                window.close()
            }
        }
        #expect(!model.codexFollow.enabled && !model.reminders.enabled)
    }
}
