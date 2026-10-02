import AppKit
import SwiftUI
import Testing
import QuotaCore
@testable import QuotaCompanionApp

@Suite(.serialized) @MainActor
struct HDCharacterTests {
    private var folders: (URL,URL)? {
        guard let root = ProcessInfo.processInfo.environment["QUOTA_HD_ASSETS"] else { return nil }
        let url = URL(fileURLWithPath: root)
        return (url.appendingPathComponent("blue-gown-v1"),url.appendingPathComponent("blue-gown-v2"))
    }
    @Test func versionsGeometryAndCache() throws {
        guard let (oldURL,newURL) = folders else { return }
        let old = try CharacterPackageStore.prepare(folder: oldURL), hd = try CharacterPackageStore.prepare(folder: newURL)
        let c = try ImportedCharacter(id: "test",prepared: hd)
        #expect(old.manifest.version == 1 && hd.manifest.version == 2)
        #expect(c.base.width == 288 && c.base.height == 320)
        #expect(old.manifest.label == hd.manifest.label)
        let color = QuotaCore.RGBColor(hex: 0x72D5E8)
        for scale in [1.0,1.5,2,3,4] {
            let a = c.textures(color,pixelScale: scale), b = c.textures(color,pixelScale: scale)
            #expect(a.fill === b.fill && a.base === b.base)
            #expect(a.fill.width == Int(72*scale) && a.mask.height == Int(80*scale))
        }
        for i in 0..<40 { _ = c.textures(QuotaCore.RGBColor(Double(i)/40,0.5,0.6),pixelScale: 4) }
        #expect(c.cachedCombinationCount == 16)
        #expect(c.cachedTextureBytes <= 288*320*4*4*16)
        print("HD cache combinations=\(c.cachedCombinationCount), textureBytes=\(c.cachedTextureBytes)")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("hd-invalid-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.copyItem(at: newURL,to: root)
        try old.fillMask.write(to: root.appendingPathComponent("fill-mask.png"))
        #expect(throws: (any Error).self) { try CharacterPackageStore.prepare(folder: root) }
        try hd.fillMask.write(to: root.appendingPathComponent("fill-mask.png"))
        var bad = hd.manifest; bad.fillTop = 41
        try JSONEncoder().encode(bad).write(to: root.appendingPathComponent("character.json"))
        #expect(throws: (any Error).self) { try CharacterPackageStore.prepare(folder: root) }
        bad.version = 3
        #expect(throws: (any Error).self) { try bad.validate() }
    }
    @Test func nativeComparisonAndStates() async throws {
        guard let (oldURL,newURL) = folders else { return }
        let old = try ImportedCharacter(id: "old",prepared: CharacterPackageStore.prepare(folder: oldURL))
        let hd = try ImportedCharacter(id: "hd",prepared: CharacterPackageStore.prepare(folder: newURL))
        let suite = "hd-render-\(UUID())"
        // Only temporary app data and a dedicated defaults domain are used.
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        let d = UserDefaults(suiteName: suite)!
        defer { d.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        let model = CompanionModel(defaults: d,store: SnapshotStore(directory: root))
        model.chestTextStyle = .goldInk
        let output = ProcessInfo.processInfo.environment["QUOTA_HD_PREVIEW"].map { URL(fileURLWithPath: $0) }
        if let output { try FileManager.default.createDirectory(at: output,withIntermediateDirectories: true) }
        var faces: [NSColor] = []
        for remaining in [100.0,50,30,15,5,0] {
            for state in [QuotaDataState.live,.stale,.unavailable] {
                model.snapshot = QuotaSnapshot(state: state,source: .demo,observedAt: .now,windows: [QuotaWindow(kind: .primary,usedPercent: 100-remaining,windowDurationMinutes: 10080,resetsAt: .now.addingTimeInterval(86400))])
                let bitmap = try await render(ImportedCharacterView(character: hd,model: model,renderScale: 2),size: CGSize(width: 144,height: 160))
                #expect(bitmap.colorAt(x: 0,y: 0)?.alphaComponent == 0)
                let factor = Double(bitmap.pixelsWide)/72
                if state == .live { faces.append(try #require(bitmap.colorAt(x: Int(36*factor),y: Int(14*factor)))) }
                if let output { try bitmap.representation(using: .png,properties: [:])!.write(to: output.appendingPathComponent("hd-\(Int(remaining))-\(state.rawValue).png")) }
            }
        }
        #expect(faces.allSatisfy { $0 == faces.first })
        model.snapshot = QuotaSnapshot(state: .live,source: .demo,observedAt: .now,windows: [QuotaWindow(kind: .primary,usedPercent: 37,windowDurationMinutes: 10080,resetsAt: .now.addingTimeInterval(86400))])
        if let output {
            let comparison = VStack(spacing: 18) {
                Text("蓝花礼裙 · 原生尺寸清晰度对照").font(.system(size: 17,weight: .semibold))
                HStack { Text("尺寸").frame(width: 70); Text("旧版 72×80 素材").frame(width: 180); Text("高清 288×320 素材").frame(width: 180) }.font(.system(size: 12))
                ForEach([1.0,1.5,2.0],id: \.self) { scale in
                    HStack(spacing: 16) {
                        Text(scale == 1 ? "中" : scale == 1.5 ? "大" : "超大").frame(width: 70)
                        ImportedCharacterView(character: old,model: model,renderScale: scale).frame(width: 180,height: 80*scale)
                        ImportedCharacterView(character: hd,model: model,renderScale: scale).frame(width: 180,height: 80*scale)
                    }
                }
                Text("同一造型、相同显示尺寸 · 63% 为示例额度\n原生窗口渲染，不是放大概念图").font(.system(size: 12))
            }.padding(24).frame(width: 540,height: 600)
            for dark in [false,true] {
                let bitmap = try await render(comparison.background(dark ? Color(red: 0.08,green: 0.12,blue: 0.18) : Color(red: 0.94,green: 0.97,blue: 0.99)).foregroundStyle(dark ? .white : .black),size: CGSize(width: 540,height: 600))
                try bitmap.representation(using: .png,properties: [:])!.write(to: output.appendingPathComponent(dark ? "comparison-dark.png" : "comparison-light.png"))
            }
            model.snapshot = QuotaSnapshot(state: .live,source: .demo,observedAt: .now,windows: QuotaSnapshot.demo().windows)
            for scale in [1.0,1.5,2.0] {
                let bitmap = try await render(ImportedCharacterView(character: hd,model: model,renderScale: scale),size: CGSize(width: 72*scale,height: 80*scale))
                try bitmap.representation(using: .png,properties: [:])!.write(to: output.appendingPathComponent("hd-double-\(scale).png"))
            }
        }
        for _ in 0..<200 { if !model.characterLibrary.isBusy { break }; try await Task.sleep(for: .milliseconds(10)) }
        for url in [oldURL,newURL] {
            model.characterLibrary.importPackage(url,copy: model.copy)
            for _ in 0..<200 { if !model.characterLibrary.isBusy { break }; try await Task.sleep(for: .milliseconds(10)) }
        }
        #expect(model.characterLibrary.selected?.manifest.version == 2 && model.characterLibrary.characters.count == 2)
        let chosen = model.characterLibrary.selected?.id
        model.characterLibrary.importPackage(root.appendingPathComponent("missing"),copy: model.copy)
        for _ in 0..<200 { if !model.characterLibrary.isBusy { break }; try await Task.sleep(for: .milliseconds(10)) }
        #expect(model.characterLibrary.selected?.id == chosen)
        let reloaded = CompanionModel(defaults: d,store: SnapshotStore(directory: root))
        for _ in 0..<200 { if !reloaded.characterLibrary.isBusy { break }; try await Task.sleep(for: .milliseconds(10)) }
        #expect(reloaded.characterLibrary.selected?.id == chosen)
        model.characterLibrary.select(nil)
        #expect(model.characterLibrary.selected == nil && model.characterLibrary.characters.count == 2)
    }
    private func render<V: View>(_ view: V,size: CGSize) async throws -> NSBitmapImageRep {
        let host = NSHostingView(rootView: view)
        let panel = NSPanel(contentRect: CGRect(origin: .zero,size: size),styleMask: .borderless,backing: .buffered,defer: false)
        panel.backgroundColor = .clear; panel.isOpaque = false; panel.hasShadow = false; panel.contentView = host
        panel.orderFrontRegardless(); defer { panel.close() }
        try await Task.sleep(for: .milliseconds(40))
        host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds,to: bitmap)
        return bitmap
    }
}
