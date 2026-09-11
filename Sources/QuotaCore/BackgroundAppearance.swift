import Foundation

public struct RGBColor: Equatable, Sendable {
    public let r: Double
    public let g: Double
    public let b: Double
    public init(_ r: Double, _ g: Double, _ b: Double) { self.r = r; self.g = g; self.b = b }
    public init(hex: UInt) {
        self.init(Double((hex >> 16) & 255) / 255, Double((hex >> 8) & 255) / 255, Double(hex & 255) / 255)
    }
    public func mixed(with other: Self, amount: Double) -> Self {
        let a = min(1, max(0, amount))
        return Self(r * (1-a) + other.r*a, g * (1-a) + other.g*a, b * (1-a) + other.b*a)
    }
    public var luminance: Double {
        func linear(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }
    public func contrast(with other: Self) -> Double {
        (max(luminance, other.luminance) + 0.05) / (min(luminance, other.luminance) + 0.05)
    }
}

public struct BackgroundAnalysis: Equatable, Sendable {
    public let minimum: Double
    public let maximum: Double
    public let mean: Double
    public let detail: Double
    public init(minimum: Double, maximum: Double, mean: Double, detail: Double) {
        self.minimum = minimum; self.maximum = maximum; self.mean = mean; self.detail = detail
    }
}

public struct BackgroundAppearanceKey: Hashable, Sendable {
    public let dark: Bool
    public let highContrast: Bool
    public let reduceTransparency: Bool
    public init(dark: Bool, highContrast: Bool, reduceTransparency: Bool) {
        self.dark = dark; self.highContrast = highContrast; self.reduceTransparency = reduceTransparency
    }
}

public struct BackgroundAppearance: Sendable {
    public let base: RGBColor
    public let text: RGBColor
    public let secondary: RGBColor
    public let track: RGBColor
    public let baseOpacity: Double
    public let imageOpacity: Double
    public let protectionOpacity: Double
    public let darkestBackground: RGBColor
    public let lightestBackground: RGBColor

    public init(analysis: BackgroundAnalysis?, key: BackgroundAppearanceKey) {
        let base = RGBColor(hex: key.dark ? 0x10233C : 0xF4FDFF)
        let text = RGBColor(hex: key.dark ? 0xF4FDFF : 0x10233C)
        let secondary = RGBColor(hex: key.dark ? 0xD5E7EE : 0x344B63)
        let solid = key.highContrast || key.reduceTransparency
        let baseOpacity = solid ? 1.0 : 0.96
        var imageOpacity = 0.0
        if let analysis {
            imageOpacity = analysis.detail > 0.15 ? 0.12 : (analysis.maximum - analysis.minimum > 0.7 ? 0.18 : 0.25)
            if key.dark && analysis.mean > 0.65 { imageOpacity = min(imageOpacity, 0.16) }
            if solid { imageOpacity = min(imageOpacity, 0.08) }
        }
        // Verify against black AND white extremes, not just a sampled average.
        // This also bounds arbitrary desktop content behind the glass material.
        func extremes(protection: Double) -> (RGBColor, RGBColor) {
            let dark = RGBColor(0,0,0).mixed(with: base, amount: baseOpacity)
                .mixed(with: RGBColor(0,0,0), amount: imageOpacity).mixed(with: base, amount: protection)
            let light = RGBColor(1,1,1).mixed(with: base, amount: baseOpacity)
                .mixed(with: RGBColor(1,1,1), amount: imageOpacity).mixed(with: base, amount: protection)
            return (dark, light)
        }
        var protection = 0.0
        let target = key.highContrast ? 7.0 : 4.5
        while protection < 1 {
            let (low, high) = extremes(protection: protection)
            if [text.contrast(with: low), text.contrast(with: high), secondary.contrast(with: low), secondary.contrast(with: high)].min()! >= target { break }
            protection = min(1, protection + 0.05)
        }
        let extremes = extremes(protection: protection)
        self.base = base; self.text = text; self.secondary = secondary
        self.baseOpacity = baseOpacity; self.imageOpacity = imageOpacity
        self.protectionOpacity = protection
        self.darkestBackground = extremes.0; self.lightestBackground = extremes.1
        track = base.mixed(with: text, amount: 0.10)
    }

    public var minimumTextContrast: Double {
        [text.contrast(with: darkestBackground), text.contrast(with: lightestBackground),
         secondary.contrast(with: darkestBackground), secondary.contrast(with: lightestBackground)].min()!
    }

    public func progressColor(remaining: Double, palette: CompanionPalette = .water, customTint: RGBColor? = nil) -> RGBColor {
        let initial = remaining > 30 ? (customTint ?? (palette != .water ? palette.color : RGBColor(hex: 0x287C99))) : RGBColor(hex: remaining <= 5 ? 0xFF5E57 : remaining <= 15 ? 0xFF8A3D : 0xFFB648)
        for step in 0...20 {
            let candidate = initial.mixed(with: text, amount: Double(step) / 20)
            if candidate.contrast(with: track) >= 3 { return candidate }
        }
        return text
    }
}

/// All variants are cached when an image is loaded, not recalculated by the UI clock.
public struct BackgroundAppearances: Sendable {
    private let values: [BackgroundAppearanceKey: BackgroundAppearance]
    public static let standard = BackgroundAppearances(analysis: nil)
    public init(analysis: BackgroundAnalysis?) {
        var values: [BackgroundAppearanceKey: BackgroundAppearance] = [:]
        for dark in [false, true] {
            for high in [false, true] {
                for reduced in [false, true] {
                    let key = BackgroundAppearanceKey(dark: dark, highContrast: high, reduceTransparency: reduced)
                    values[key] = BackgroundAppearance(analysis: analysis, key: key)
                }
            }
        }
        self.values = values
    }
    public subscript(key: BackgroundAppearanceKey) -> BackgroundAppearance { values[key]! }
}
