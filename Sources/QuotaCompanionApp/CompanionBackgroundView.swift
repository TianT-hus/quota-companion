import AppKit
import QuotaCore
import SwiftUI

struct CompanionBackground {
    let image: NSImage
    let appearances: BackgroundAppearances
}

/// Deliberately light glass: desktop appearance must not darken the reading surface.
struct GlassCardSurface: View {
    let background: CompanionBackground?
    let appearance: BackgroundAppearance
    let solid: Bool
    var composition: BackgroundComposition? = nil
    private let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
    var body: some View {
        GeometryReader { g in
            ZStack {
                LinearGradient(colors: [Color(hex: 0xEFFAFF), Color(hex: 0xD4E8F4), Color(hex: 0xBBD1E2)], startPoint: .top, endPoint: .bottom)
                if let background {
                    if let composition {
                        PositionedBackgroundImage(image: background.image, composition: composition)
                            .opacity(composition.safeOpacity)
                        Color.white.opacity(BackgroundReadability.protection(opacity: composition.safeOpacity, solid: solid, darkestPixel: composition.darkestPixelHex.flatMap(QuotaCore.RGBColor.init(hexString:))))
                    } else {
                        Image(nsImage: background.image).resizable().scaledToFill()
                            .frame(width: g.size.width, height: g.size.height).clipped()
                            .opacity(solid ? 0.04 : min(0.12, appearance.imageOpacity))
                        Color.white.opacity(appearance.protectionOpacity)
                    }
                }
                LinearGradient(stops: [.init(color: .white.opacity(0.65), location: 0), .init(color: .clear, location: 0.26), .init(color: .clear, location: 0.78), .init(color: Color(hex: 0x587894).opacity(0.2), location: 1)], startPoint: .top, endPoint: .bottom)
                shape.strokeBorder(Color(hex: 0x526B85).opacity(0.5), lineWidth: 1)
                shape.inset(by: 1).strokeBorder(.white.opacity(0.92), lineWidth: 1.1)
                shape.inset(by: 2.5).strokeBorder(LinearGradient(colors: [.white.opacity(0.7), .clear, .white.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.8)
            }.clipShape(shape)
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct PositionedBackgroundImage: View {
    let image: NSImage
    let composition: BackgroundComposition
    var body: some View {
        GeometryReader { geometry in
            let rect = composition.imageRect(image: image.size, viewport: geometry.size)
            Image(nsImage: image).resizable().frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
        }.clipped().allowsHitTesting(false)
    }
}

struct GlassControlSurface: View {
    var body: some View {
        Circle().fill(LinearGradient(colors: [Color(hex: 0xF3FCFF), Color(hex: 0xBDD8EC)], startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(Circle().strokeBorder(Color(hex: 0x6B8CA7).opacity(0.6), lineWidth: 0.7))
            .overlay(Circle().inset(by: 1).strokeBorder(.white.opacity(0.85), lineWidth: 0.8))
            .allowsHitTesting(false)
    }
}

private extension Color {
    init(hex: UInt) { self = QuotaCore.RGBColor(hex: hex).color }
}

extension QuotaCore.RGBColor {
    var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: 1) }
}

struct CompanionBackgroundView: View {
    let background: CompanionBackground?
    let appearance: BackgroundAppearance
    var cornerRadius: CGFloat = 24
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                appearance.base.color.opacity(appearance.baseOpacity)
                if let background {
                    Image(nsImage: background.image).resizable().scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                        .opacity(appearance.imageOpacity)
                }
                appearance.base.color.opacity(appearance.protectionOpacity)
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [.white.opacity(0.72), .white.opacity(0.12), .white.opacity(0.4)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.8)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct BackgroundPreview: View {
    @ObservedObject var model: CompanionModel
    @Environment(\.colorScheme) private var scheme
    var accessibility = CompanionAccessibility()
    var body: some View {
        let key = BackgroundAppearanceKey(dark: scheme == .dark, highContrast: accessibility.contrast == .increased,
                                          reduceTransparency: accessibility.reduceTransparency)
        let style = (model.background?.appearances ?? .standard)[key]
        ZStack {
            CompanionBackgroundView(background: model.background, appearance: style)
            VStack(alignment: .leading, spacing: 8) {
                Text(model.copy.text("额度信息始终清晰", "Quota stays readable"))
                    .font(CompanionTokens.rounded(13, weight: .semibold)).foregroundStyle(style.text.color)
                Capsule().fill(style.track.color).frame(height: 5)
                    .overlay(alignment: .leading) { Capsule().fill(style.progressColor(remaining: 70).color).frame(width: 130, height: 5) }
                Text(model.copy.text("仅更换卡片背景，小玩偶与圆球不变", "Only the card background changes"))
                    .font(CompanionTokens.rounded(10)).foregroundStyle(style.secondary.color)
            }.padding(18)
        }
        .frame(height: 104)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}
