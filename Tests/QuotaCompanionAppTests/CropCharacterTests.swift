import AppKit
import ImageIO
import UniformTypeIdentifiers
import SwiftUI
import Testing
import QuotaCore
@testable import QuotaCompanionApp

@Suite(.serialized) @MainActor
struct CropCharacterTests {
    @Test func fitWholeImageAndPanWithinFrame() throws {
        for image in [CGSize(width: 1000, height: 500), CGSize(width: 500, height: 1000), CGSize(width: 2000, height: 100)] {
            for height in [56.0, 80.0] {
                let viewport = CGSize(width: 200, height: height)
                let minimum = BackgroundComposition.minimumZoom(image: image, viewport: viewport)
                let original = BackgroundComposition(zoom: minimum, opacity: 0.65)
                #expect(minimum > 0 && minimum <= 1)
                #expect(CropGeometry.zoomed(original, factor: 0.01, minimum: minimum).zoom == minimum)
                for delta in [CGSize.zero, CGSize(width: 9999, height: -9999), CGSize(width: -9999, height: 9999)] {
                    let moved = CropGeometry.moved(original, image: image, viewport: viewport, delta: delta)
                    let rect = moved.imageRect(image: image, viewport: viewport)
                    #expect(rect.minX >= -0.000001 && rect.minY >= -0.000001)
                    #expect(rect.maxX <= viewport.width+0.000001 && rect.maxY <= viewport.height+0.000001)
                    #expect(abs(rect.width/rect.height - image.width/image.height) < 0.000001)
                    let restored = try JSONDecoder().decode(BackgroundComposition.self, from: JSONEncoder().encode(moved))
                    #expect(restored == moved && restored.opacity == 0.65)
                    for scale in [1.0, 1.5, 2.0] {
                        let scaled = moved.imageRect(image: image, viewport: CGSize(width: 200*scale, height: height*scale))
                        #expect(abs(scaled.minX-rect.minX*scale) < 0.000001)
                        #expect(abs(scaled.width-rect.width*scale) < 0.000001)
                    }
                }
            }
        }
    }
    @Test func cropGeometryClampsAndPreservesOpacity() {
        let original=BackgroundComposition(x: 0.5, y: 0.5, zoom: 2, opacity: 0.42)
        for doubleRow in [true,false] {
            let crop=CropGeometry.frame(in: CGRect(x: 0, y: 0, width: 520, height: 280), doubleRow: doubleRow)
            #expect(abs(crop.width/crop.height - 200/(doubleRow ? 80.0 : 56.0)) < 0.001)
            for delta in [CGSize(width: 9999,height: -9999), CGSize(width: -9999,height: 9999)] {
                let next=CropGeometry.moved(original, image: CGSize(width: 1000, height: 500), viewport: crop.size, delta: delta)
                let rect=next.imageRect(image: CGSize(width: 1000, height: 500), viewport: crop.size)
                #expect(rect.minX <= 0.000001 && rect.minY <= 0.000001 && rect.maxX >= crop.width-0.000001 && rect.maxY >= crop.height-0.000001)
                #expect(next.opacity == original.opacity)
            }
        }
        #expect(CropGeometry.zoomed(original, factor: 10).zoom == 4)
        #expect(CropGeometry.zoomed(original, factor: 0.01).zoom == 1)
        #expect(CropGeometry.zoomed(original, factor: .nan) == original)
    }

    @Test func packageValidationImportRestartAndRollback() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("character-test-\(UUID())")
        let source=root.appendingPathComponent("source")
        let manifest=CharacterManifest(name: "Test character", label: CharacterLabelRect(x: 12,y: 40,width: 48,height: 24), fillTop: 32, fillBottom: 77)
        try createPackage(at: source, manifest: manifest)
        let valid=try CharacterPackageStore.prepare(folder: source)
        #expect(valid.manifest == manifest)
        let suite="character-tests-\(UUID())"
        // The UUID suite below is the only persistence domain modified by this test.
        let d=UserDefaults(suiteName: suite)!
        defer { d.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        d.set("old-mascot.png", forKey: "customMascotPath")
        let store=SnapshotStore(directory: root.appendingPathComponent("store"))
        let model=CompanionModel(defaults: d, store: store)
        try await finish(model.characterLibrary)
        let snapshot=model.snapshot
        model.characterLibrary.importPackage(source, copy: model.copy)
        try await finish(model.characterLibrary)
        let selected=try #require(model.characterLibrary.selected)
        #expect(selected.manifest.name == "Test character")
        #expect(selected.tinted(QuotaCore.RGBColor(hex: 0xE795A7)) === selected.tinted(QuotaCore.RGBColor(hex: 0xE795A7)))
        let reloaded=CompanionModel(defaults: d, store: store)
        try await finish(reloaded.characterLibrary)
        #expect(reloaded.characterLibrary.selected?.id == selected.id && reloaded.customMascotPath == "old-mascot.png")
        try Data("broken".utf8).write(to: source.appendingPathComponent("base.png"))
        model.characterLibrary.importPackage(source, copy: model.copy)
        try await finish(model.characterLibrary)
        #expect(model.characterLibrary.selected?.id == selected.id && !model.characterLibrary.errorMessage.isEmpty)
        #expect(model.snapshot == snapshot)
        model.characterLibrary.select(nil)
        #expect(model.characterLibrary.selected == nil && model.characterLibrary.characters.count == 1)
        var invalid=manifest; invalid.label.x = -1
        #expect(throws: (any Error).self) { try invalid.validate() }
        try createPackage(at: source, manifest: manifest)
        let original=source.appendingPathComponent("details.png")
        try FileManager.default.removeItem(at: original)
        try FileManager.default.createSymbolicLink(at: original, withDestinationURL: source.appendingPathComponent("base.png"))
        #expect(throws: (any Error).self) { try CharacterPackageStore.prepare(folder: source) }
    }

    @Test func customCharacterNativeStates() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("character-render-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        try createPackage(at: root, manifest: CharacterManifest(name: "Fixture", label: CharacterLabelRect(x: 12,y: 40,width: 48,height: 24), fillTop: 32, fillBottom: 77))
        let character=try ImportedCharacter(id: UUID().uuidString, prepared: CharacterPackageStore.prepare(folder: root))
        let suite="character-render-\(UUID())"
        let d=UserDefaults(suiteName: suite)!
        defer { d.removePersistentDomain(forName: suite) }
        let model=CompanionModel(defaults: d, store: SnapshotStore(directory: root.appendingPathComponent("state")))
        var faces: [NSColor] = []
        var bodies: [Double: NSColor] = [:]
        for remaining in [100.0, 50, 30, 15, 5, 0] {
            for state in [QuotaDataState.live, .stale, .unavailable] {
                model.snapshot=QuotaSnapshot(state: state, source: .demo, observedAt: .now, windows: [QuotaWindow(kind: .primary, usedPercent: 100-remaining, windowDurationMinutes: 300, resetsAt: .now.addingTimeInterval(1000))])
                let view=NSHostingView(rootView: ImportedCharacterView(character: character, model: model))
                let panel=NSPanel(contentRect: CGRect(x: 0,y: 0,width: 72,height: 80), styleMask: .borderless, backing: .buffered, defer: false)
                panel.isOpaque=false; panel.backgroundColor = .clear; panel.contentView=view
                view.layoutSubtreeIfNeeded()
                let bitmap=try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds)); view.cacheDisplay(in: view.bounds, to: bitmap)
                #expect(bitmap.pixelsWide >= 72 && bitmap.pixelsHigh >= 80)
                #expect((bitmap.colorAt(x: 0,y: 0)?.alphaComponent ?? 1) == 0)
                if state == .live {
                    let scale = Double(bitmap.pixelsWide)/72
                    faces.append(try #require(bitmap.colorAt(x: Int(20*scale), y: Int(12*scale))))
                    bodies[remaining] = try #require(bitmap.colorAt(x: Int(20*scale), y: Int(35*scale)))
                }
                panel.close()
            }
        }
        #expect(faces.allSatisfy { $0 == faces.first })
        #expect(bodies[100] != bodies[0])
    }

    @Test func customCharacterCPU() async throws {
        guard ProcessInfo.processInfo.environment["QUOTA_CHARACTER_CPU"] == "1" else { return }
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("character-cpu-\(UUID())")
        let suite="character-cpu-\(UUID())"
        let d=UserDefaults(suiteName: suite)!
        defer { d.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        try createPackage(at: root.appendingPathComponent("source"), manifest: CharacterManifest(name: "CPU fixture", label: CharacterLabelRect(x: 12,y: 40,width: 48,height: 24), fillTop: 32, fillBottom: 77))
        let model=CompanionModel(defaults: d, store: SnapshotStore(directory: root.appendingPathComponent("store")))
        try await finish(model.characterLibrary)
        let source = ProcessInfo.processInfo.environment["QUOTA_APPROVED_CHARACTER"].map { URL(fileURLWithPath: $0) } ?? root.appendingPathComponent("source")
        model.characterLibrary.importPackage(source, copy: model.copy)
        try await finish(model.characterLibrary)
        model.snapshot=QuotaSnapshot(state: .live, source: .demo, observedAt: .now, windows: QuotaSnapshot.demo().windows)
        model.companionSize = .extraLarge
        let panels=PanelController(model: model, positionDefaults: d, monitorsSystem: false)
        panels.show(); defer { panels.close() }
        func cpu() -> Double {
            var u=rusage(); getrusage(RUSAGE_SELF,&u)
            return Double(u.ru_utime.tv_sec+u.ru_stime.tv_sec)+Double(u.ru_utime.tv_usec+u.ru_stime.tv_usec)/1_000_000
        }
        for expanded in [false,true] {
            if expanded { model.showExpanded(); model.holdInteraction(true) }
            try await Task.sleep(for: .seconds(1))
            let start=cpu(), wall=ProcessInfo.processInfo.systemUptime
            try await Task.sleep(for: .seconds(30))
            let result=(cpu()-start)/(ProcessInfo.processInfo.systemUptime-wall)*100
            print("customCharacterCPU expanded=\(expanded) size=extraLarge average=\(result)% (30s isolated Release native panels)")
            #expect(result < (expanded ? 5 : 2))
        }
    }

    private func finish(_ library: CharacterLibrary) async throws {
        for _ in 0..<200 { if !library.isBusy { return }; try await Task.sleep(for: .milliseconds(20)) }
        Issue.record("Character operation exceeded four seconds")
    }
    private func createPackage(at folder: URL, manifest: CharacterManifest) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try JSONEncoder().encode(manifest).write(to: folder.appendingPathComponent("character.json"))
        for name in ["base.png", "fill-mask.png", "details.png"] {
            var bytes=[UInt8](repeating: 0,count: 72*80*4)
            for y in 4..<77 { for x in 10..<62 {
                let include = name == "base.png" || (name == "details.png" ? y < 32 : y >= 32)
                if include { let i=(y*72+x)*4; bytes[i]=225; bytes[i+1]=205; bytes[i+2]=190; bytes[i+3]=255 }
            } }
            let image=try #require(CGImage(width: 72,height: 80,bitsPerComponent: 8,bitsPerPixel: 32,bytesPerRow: 288,space: CGColorSpace(name: CGColorSpace.sRGB)!,bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),provider: CGDataProvider(data: Data(bytes) as CFData)!,decode: nil,shouldInterpolate: false,intent: .defaultIntent))
            let target=try #require(CGImageDestinationCreateWithURL(folder.appendingPathComponent(name) as CFURL,UTType.png.identifier as CFString,1,nil))
            CGImageDestinationAddImage(target,image,nil); #expect(CGImageDestinationFinalize(target))
        }
    }
}
