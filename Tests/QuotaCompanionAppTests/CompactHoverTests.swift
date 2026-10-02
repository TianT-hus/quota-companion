import AppKit
import SwiftUI
import Testing
import QuotaCore
@testable import QuotaCompanionApp

@Suite(.serialized) @MainActor
struct CompactHoverTests {
    private var appearance: BackgroundAppearance {
        BackgroundAppearances.standard[BackgroundAppearanceKey(dark: false, highContrast: false, reduceTransparency: false)]
    }

    @Test func thinNativeFillAndAnimation() throws {
        let panel = NSPanel(contentRect: CGRect(x: 100, y: 100, width: 150, height: 4), styleMask: .borderless, backing: .buffered, defer: false)
        let view = LiquidProgressCanvas(frame: CGRect(x: 0, y: 0, width: 150, height: 4), style: .compact)
        panel.contentView = view; defer { panel.close() }
        #expect(view.intrinsicContentSize.height == 4)
        for value in [100.0, 79, 50, 30, 15, 5, 0, -10, 150, .nan] {
            view.update(remaining: value, active: true, stale: false, appearance: appearance)
            let expected = value.isFinite ? min(100, max(0, value)) / 100 : 0
            #expect(abs(view.fill.frame.width - 149 * expected) < 0.001)
            #expect(view.fill.frame.height == 3)
            #expect(view.fill.isHidden == (expected == 0))
        }
        view.update(remaining: 50, active: true, stale: false, appearance: appearance)
        let start = try #require(view.shine.animation(forKey: "flow")).beginTime
        view.update(remaining: 50, active: true, stale: false, appearance: appearance)
        #expect(view.shine.animation(forKey: "flow")?.beginTime == start)
        view.update(remaining: 50, active: false, stale: false, appearance: appearance)
        #expect(view.shine.animation(forKey: "flow") == nil)
        view.update(remaining: 50, active: true, stale: true, appearance: appearance)
        #expect(view.shine.animation(forKey: "flow") == nil)
        view.update(remaining: 50, active: true, stale: false, appearance: appearance, highContrast: true)
        #expect(view.shine.animation(forKey: "flow") != nil && view.track.borderWidth == 0.75)
        view.stop(); #expect(view.shine.animation(forKey: "flow") == nil)
        #expect(LiquidProgressCanvas(frame: .zero).intrinsicContentSize.height == 14)
        for scale in [1.0, 1.5, 2.0] {
            view.renderScale = scale
            view.frame.size = CGSize(width: 150 * scale, height: 4 * scale)
            view.update(remaining: 50, active: false, stale: false, appearance: appearance)
            #expect(abs(view.intrinsicContentSize.height - 4 * scale) < 0.001)
            #expect(abs(view.fill.frame.width - 149 * scale / 2) < 0.001)
            #expect(abs(view.fill.frame.height - 3 * scale) < 0.001)
        }
        #expect(CompactHoverMetrics.controlSize == 14)
        #expect(CompactHoverMetrics.controlHitSize >= CompactHoverMetrics.controlSize)
        #expect(CompactHoverMetrics.quotaHeight + CompactHoverMetrics.scheduleHeight + 5 + 2 * CompactHoverMetrics.verticalInset == 80)
    }

    @Test func fixedHeightAndDirections() async throws {
        _ = NSApplication.shared
        let suite = "compact-hover-\(UUID())", root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        let model = CompanionModel(defaults: defaults, store: SnapshotStore(directory: root))
        let controller = PanelController(model: model, positionDefaults: defaults, monitorsSystem: false)
        controller.show(); defer { controller.close() }
        var maximum = 0.0
        for size in CompanionSize.allCases {
            model.companionSize = size
            try await Task.sleep(for: .milliseconds(350))
            let pet = controller.nativeWindow.frame
            for count in 0...3 {
                model.snapshot = .demo()
                if count == 0 { model.snapshot = .unavailable() }
                if count == 1 { model.snapshot.windows = Array(model.snapshot.windows.prefix(1)) }
                if count == 3 { model.snapshot.windows.append(QuotaWindow(kind: .secondary, usedPercent: 25, windowDurationMinutes: 1440, resetsAt: .now)) }
                for _ in 0..<9 {
                    model.showExpanded()
                    #expect(model.detailBaseSize == CGSize(width: 150, height: 80))
                    #expect(abs(controller.detailWindow.frame.height - 80 * max(2, size.scale)) < 0.01)
                    #expect(abs(controller.detailWindow.frame.width - 150 * max(2, size.scale)) < 0.01)
                    #expect(controller.nativeWindow.frame == pet)
                    maximum = max(maximum, controller.layoutMilliseconds)
                    model.collapse()
                }
            }
            // Force each expansion direction using narrow/wide screen configurations.
            let scale = size.scale
            for (screen, origin, direction) in [
                (CGRect(x: 0,y: 0,width: 1000,height: 1000), CGPoint(x: 0,y: 300), DetailDirection.right),
                (CGRect(x: 0,y: 0,width: 1000,height: 1000), CGPoint(x: 1000-72*scale,y: 300), .left),
                (CGRect(x: 0,y: 0,width: 150*scale,height: 600*scale), CGPoint(x: 40*scale,y: 20*scale), .above),
                (CGRect(x: 0,y: 0,width: 150*scale,height: 600*scale), CGPoint(x: 40*scale,y: 520*scale), .below)
            ] {
                let pet = CGRect(origin: origin, size: CGSize(width: 72*scale,height: 80*scale))
                let layout = PetPanelLayout(pet: pet, windowCount: 2, screen: screen, scale: scale, detailSize: CompactHoverMetrics.size)
                #expect(layout.direction == direction && screen.contains(layout.detail))
                #expect(layout.pet == pet && layout.detail.height == pet.height)
                #expect(layout.contains(CGPoint(x: layout.bridge.midX,y: layout.bridge.midY)))
            }
        }
        #expect(maximum < 300)
        print("compact hover 108 programmatic cycles; max internal layout \(maximum) ms; not pointer acceptance")
        model.showDay(); #expect(model.detailBaseSize == CompactHoverMetrics.size && !model.isExpanded)
        model.secretary.page = .todos; #expect(model.detailBaseSize == CompactHoverMetrics.size)
    }

    @Test func nativePreviews() async throws {
        guard let path = ProcessInfo.processInfo.environment["QUOTA_HOVER_PREVIEW"] else { return }
        _ = NSApplication.shared
        let out = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let suite = "compact-render-\(UUID())", root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        let model = CompanionModel(defaults: defaults, store: SnapshotStore(directory: root))
        model.language = .zhHans; model.chestTextStyle = .goldInk
        if let character = ProcessInfo.processInfo.environment["QUOTA_APPROVED_CHARACTER"] {
            for _ in 0..<200 { if !model.characterLibrary.isBusy { break }; try await Task.sleep(for: .milliseconds(10)) }
            model.characterLibrary.importPackage(URL(fileURLWithPath: character), copy: model.copy)
            for _ in 0..<200 { if !model.characterLibrary.isBusy { break }; try await Task.sleep(for: .milliseconds(10)) }
        }
        let date = Calendar.current.date(from: DateComponents(year: 2026,month: 9,day: 17,hour: 15))!
        let parsed = ScheduleParser.parse("每天 13:00–17:30 工作\n每天 17:30–18:30 吃饭＋买菜＋散步")
        #expect(model.secretary.saveRows(parsed.rows, days: Set(1...7), today: false))
        for variant in ["single", "double", "large", "extra-large", "wrap", "wrap-large", "wrap-xl", "wrap-dual", "left", "above", "below", "english-long", "offline", "low", "empty", "error", "high-contrast", "reduce-transparency", "more-windows"] {
            let week = QuotaWindow(kind: .secondary, usedPercent: 21, windowDurationMinutes: 10080, resetsAt: date.addingTimeInterval(561600))
            let short = QuotaWindow(kind: .primary, usedPercent: 38, windowDurationMinutes: 300, resetsAt: date.addingTimeInterval(8280))
            let single = variant == "single" || (variant.hasPrefix("wrap") && variant != "wrap-dual")
            model.snapshot = QuotaSnapshot(state: .live, source: .demo, observedAt: date, windows: single ? [week] : [short,week])
            model.language = variant == "english-long" ? .english : .zhHans
            model.companionSize = variant == "large" || variant == "wrap-large" ? .large : variant == "extra-large" || variant == "wrap-xl" ? .extraLarge : .medium
            model.detailDirection = variant == "left" ? .left : variant == "above" ? .above : variant == "below" ? .below : .right
            if variant == "offline" { model.snapshot.state = .stale }
            if variant == "low" { model.snapshot.windows = [QuotaWindow(kind: .secondary, usedPercent: 95, windowDurationMinutes: 10080, resetsAt: date)] }
            if variant == "more-windows" { model.snapshot.windows.append(QuotaWindow(kind: .secondary, usedPercent: 100, windowDurationMinutes: 1440, resetsAt: date)) }
            if variant == "empty" { model.snapshot = .unavailable() }
            let title = variant == "english-long" ? "Work on a very long project title with details" : variant.hasPrefix("wrap") ? "整理文件／核对结果＋完成归档" : "工作"
            _ = model.secretary.saveRows([ScheduleImportRow(days: Set(1...7), block: ScheduleBlock(start: 780,end: 1050,title: title)), ScheduleImportRow(days: Set(1...7),block: ScheduleBlock(start: 1050,end: 1110,title: "吃饭＋买菜＋散步"))], days: Set(1...7), today: false)
            if variant == "empty" { _ = model.secretary.commit { $0.week = [:]; $0.exceptions = [:] } }
            model.secretary.error = variant == "error" ? "Example save failure" : ""
            let scale = model.companionSize.scale
            let left = model.detailDirection == .left
            let above = model.detailDirection == .above, below = model.detailDirection == .below
            let vertical = above || below
            let w: CGFloat = vertical ? 150*scale : 186*scale, h: CGFloat = vertical ? 168*scale : 80*scale
            let petPoint = CGPoint(x: vertical ? w/2 : left ? 150*scale : 36*scale, y: above ? 128*scale : 40*scale)
            let detailPoint = CGPoint(x: vertical ? w/2 : left ? 75*scale : 111*scale, y: below ? 128*scale : 40*scale)
            let content = ZStack(alignment: .topLeading) {
                CompanionRootView(model: model, previewDate: date).frame(width: 150*scale,height: 80*scale).position(detailPoint)
                PetRootView(model: model).frame(width: 72*scale,height: 80*scale).position(petPoint)
            }.frame(width: w,height: h)
                .environment(\.companionAccessibility, CompanionAccessibilityOptions(reduceMotion: true, reduceTransparency: variant == "reduce-transparency", contrast: variant == "high-contrast" ? .increased : .standard))
            let host = NSHostingView(rootView: content)
            host.sizingOptions = []; host.frame = CGRect(x: 0,y: 0,width: w,height: h)
            let panel = NSPanel(contentRect: host.frame,styleMask: .borderless,backing: .buffered,defer: false)
            panel.isReleasedWhenClosed = false; panel.isOpaque = false; panel.backgroundColor = .clear; panel.contentView = host
            panel.orderFrontRegardless()
            try await Task.sleep(for: .milliseconds(100)); host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds)); host.cacheDisplay(in: host.bounds,to: bitmap)
            try #require(bitmap.representation(using: .png,properties: [:])).write(to: out.appendingPathComponent(variant+"-retina.png"))
            let cg = try #require(bitmap.cgImage)
            for factor in [1, 4] {
                let width = Int(w)*factor, height = Int(h)*factor
                let context = try #require(CGContext(data: nil,width: width,height: height,bitsPerComponent: 8,bytesPerRow: width*4,space: CGColorSpaceCreateDeviceRGB(),bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
                context.interpolationQuality = factor == 1 ? .high : .none
                context.draw(cg,in: CGRect(x: 0,y: 0,width: width,height: height))
                let result = NSBitmapImageRep(cgImage: try #require(context.makeImage()))
                try #require(result.representation(using: .png,properties: [:])).write(to: out.appendingPathComponent(variant+"-\(factor)x.png"))
            }
            panel.close()
        }
    }
}
