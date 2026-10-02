import AppKit
import SwiftUI
import Testing
import QuotaCore
@testable import QuotaCompanionApp

@Suite(.serialized) @MainActor
struct ApprovedCharacterTests {
    @Test func localPackageAndNativeStates() async throws {
        guard let input = ProcessInfo.processInfo.environment["QUOTA_APPROVED_CHARACTER"] else { return }
        let package = URL(fileURLWithPath: input)
        let prepared = try CharacterPackageStore.prepare(folder: package)
        let character = try ImportedCharacter(id: UUID().uuidString, prepared: prepared)
        #expect(!character.manifest.name.isEmpty)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("approved-character-\(UUID())")
        let suite = "approved-character-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        let model = CompanionModel(defaults: defaults, store: SnapshotStore(directory: root))
        for _ in 0..<200 { if !model.characterLibrary.isBusy { break }; try await Task.sleep(for: .milliseconds(20)) }
        model.characterLibrary.importPackage(package, copy: model.copy)
        for _ in 0..<200 { if !model.characterLibrary.isBusy { break }; try await Task.sleep(for: .milliseconds(20)) }
        #expect(model.characterLibrary.selected?.manifest.name == character.manifest.name)
        let reloaded = CompanionModel(defaults: defaults, store: SnapshotStore(directory: root))
        for _ in 0..<200 { if !reloaded.characterLibrary.isBusy { break }; try await Task.sleep(for: .milliseconds(20)) }
        #expect(reloaded.characterLibrary.selected?.id == model.characterLibrary.selected?.id)

        let output = ProcessInfo.processInfo.environment["QUOTA_APPROVED_PREVIEW"].map { URL(fileURLWithPath: $0) }
        if let output { try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true) }
        var faceColors: [NSColor] = []
        var fillColors: [NSColor] = []
        for remaining in [100.0,50,30,15,5,0] {
            for state in [QuotaDataState.live,.stale,.unavailable] {
                model.snapshot = QuotaSnapshot(state: state, source: .demo, observedAt: .now, windows: [QuotaWindow(kind: .primary, usedPercent: 100-remaining, windowDurationMinutes: 10080, resetsAt: .now.addingTimeInterval(86400))])
                let view = ImportedCharacterView(character: character, model: model)
                let bitmap = try await render(view, size: CGSize(width: 72,height: 80))
                let scale = Double(bitmap.pixelsWide)/72
                #expect(bitmap.colorAt(x: 0,y: 0)?.alphaComponent == 0)
                if state == .live {
                    faceColors.append(try #require(bitmap.colorAt(x: Int(36*scale),y: Int(14*scale))))
                    if remaining == 0 || remaining == 100 { fillColors.append(try #require(bitmap.colorAt(x: Int(25*scale),y: Int(65*scale)))) }
                }
                if let output {
                    let name = "gown-\(Int(remaining))-\(state.rawValue).png"
                    try #require(bitmap.representation(using: .png, properties: [:])).write(to: output.appendingPathComponent(name))
                }
            }
        }
        #expect(faceColors.allSatisfy { $0 == faceColors.first })
        #expect(fillColors.count == 2 && fillColors[0] != fillColors[1])
        model.snapshot = QuotaSnapshot(state: .live, source: .demo, observedAt: .now, windows: [
            QuotaWindow(kind: .primary, usedPercent: 38, windowDurationMinutes: 300, resetsAt: .now.addingTimeInterval(1000)),
            QuotaWindow(kind: .secondary, usedPercent: 21, windowDurationMinutes: 10080, resetsAt: .now.addingTimeInterval(86400))])
        for scale in [1.0, 1.5, 2.0] {
            let size = CGSize(width: 72*scale,height: 80*scale)
            let view = ImportedCharacterView(character: character, model: model).scaleEffect(scale).frame(width: size.width,height: size.height)
            let bitmap = try await render(view, size: size)
            #expect(bitmap.colorAt(x: 0,y: 0)?.alphaComponent == 0)
            if let output { try #require(bitmap.representation(using: .png, properties: [:])).write(to: output.appendingPathComponent("gown-double-\(scale).png")) }
        }
        if let output {
            let paths = [100,50,5].map { output.appendingPathComponent("gown-\($0)-live.png") }
            let images = try paths.map { try #require(NSImage(contentsOf: $0)) }
            let gallery = VStack(alignment: .leading, spacing: 16) {
                Text("蓝花礼裙 · 原生额度效果").font(.system(size: 17,weight: .semibold))
                HStack(alignment: .top, spacing: 24) {
                    ForEach(0..<3) { i in
                        VStack(spacing: 12) {
                            Text("\([100,50,5][i])%").font(.system(size: 13,weight: .semibold))
                            Image(nsImage: images[i]).resizable().interpolation(.none).frame(width: 72,height: 80)
                            Text("72 × 80 pt").font(.system(size: 11))
                            Image(nsImage: images[i]).resizable().interpolation(.none).frame(width: 216,height: 240)
                            Text("3× 细节").font(.system(size: 11))
                        }
                    }
                }
                Text("应用原生渲染 · 示例额度 · 透明角色，无矩形底板").font(.system(size: 12))
            }.padding(20).frame(width: 740,height: 540)
            for dark in [false,true] {
                let bitmap = try await render(gallery.background(dark ? Color(red: 0.09,green: 0.13,blue: 0.2) : Color(red: 0.93,green: 0.96,blue: 0.98)).foregroundStyle(dark ? .white : Color(red: 0.06,green: 0.14,blue: 0.24)), size: CGSize(width: 740,height: 540))
                try #require(bitmap.representation(using: .png, properties: [:])).write(to: output.appendingPathComponent(dark ? "native-gallery-dark.png" : "native-gallery.png"))
            }
        }
        model.characterLibrary.select(nil)
        #expect(model.characterLibrary.selected == nil && model.characterLibrary.characters.count == 1)
    }

    private func render<V: View>(_ view: V, size: CGSize) async throws -> NSBitmapImageRep {
        let hosting = NSHostingView(rootView: view)
        let panel = NSPanel(contentRect: CGRect(origin: .zero,size: size), styleMask: .borderless, backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.contentView = hosting; panel.orderFrontRegardless()
        defer { panel.close() }
        try await Task.sleep(for: .milliseconds(40))
        hosting.layoutSubtreeIfNeeded(); hosting.displayIfNeeded()
        let bitmap = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        return bitmap
    }
}
