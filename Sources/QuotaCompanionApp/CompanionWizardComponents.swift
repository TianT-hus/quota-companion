import AppKit
import SwiftUI
import QuotaCore

enum WizardStyle {
    static let blue = Color(red: 38/255, green: 110/255, blue: 212/255)
    static let secondary = Color(red: 105/255, green: 113/255, blue: 125/255)
    static let line = Color(white: 0.89)
    static let soft = Color(red: 245/255, green: 246/255, blue: 248/255)
    static let pale = Color(red: 240/255, green: 245/255, blue: 253/255)
}
struct WizardButtonStyle: ButtonStyle {
    var primary = false
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 13, weight: .medium)).padding(.horizontal, 16)
            .frame(minHeight: 36).foregroundStyle(enabled ? (primary ? Color.white : ManagementStyle.ink) : WizardStyle.secondary)
            .background(primary && enabled ? WizardStyle.blue : WizardStyle.soft, in: RoundedRectangle(cornerRadius: 8))
            .opacity(configuration.isPressed ? 0.72 : (enabled ? 1 : 0.55)).contentShape(RoundedRectangle(cornerRadius: 8))
    }
}
/// Keep native Button actions for both pointer and AXPress in the nested modal.
/// Dismiss the confirmation before closing its parent so modal loops unwind in order.
struct WizardDiscardConfirmation: View {
    let copy: Copybook
    let onDiscard: () -> Void
    @Environment(\.ownedDismiss) private var dismiss
    var body: some View {
        VStack(alignment:.leading,spacing:20) {
            Text(copy.text("放弃未保存的桌宠？","Discard this companion draft?")).font(.system(size:18,weight:.semibold))
            Text(copy.text("本次选择的素材和编辑内容将被放弃，原始文件不会修改。","This session's selections and edits will be discarded. Original files will not change."))
                .fixedSize(horizontal:false,vertical:true).foregroundStyle(WizardStyle.secondary)
            HStack {
                Button(copy.text("继续编辑","Keep editing")) { dismiss() }
                    .buttonStyle(WizardButtonStyle(primary:true)).keyboardShortcut(.cancelAction).accessibilityIdentifier("wizard.discard.keep")
                Spacer()
                Button(copy.text("放弃","Discard")) { dismiss(); onDiscard() }
                    .buttonStyle(WizardButtonStyle()).accessibilityIdentifier("wizard.discard.confirm")
            }
        }.padding(24).frame(width:400).fixedSize(horizontal:false,vertical:true)
    }
}
struct WizardStepBar: View {
    let titles: [String]; let step: Int; let complete: Bool; let copy: Copybook
    var body: some View {
        GeometryReader { proxy in
            let cell = proxy.size.width / CGFloat(titles.count)
            ZStack(alignment: .topLeading) {
                ForEach(0..<titles.count-1, id: \.self) { index in
                    Rectangle().fill(index < step ? WizardStyle.blue : WizardStyle.line)
                        .frame(width: cell, height: 2).offset(x: cell * (CGFloat(index)+0.5), y: 20)
                }
                HStack(alignment: .top, spacing: 0) {
                    ForEach(titles.indices, id: \.self) { index in
                        VStack(spacing: 10) {
                            ZStack {
                                Circle().fill(index <= step ? (complete && index == step ? .green : WizardStyle.blue) : WizardStyle.line)
                                if index < step || complete { Image(systemName: "checkmark").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white) }
                                else { Text("\(index+1)").font(.system(size: 12, weight: .semibold)).foregroundStyle(index == step ? .white : WizardStyle.secondary) }
                            }.frame(width: 30, height: 30).padding(5)
                                .background(Circle().fill(.white).opacity(index == step && !complete ? 1 : 0))
                                .overlay(Circle().strokeBorder(index == step && !complete ? WizardStyle.blue : .clear, lineWidth: 1))
                            Text(titles[index]).font(.system(size: 12, weight: index == step ? .semibold : .regular))
                                .foregroundStyle(index == step ? WizardStyle.blue : WizardStyle.secondary)
                                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                        }.frame(width: cell).accessibilityElement(children: .ignore)
                            .accessibilityLabel("\(index+1). \(titles[index])")
                            .accessibilityValue(index < step || complete ? copy.text("已完成", "Completed") : index == step ? copy.text("当前步骤", "Current step") : copy.text("未完成", "Not completed"))
                    }
                }
            }
        }.frame(height: 76).accessibilityIdentifier("wizard.progress")
    }
}
struct WizardCheckerboard: View {
    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.98)))
            for y in stride(from: 0.0, to: size.height, by: 12) {
                for x in stride(from: 0.0, to: size.width, by: 12) where (Int(x/12)+Int(y/12)) % 2 == 0 {
                    context.fill(Path(CGRect(x:x,y:y,width:12,height:12)), with: .color(Color(white: 0.94)))
                }
            }
        }.accessibilityHidden(true)
    }
}
struct WizardSourceImage: View {
    let image: CGImage?
    var body: some View {
        ZStack {
            WizardCheckerboard()
            if let image { Image(decorative: image, scale: 1).resizable().interpolation(.high).scaledToFit().padding(14) }
        }.clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
struct WizardImageCanvas: View {
    @ObservedObject var draft: ImageCharacterDraft
    var arranging = false; var showQuota = false; var showBounds = false
    var brush: Double = 12; var erasing = false; var sample: Double = 79
    let copy: Copybook
    @State private var character: ImportedCharacter?
    @State private var stroke: CharacterBrushStroke?
    @State private var dragOrigin: CGPoint?
    private struct RasterKey: Equatable {
        let image: ObjectIdentifier?; let zoom: Double; let offset: CGPoint
        let strokes: [CharacterBrushStroke]; let tint: Bool
    }
    private var rasterKey: RasterKey { .init(image: draft.image.map(ObjectIdentifier.init), zoom: draft.zoom, offset: draft.offset, strokes: draft.strokes, tint: draft.tintEnabled) }
    var body: some View {
        GeometryReader { geometry in
            let scale = geometry.size.width / 288
            ZStack(alignment: .topLeading) {
                WizardCheckerboard()
                if let character {
                    Image(decorative: character.base, scale: 1).resizable()
                    if draft.tintEnabled && showQuota {
                        Image(decorative: character.tinted(.init(hex: 0x72D5E8)), scale: 1).resizable()
                            .mask(Image(decorative: character.fillMask, scale: 1).resizable())
                            .mask(alignment: .bottom) { Rectangle().frame(height: geometry.size.height*sample/100) }
                    }
                }
                if showQuota {
                    Text("\(Int(sample))%")
                        .font(.system(size: min(40, draft.label.height*1.6)*scale, weight: .bold))
                        .foregroundStyle(.white).shadow(color: .black, radius: 1)
                        .frame(width: draft.label.width*4*scale, height: draft.label.height*4*scale, alignment: .top)
                        .overlay(Rectangle().stroke(showBounds ? WizardStyle.blue : .clear, lineWidth: 1))
                        .offset(x: draft.label.x*4*scale, y: draft.label.y*4*scale)
                }
                if let stroke {
                    Path { path in
                        if let first = stroke.points.first { path.move(to: CGPoint(x:first.x*scale,y:first.y*scale)); for p in stroke.points.dropFirst() { path.addLine(to: CGPoint(x:p.x*scale,y:p.y*scale)) } }
                    }.stroke(stroke.erasing ? .gray : WizardStyle.blue.opacity(0.5), style: StrokeStyle(lineWidth: brush*2*scale, lineCap: .round))
                }
            }.clipShape(RoundedRectangle(cornerRadius: 10)).contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                    if arranging {
                        if dragOrigin == nil { dragOrigin = draft.offset }
                        draft.offset = CGPoint(x:(dragOrigin?.x ?? 0)+value.translation.width/scale,y:(dragOrigin?.y ?? 0)+value.translation.height/scale)
                    } else if showBounds && draft.tintEnabled {
                        if stroke == nil { stroke = .init(points: [], radius: brush, erasing: erasing) }
                        stroke?.points.append(CGPoint(x:value.location.x/scale,y:value.location.y/scale))
                    }
                }.onEnded { _ in
                    dragOrigin = nil
                    if let stroke { draft.commitStroke(stroke); self.stroke = nil }
                })
        }.task(id: rasterKey) {
            do { try await Task.sleep(for: .milliseconds(16)); try Task.checkCancellation() } catch { return }
            if let prepared = try? draft.prepared() { character = try? ImportedCharacter(id: "wizard-preview", prepared: prepared) }
            else { character = nil }
        }
        .accessibilityElement(children: .ignore).accessibilityLabel(copy.text("桌宠制作预览", "Companion preview"))
        .accessibilityValue(showQuota ? copy.text("示例额度 \(Int(sample))%", "Sample quota \(Int(sample))%") : copy.text("原图形象", "Original appearance"))
        .accessibilityHint(arranging ? copy.text("可通过右侧滑条调整位置和缩放", "Use the sliders to adjust position and scale") : "")
    }
}
struct WizardPackagePreview: View {
    let character: ImportedCharacter; let quota: Bool; let copy: Copybook
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var playing = false
    static func frameIndex(at time: TimeInterval, durations: [Int]) -> Int {
        let total = durations.reduce(0, +)
        guard total > 0 else { return 0 }
        let position = max(0, time).truncatingRemainder(dividingBy: Double(total)/1000)*1000
        var boundary = 0
        for (index,duration) in durations.enumerated() { boundary += duration; if position < Double(boundary) { return index } }
        return max(0,durations.count-1)
    }
    var body: some View {
        VStack(spacing: 10) {
            TimelineView(.animation(minimumInterval: 0.1, paused: !playing || reduceMotion)) { timeline in
                let frames = character.animationFrames
                let index = Self.frameIndex(at: timeline.date.timeIntervalSinceReferenceDate, durations: character.manifest.animation?.durationsMilliseconds ?? [])
                let frame = playing && !reduceMotion && !frames.isEmpty ? frames[min(index,frames.count-1)] : character
                GeometryReader { geometry in
                    let s = geometry.size.width/72, label=character.manifest.label
                    ZStack(alignment: .topLeading) {
                        WizardCheckerboard()
                        Image(decorative: frame.base, scale: 1).resizable()
                        if quota {
                            Image(decorative: frame.tinted(.init(hex:0x72D5E8)),scale:1).resizable()
                                .mask(Image(decorative:frame.fillMask,scale:1).resizable())
                                .mask(alignment:.topLeading) {
                                    Rectangle().frame(height:Double(character.manifest.fillBottom-character.manifest.fillTop)*0.79*s)
                                        .offset(y:(Double(character.manifest.fillBottom)-Double(character.manifest.fillBottom-character.manifest.fillTop)*0.79)*s)
                                }
                        }
                        Image(decorative: frame.details, scale: 1).resizable()
                        if quota {
                            Text("79%").font(.system(size: 10*s, weight: .bold)).foregroundStyle(.white).shadow(color: .black, radius: 1)
                                .frame(width:label.width*s,height:label.height*s,alignment:.top).offset(x:label.x*s,y:label.y*s)
                        }
                    }.clipShape(RoundedRectangle(cornerRadius: 10))
                }.aspectRatio(72/80, contentMode: .fit)
            }
            if quota && !character.animationFrames.isEmpty {
                Button(playing ? copy.text("暂停动画", "Pause animation") : copy.text("播放动画", "Play animation")) { playing.toggle() }
                    .disabled(reduceMotion).buttonStyle(WizardButtonStyle())
                if reduceMotion { Text(copy.text("减少动态效果已开启，显示静态预览。", "Reduce Motion is on; showing a still preview.")).font(.system(size:11)).foregroundStyle(WizardStyle.secondary) }
            }
        }
    }
}
