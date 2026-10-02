import AppKit
import SwiftUI

/// Measure native glyphs before selecting the font size; never truncate the title.
/// Tiny text is an explicit consequence of the user's fixed-width preference.
enum SingleLineFit {
    static func normalized(_ text: String) -> String {
        text.components(separatedBy: .newlines).joined(separator: " ")
    }
    static func size(_ text: String, font: NSFont, width: CGFloat) -> CGFloat {
        let value = normalized(text) as NSString
        let limit = max(0.001, width - 0.5)
        func measured(_ size: CGFloat) -> CGFloat {
            value.size(withAttributes: [.font: NSFont(descriptor: font.fontDescriptor, size: size) ?? font]).width
        }
        guard measured(font.pointSize) > limit, width > 0 else { return font.pointSize }
        // SF optical sizes and fallback glyphs do not scale perfectly linearly.
        // Search actual native metrics, not just character count or a ratio.
        var low: CGFloat = 0.001, high = font.pointSize
        for _ in 0..<20 {
            let middle = (low + high) / 2
            if measured(middle) <= limit { low = middle } else { high = middle }
        }
        return low
    }
}

struct FittedSingleLineText: View {
    let text: String
    var size: CGFloat = 8
    var weight: NSFont.Weight = .regular
    var monospaced = false
    var alignment: Alignment = .leading
    var body: some View {
        GeometryReader { geometry in
            let font = monospaced ? HoverTypography.font(size, weight: weight) : NSFont.systemFont(ofSize: size, weight: weight)
            Text(SingleLineFit.normalized(text))
                .font(Font(NSFont(descriptor: font.fontDescriptor, size: SingleLineFit.size(text, font: font, width: geometry.size.width)) ?? font))
                .fixedSize(horizontal: true, vertical: true)
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: alignment)
        }.accessibilityElement(children: .ignore).accessibilityLabel(text).help(text)
    }
}
