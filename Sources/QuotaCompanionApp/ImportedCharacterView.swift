import SwiftUI
import QuotaCore

struct SelectedCharacterView: View {
    @ObservedObject var model: CompanionModel
    @ObservedObject var library: CharacterLibrary
    var body: some View {
        Group {
            if let character = library.selected { ImportedCharacterView(character: character, model: model, renderScale: model.companionSize.scale) }
            else { PixelCatView(snapshot: model.snapshot, locale: model.copy.locale, palette: model.palette, textStyle: model.chestTextStyle, customTint: model.quotaTint, customText: model.customAppearance.chest).scaleEffect(model.companionSize.scale, anchor: .topLeading) }
        }
    }
}

struct ImportedCharacterView: View {
    let character: ImportedCharacter
    @ObservedObject var model: CompanionModel
    var renderScale: Double = 1
    @Environment(\.displayScale) private var displayScale
    private var remaining: Double? { model.snapshot.state == .unavailable ? nil : model.snapshot.limitingWindow?.remainingPercent }
    private var tint: QuotaCore.RGBColor {
        guard let remaining else { return model.quotaTint ?? model.palette.color }
        if remaining <= 5 { return QuotaCore.RGBColor(hex: 0xFF5E57) }
        if remaining <= 15 { return QuotaCore.RGBColor(hex: 0xFF8A3D) }
        if remaining <= 30 { return QuotaCore.RGBColor(hex: 0xFFB648) }
        return model.quotaTint ?? model.palette.color
    }
    var body: some View {
        let manifest=character.manifest
        let height=(Double(manifest.fillBottom-manifest.fillTop)*min(100,max(0,remaining ?? 0))/100).rounded()
        let label=manifest.label
        let textures = character.textures(tint, pixelScale: renderScale*displayScale)
        ZStack(alignment: .topLeading) {
            sprite(textures.base)
            sprite(textures.fill).mask(sprite(textures.mask))
                .mask(alignment: .topLeading) { Rectangle().frame(width: 72*renderScale, height: height*renderScale).offset(y: (Double(manifest.fillBottom)-height)*renderScale) }
            sprite(textures.details)
            ZStack {
                ForEach(0..<8) { i in quotaLabel.foregroundStyle(outline.color).offset(x: cos(Double(i)*Double.pi/4)*renderScale, y: sin(Double(i)*Double.pi/4)*renderScale) }
                quotaLabel.foregroundStyle(text.color)
            }.frame(width: label.width*renderScale, height: label.height*renderScale, alignment: .top).offset(x: label.x*renderScale, y: label.y*renderScale)
            if model.snapshot.state != .live {
                Image(systemName: "wifi.slash").font(.system(size: 9*renderScale, weight: .bold)).foregroundStyle(.white).shadow(color: .black, radius: renderScale).offset(x: 59*renderScale, y: 2*renderScale)
            }
        }.frame(width: 72*renderScale, height: 80*renderScale).saturation(model.snapshot.state == .live ? 1 : 0.25)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(character.manifest.name + ", " + (remaining == nil ? model.copy.text("暂无额度", "Quota unavailable") : model.snapshot.petLabelWindows.map { "\($0.compactLabel(locale: model.copy.locale)) \(Int($0.remainingPercent.rounded()))%" }.joined(separator: ", ")) + ", " + model.snapshot.state.rawValue)
    }
    private var text: QuotaCore.RGBColor { model.customAppearance.chest.flatMap { QuotaCore.RGBColor(hexString: $0.text) } ?? model.chestTextStyle.text }
    private var outline: QuotaCore.RGBColor { model.customAppearance.chest.flatMap { QuotaCore.RGBColor(hexString: $0.outline) } ?? model.chestTextStyle.outline }
    private var quotaLabel: some View {
        VStack(spacing: renderScale) {
            if remaining == nil { Text("—") }
            else { ForEach(model.snapshot.petLabelWindows) { item in
                Text("\(item.compactLabel(locale: model.copy.locale)):\(Int(item.remainingPercent.rounded()))%")
                    .lineLimit(1).minimumScaleFactor(0.8)
            } }
        }.font(CompanionTokens.mono(10*renderScale, weight: .bold))
    }
    private func sprite(_ image: CGImage) -> some View {
        Image(decorative: image, scale: renderScale*displayScale).resizable().interpolation(.none).frame(width: 72*renderScale, height: 80*renderScale)
    }
}
