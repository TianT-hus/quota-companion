import AppKit
import SwiftUI

/// Native font metrics. Content length never changes the font of another field.
enum HoverTypography {
    static func font(_ size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        let descriptor = NSFont.systemFont(ofSize: size, weight: weight).fontDescriptor.addingAttributes([
            .featureSettings: [[NSFontDescriptor.FeatureKey.typeIdentifier: 6,
                               NSFontDescriptor.FeatureKey.selectorIdentifier: 0]]
        ])
        return NSFont(descriptor: descriptor, size: size) ?? .systemFont(ofSize: size, weight: weight)
    }
    static func width(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular) -> CGFloat {
        (SingleLineFit.normalized(text) as NSString).size(withAttributes: [.font: font(size, weight: weight)]).width
    }
    static func size(quota: [(String, String)], schedule: [String], contentWidth: CGFloat, scale: CGFloat, offline: Bool) -> CGFloat {
        max(13, 7 * scale)
    }
    static func secondarySize(scale: CGFloat) -> CGFloat { max(12, 6 * scale) }
}

struct HoverText: View {
    let text: String
    let size: CGFloat
    var weight: NSFont.Weight = .regular
    var body: some View {
        Text(SingleLineFit.normalized(text))
            .font(Font(HoverTypography.font(size, weight: weight)))
            .lineLimit(1).truncationMode(.tail)
            .accessibilityLabel(text).help(text)
    }
}
