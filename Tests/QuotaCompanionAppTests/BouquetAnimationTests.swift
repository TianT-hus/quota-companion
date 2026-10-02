import AppKit
import QuartzCore
import ImageIO
import SwiftUI
import Testing
import QuotaCore
@testable import QuotaCompanionApp

@Suite(.serialized) @MainActor
struct BouquetAnimationTests {
    private var folder: URL? {
        ProcessInfo.processInfo.environment["QUOTA_TOSS_CHARACTER"].map { URL(fileURLWithPath: $0) }
    }
    @Test func manifestTimingValidation() throws {
        var m = CharacterManifest(name: "Example", label: .init(x: 12,y: 49,width: 48,height: 23),fillTop: 40,fillBottom: 79)
        m.version = 3
        #expect(throws: (any Error).self) { try m.validate() }
        m.animation = .init(durationsMilliseconds: [375,375,250,375,375,375,375,500])
        try m.validate()
        #expect(m.animation?.keyTimes.count == 9)
        #expect(m.animation?.keyTimes.last == 1)
        m.animation?.durationsMilliseconds[0] = 0
        #expect(throws: (any Error).self) { try m.validate() }
        m.version = 2
        #expect(throws: (any Error).self) { try m.validate() }
    }
    @Test func privatePackageRoundTripAndCache() throws {
        guard let folder else { return }
        let p = try CharacterPackageStore.prepare(folder: folder)
        #expect(p.frames.count == 8 && p.manifest.pixelsPerPoint == 4)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("toss-package-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = CharacterPackageStore(directory: root)
        let id = try store.save(p)
        #expect(try store.load(id: id).frames.count == 8)
        let c = try ImportedCharacter(id: id,prepared: p)
        for i in 0..<20 {
            let color = QuotaCore.RGBColor(Double(i)/20,0.7,0.9)
            _ = c.textures(color,pixelScale: 4)
            for f in c.animationFrames { _ = f.textures(color,pixelScale: 4) }
        }
        #expect(c.cachedTextureBytes <= 64*1024*1024)
        print("Toss dynamic texture cache: \(c.cachedTextureBytes) bytes")
        c.clearTextures(); #expect(c.cachedTextureBytes == 0)
        try FileManager.default.removeItem(at: root.appendingPathComponent(id).appendingPathComponent("frame-4-details.png"))
        #expect(throws: (any Error).self) { try store.load(id: id) }
    }
    @Test func nativeAnimationInterruptAndPreview() async throws {
        guard let folder else { return }
        let c = try ImportedCharacter(id: "preview",prepared: CharacterPackageStore.prepare(folder: folder))
        let view = CharacterAnimationCanvas(frame: CGRect(x: 0,y: 0,width: 144,height: 160))
        let panel = NSPanel(contentRect: view.frame,styleMask: .borderless,backing: .buffered,defer: false)
        panel.backgroundColor = .clear; panel.isOpaque = false; panel.hasShadow = false; panel.contentView = view
        panel.orderFrontRegardless(); defer { view.stop(); panel.close() }
        let color = QuotaCore.RGBColor(hex: 0x72D5E8)
        func configure(_ eligible: Bool, _ remaining: Double = 50) {
            view.configure(character: c,tint: color,remaining: remaining,pixelScale: 4,eligible: eligible)
        }
        configure(true)
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let deadline = try #require(view.scheduledDeadline)
            configure(true, 30); #expect(view.scheduledDeadline == deadline)
            view.playOnceForTesting(); #expect(view.isPlaying)
            let start = view.baseLayer.animation(forKey: "bouquet-toss")?.beginTime
            configure(true, 5)
            #expect(view.baseLayer.animation(forKey: "bouquet-toss")?.beginTime == start)
        }
        configure(false)
        #expect(!view.isPlaying && view.scheduledDeadline == nil)
        #expect(view.baseLayer.animationKeys()?.isEmpty != false)
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            view.configure(character: c, tint: color, remaining: 50, pixelScale: 4, eligible: true, frequency: .once)
            #expect(abs(try #require(view.scheduledDeadline) - CACurrentMediaTime() - 60) < 1)
            let deadline = view.scheduledDeadline
            view.configure(character: c, tint: color, remaining: 40, pixelScale: 4, eligible: true, frequency: .once)
            #expect(view.scheduledDeadline == deadline)
            view.configure(character: c, tint: color, remaining: 40, pixelScale: 4, eligible: true, frequency: .four)
            #expect(abs(try #require(view.scheduledDeadline) - CACurrentMediaTime() - 15) < 1)
            view.configure(character: c, tint: color, remaining: 40, pixelScale: 4, eligible: true, frequency: .continuous)
            #expect(view.isPlaying)
            view.configure(character: c, tint: color, remaining: 40, pixelScale: 4, eligible: false, frequency: .continuous)
            #expect(!view.isPlaying && view.scheduledDeadline == nil)
        }
        configure(true)
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.post(name: NSWorkspace.sessionDidResignActiveNotification,object: nil)
        workspace.post(name: NSWorkspace.didWakeNotification,object: nil)
        #expect(view.scheduledDeadline == nil) // Waking alone must not unlock the session.
        workspace.post(name: NSWorkspace.sessionDidBecomeActiveNotification,object: nil)
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { #expect(view.scheduledDeadline != nil && !view.isPlaying) }
        workspace.post(name: NSWorkspace.screensDidSleepNotification,object: nil)
        #expect(view.scheduledDeadline == nil)
        workspace.post(name: NSWorkspace.screensDidWakeNotification,object: nil)
        for _ in 0..<100 { configure(true); view.playOnceForTesting(); configure(false) }
        #expect(!view.isPlaying)
        for percent in [100.0,50,5,0] {
            configure(false,percent)
            #expect(abs(view.fillClip.frame.height - ((39*percent/100).rounded())/80*160) < 0.001)
        }
        let output = ProcessInfo.processInfo.environment["QUOTA_TOSS_PREVIEW"].map { URL(fileURLWithPath: $0) }
        if let output {
            try FileManager.default.createDirectory(at: output,withIntermediateDirectories: true)
            for scale in [1.0,1.5,2.0] {
                panel.setContentSize(CGSize(width: 72*scale,height: 80*scale))
                view.frame = CGRect(x: 0,y: 0,width: 72*scale,height: 80*scale)
                for percent in [100.0,50,5] {
                    let url = output.appendingPathComponent("toss-\(scale)-\(Int(percent)).gif")
                    let dest = try #require(CGImageDestinationCreateWithURL(url as CFURL,"com.compuserve.gif" as CFString,8,nil))
                    CGImageDestinationSetProperties(dest,[kCGImagePropertyGIFDictionary:[kCGImagePropertyGIFLoopCount:0]] as CFDictionary)
                    for i in 0..<8 {
                        configure(false,percent); view.displayFrameForTesting(i)
                        view.needsLayout = true; view.layoutSubtreeIfNeeded()
                        try await Task.sleep(for: .milliseconds(20))
                        let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
                        view.cacheDisplay(in: view.bounds,to: bitmap)
                        #expect(bitmap.colorAt(x: 0,y: 0)?.alphaComponent == 0)
                        let cg = try #require(bitmap.cgImage)
                        CGImageDestinationAddImage(dest,cg,[kCGImagePropertyGIFDictionary:[kCGImagePropertyGIFDelayTime: Double(c.manifest.animation!.durationsMilliseconds[i])/1000]] as CFDictionary)
                        if scale == 2 && percent == 50 {
                            try bitmap.representation(using: .png,properties: [:])!.write(to: output.appendingPathComponent("native-frame-\(i).png"))
                        }
                    }
                    #expect(CGImageDestinationFinalize(dest))
                }
            }
        }
    }
    @Test func normalCadenceCPU() async throws {
        guard let folder, ProcessInfo.processInfo.environment["QUOTA_TOSS_PERF"] == "1" else { return }
        let c = try ImportedCharacter(id: "perf",prepared: CharacterPackageStore.prepare(folder: folder))
        let view = CharacterAnimationCanvas(frame: CGRect(x: 0,y: 0,width: 144,height: 160))
        let panel = NSPanel(contentRect: view.frame,styleMask: .borderless,backing: .buffered,defer: false)
        panel.contentView = view; panel.orderFrontRegardless()
        defer { view.stop(); panel.close() }
        view.configure(character: c,tint: .init(hex: 0x72D5E8),remaining: 50,pixelScale: 4,eligible: true)
        func cpu() -> Double { var t = timespec(); clock_gettime(CLOCK_PROCESS_CPUTIME_ID,&t); return Double(t.tv_sec)+Double(t.tv_nsec)/1e9 }
        let start = cpu(), wall = Date()
        try await Task.sleep(for: .seconds(120))
        let usage = (cpu()-start)/Date().timeIntervalSince(wall)*100
        print("120 s native canvas normal-cadence CPU: \(usage)% (test process; not full app/WindowServer)")
        #expect(usage < 2)
    }
    @Test func livePresentationReplacesWholeFrames() async throws {
        guard let folder, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let c = try ImportedCharacter(id: "live-presentation",prepared: CharacterPackageStore.prepare(folder: folder))
        let view = CharacterAnimationCanvas(frame: CGRect(x: 0,y: 0,width: 144,height: 160))
        let panel = NSPanel(contentRect: view.frame,styleMask: .borderless,backing: .buffered,defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.contentView = view
        panel.orderFrontRegardless(); defer { view.stop(); panel.close() }
        let tint = QuotaCore.RGBColor(hex: 0x72D5E8)
        view.configure(character: c,tint: tint,remaining: 50,pixelScale: 4,eligible: true)
        view.layoutSubtreeIfNeeded(); view.playOnceForTesting(); CATransaction.flush()
        let expected = c.animationFrames.map { $0.textures(tint,pixelScale: 4).base }
        var seen = Set<Int>()
        for _ in 0..<9 {
            try await Task.sleep(for: .milliseconds(250))
            let contents = try #require(view.baseLayer.presentation()?.contents)
            try #require(CFGetTypeID(contents as CFTypeRef) == CGImage.typeID)
            let image = contents as! CGImage
            let bytes = try #require(image.dataProvider?.data) as Data
            let match = expected.firstIndex { candidate in
                candidate.width == image.width && candidate.height == image.height &&
                candidate.dataProvider?.data as Data? == bytes
            }
            #expect(match != nil, "Presentation must contain one clean source frame, not accumulated images")
            if let match { seen.insert(match) }
        }
        #expect(seen.count >= 3)
        view.configure(character: c,tint: tint,remaining: 50,pixelScale: 4,eligible: false)
        #expect(!view.isPlaying && view.baseLayer.animation(forKey: "bouquet-toss") == nil)
        print("Live CA presentation observed \(seen.count) distinct clean frames; interaction cancels playback")
    }
    @Test func importSwitchRestartAndNativeLabels() async throws {
        guard let folder else { return }
        let name = "toss-library-\(UUID())", root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name); try? FileManager.default.removeItem(at: root) }
        let model = CompanionModel(defaults: defaults,store: SnapshotStore(directory: root))
        func wait(_ library: CharacterLibrary) async { while library.isBusy { try? await Task.sleep(for: .milliseconds(20)) } }
        await wait(model.characterLibrary)
        model.characterLibrary.importPackage(folder,copy: model.copy); await wait(model.characterLibrary)
        let c = try #require(model.characterLibrary.selected)
        #expect(c.manifest.version == 3 && model.characterLibrary.animationEnabled)
        model.characterLibrary.animationEnabled = false
        model.characterLibrary.importPackage(root.appendingPathComponent("missing"),copy: model.copy)
        await wait(model.characterLibrary)
        #expect(model.characterLibrary.selectedID == c.id)
        let reloaded = CompanionModel(defaults: defaults,store: SnapshotStore(directory: root))
        await wait(reloaded.characterLibrary)
        #expect(reloaded.characterLibrary.selectedID == c.id && !reloaded.characterLibrary.animationEnabled)
        model.chestTextStyle = .goldInk
        guard let path = ProcessInfo.processInfo.environment["QUOTA_TOSS_PREVIEW"] else { return }
        let output = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: output,withIntermediateDirectories: true)
        for scale in [1.0,1.5,2.0] {
            for state in [QuotaDataState.live,.stale,.unavailable] {
                model.snapshot = QuotaSnapshot(state: state,source: .demo,observedAt: .now,windows: [QuotaWindow(kind: .primary,usedPercent: 50,windowDurationMinutes: 10080,resetsAt: .now.addingTimeInterval(86400))])
                let host = NSHostingView(rootView: ImportedCharacterView(character: c,model: model,renderScale: scale))
                let panel = NSPanel(contentRect: CGRect(x: 0,y: 0,width: 72*scale,height: 80*scale),styleMask: .borderless,backing: .buffered,defer: false)
                panel.backgroundColor = .clear; panel.isOpaque = false; panel.hasShadow = false; panel.contentView = host
                panel.orderFrontRegardless()
                try await Task.sleep(for: .milliseconds(50)); host.layoutSubtreeIfNeeded()
                func find(_ view: NSView) -> CharacterAnimationCanvas? {
                    if let canvas = view as? CharacterAnimationCanvas { return canvas }
                    return view.subviews.compactMap(find).first
                }
                let canvas = try #require(find(host)); canvas.displayFrameForTesting(3)
                try await Task.sleep(for: .milliseconds(30))
                let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds,to: bitmap)
                try bitmap.representation(using: .png,properties: [:])!.write(to: output.appendingPathComponent("label-\(scale)-\(state.rawValue).png"))
                if state == .live {
                    let dest = try #require(CGImageDestinationCreateWithURL(output.appendingPathComponent("label-animation-\(scale).gif") as CFURL,"com.compuserve.gif" as CFString,8,nil))
                    CGImageDestinationSetProperties(dest,[kCGImagePropertyGIFDictionary:[kCGImagePropertyGIFLoopCount:0]] as CFDictionary)
                    for i in 0..<8 {
                        canvas.displayFrameForTesting(i)
                        try await Task.sleep(for: .milliseconds(25))
                        // cacheDisplay does not clear the transparent pixels of a reused bitmap.
                        let frameBitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                        host.cacheDisplay(in: host.bounds,to: frameBitmap)
                        try #require(frameBitmap.representation(using: .png, properties: [:])).write(to: output.appendingPathComponent("label-\(scale)-frame-\(i).png"))
                        CGImageDestinationAddImage(dest,try #require(frameBitmap.cgImage),[kCGImagePropertyGIFDictionary:[kCGImagePropertyGIFDelayTime:Double(c.manifest.animation!.durationsMilliseconds[i])/1000]] as CFDictionary)
                    }
                    #expect(CGImageDestinationFinalize(dest))
                }
                canvas.stop(); panel.close()
            }
        }
    }
}
