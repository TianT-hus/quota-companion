import SwiftUI

/// Injectable only inside the view tree; never persisted or exposed as a setting.
struct CompanionAccessibilityOptions {
    var reduceMotion: Bool
    var reduceTransparency: Bool
    var contrast: ColorSchemeContrast
}

private struct CompanionAccessibilityKey: EnvironmentKey {
    static let defaultValue: CompanionAccessibilityOptions? = nil
}

extension EnvironmentValues {
    var companionAccessibility: CompanionAccessibilityOptions? {
        get { self[CompanionAccessibilityKey.self] }
        set { self[CompanionAccessibilityKey.self] = newValue }
    }
}

struct CompanionAccessibility: DynamicProperty {
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.accessibilityReduceTransparency) private var systemReduceTransparency
    @Environment(\.colorSchemeContrast) private var systemContrast
    @Environment(\.companionAccessibility) private var override
    var reduceMotion: Bool { override?.reduceMotion ?? systemReduceMotion }
    var reduceTransparency: Bool { override?.reduceTransparency ?? systemReduceTransparency }
    var contrast: ColorSchemeContrast { override?.contrast ?? systemContrast }
}

enum CompanionTokens {
    static let waterGlass = Color(hex: 0xBFEFF7)
    static let waterDepth = Color(hex: 0x72D5E8)
    static let foam = Color(hex: 0xF4FDFF)
    static let accent = Color(hex: 0x287C99)
    static let ink = Color(hex: 0x10233C)
    static let warm = Color(hex: 0xFFB648)
    static let low = Color(hex: 0xFF8A3D)
    static let critical = Color(hex: 0xFF5E57)

    static func color(for remaining: Double) -> Color {
        if remaining <= 5 { return critical }
        if remaining <= 15 { return low }
        if remaining <= 30 { return warm }
        return accent
    }

    static func liquidColor(for remaining: Double) -> Color {
        remaining > 30 ? waterDepth : color(for: remaining)
    }

    static func text(in scheme: ColorScheme) -> Color { scheme == .dark ? foam : ink }
    static func secondaryText(in scheme: ColorScheme, contrast: ColorSchemeContrast) -> Color {
        text(in: scheme).opacity(contrast == .increased ? 0.90 : 0.72)
    }

    static func rounded(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default).monospacedDigit()
    }
}

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8) & 0xff) / 255,
            blue: Double(hex & 0xff) / 255,
            opacity: alpha
        )
    }
}
