import QuotaCore
import SwiftUI

struct PixelCatView: View {
    let snapshot: QuotaSnapshot
    let locale: Locale
    var palette: CompanionPalette = .water
    var textStyle: ChestTextStyle = .whiteInk
    var customTint: QuotaCore.RGBColor? = nil
    var customText: TextPreset? = nil
    var accessibility = CompanionAccessibility()
    @State private var greeting = false
    @State private var greetingTask: Task<Void, Never>?
    private var window: QuotaWindow? { snapshot.state == .unavailable ? nil : snapshot.limitingWindow }
    private var remaining: Double? { window?.remainingPercent }
    private var value: String { remaining.map { "\(Int($0.rounded()))%" } ?? "—" }
    private var texture: FantasyCatTexture { .shared }
    private var colorIndex: Int { FantasyCatTexture.colorIndex(remaining) == 0 ? palette.textureIndex : FantasyCatTexture.colorIndex(remaining) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            sprite(texture.body)
            sprite(fillImages.0).mask(CatFillMask(remaining: remaining))
            sprite(texture.details)
            if greeting {
                sprite(texture.eyeCover)
                sprite(fillImages.1).mask(CatFillMask(remaining: remaining))
                sprite(texture.eyelids)
            }
            ZStack {
                ForEach(0..<8) { index in
                    quotaLabel.foregroundStyle((customText.flatMap { QuotaCore.RGBColor(hexString: $0.outline) } ?? textStyle.outline).color)
                        .offset(x: cos(Double(index) * .pi / 4), y: sin(Double(index) * .pi / 4))
                }
                quotaLabel.foregroundStyle((customText.flatMap { QuotaCore.RGBColor(hexString: $0.text) } ?? textStyle.text).color)
            }
            // Independent glyph copies avoid cumulative shadow growth; no backdrop.
            .frame(width: 48, height: 24, alignment: .top).offset(x: 7, y: 39)
            if snapshot.state != .live {
                Image(systemName: "wifi.slash").font(.system(size: 9, weight: .bold))
                    .foregroundStyle(CompanionTokens.ink).shadow(color: .white, radius: 0.5)
                    .offset(x: 57, y: 12)
            }
            if snapshot.source == .demo {
                Text("D").font(CompanionTokens.mono(6, weight: .bold))
                    .foregroundStyle(CompanionTokens.ink).offset(x: 5, y: 49)
            }
        }
        .frame(width: 72, height: 80)
        .saturation(snapshot.state == .live ? 1 : 0.25)
        .onHover { if $0 { greet() } }
        .onChange(of: remaining) { _, _ in greet() }
        .onDisappear { greetingTask?.cancel(); greeting = false }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(snapshot.state == .unavailable || snapshot.windows.isEmpty ? "Quota unavailable" : snapshot.petLabelWindows.map {
            "\($0.accessibleLabel(locale: locale)), \(Int($0.remainingPercent.rounded()))%"
        }.joined(separator: "; ") + ", " + snapshot.state.rawValue)
    }
    private func sprite(_ image: CGImage) -> some View {
        Image(decorative: image, scale: 1).resizable().interpolation(.none).frame(width: 72, height: 80)
    }
    private var fillImages: (CGImage, CGImage) {
        if FantasyCatTexture.colorIndex(remaining) == 0, let customTint { return texture.customImages(customTint) }
        return (texture.colors[colorIndex], texture.coloredEyeCovers[colorIndex])
    }
    private var quotaLabel: some View {
        VStack(spacing: 1) {
            if snapshot.state == .unavailable || snapshot.windows.isEmpty {
                Text("—")
            } else {
                ForEach(snapshot.petLabelWindows) { item in
                    Text("\(item.compactLabel(locale: locale)):\(Int(item.remainingPercent.rounded()))%")
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
            }
        }
        .font(CompanionTokens.mono(10, weight: .bold))
    }
    private func greet() {
        greetingTask?.cancel()
        guard !accessibility.reduceMotion else { greeting = false; return }
        greeting = true
        greetingTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(160))
            if !Task.isCancelled { greeting = false }
        }
    }
}

struct PetRootView: View {
    @ObservedObject var model: CompanionModel
    var body: some View {
        SelectedCharacterView(model: model, library: model.characterLibrary)
            .frame(width: model.companionSize.petSize.width, height: model.companionSize.petSize.height, alignment: .topLeading)
            .contentShape(PixelCatShape())
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { model.showKeyboardDetails() }
            .help(model.copy.text("悬停查看额度；离开自动收起；拖动移动", "Hover for quota; leave to hide; drag to move"))
    }
}
