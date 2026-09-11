import Foundation

public extension RGBColor {
    init?(hexString: String) {
        let value = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = value.hasPrefix("#") ? String(value.dropFirst()) : value
        guard digits.count == 6, digits.allSatisfy({ $0.isASCII && $0.isHexDigit }), let number = UInt(digits, radix: 16) else { return nil }
        self.init(hex: number)
    }
    var hexString: String {
        func byte(_ x: Double) -> Int { Int((min(1, max(0, x.isFinite ? x : 0)) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(r), byte(g), byte(b))
    }
    static func rgbStrings(_ values: [String]) -> RGBColor? {
        guard values.count == 3 else { return nil }
        let bytes = values.compactMap { Int($0) }
        guard bytes.count == 3, bytes.allSatisfy({ (0...255).contains($0) }) else { return nil }
        return RGBColor(Double(bytes[0])/255, Double(bytes[1])/255, Double(bytes[2])/255)
    }
}

public struct ColorPreset: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var hex: String
    public init(id: UUID = UUID(), name: String, hex: String) { self.id = id; self.name = name; self.hex = hex }
}
public struct TextPreset: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var text: String
    public var outline: String
    public init(id: UUID = UUID(), name: String, text: String, outline: String) {
        self.id = id; self.name = name; self.text = text; self.outline = outline
    }
}

/// Center coordinates refer to the image; clamping occurs per viewport, not on the saved focal point.
public struct BackgroundComposition: Codable, Equatable, Sendable {
    public var x: Double = 0.5
    public var y: Double = 0.5
    public var zoom: Double = 1
    public var opacity: Double = 0.12
    public var darkestPixelHex: String? = nil
    public init(x: Double = 0.5, y: Double = 0.5, zoom: Double = 1, opacity: Double = 0.12) {
        self.x = x; self.y = y; self.zoom = zoom; self.opacity = opacity
    }
    public func imageRect(image: CGSize, viewport: CGSize) -> CGRect {
        guard image.width > 0, image.height > 0, viewport.width > 0, viewport.height > 0 else { return .zero }
        let scale = max(viewport.width/image.width, viewport.height/image.height) * bounded(zoom, Self.minimumZoom(image: image, viewport: viewport)...4, 1)
        let w = image.width * scale, h = image.height * scale
        let left = w < viewport.width ? (viewport.width-w)*(1-bounded(x, 0...1, 0.5)) : min(0, max(viewport.width-w, viewport.width/2 - bounded(x, 0...1, 0.5)*w))
        let top = h < viewport.height ? (viewport.height-h)*(1-bounded(y, 0...1, 0.5)) : min(0, max(viewport.height-h, viewport.height/2 - bounded(y, 0...1, 0.5)*h))
        return CGRect(x: left, y: top, width: w, height: h)
    }
    public var safeOpacity: Double { bounded(opacity, 0...1, 0.12) }
    public static func minimumZoom(image: CGSize, viewport: CGSize) -> Double {
        guard image.width > 0, image.height > 0, viewport.width > 0, viewport.height > 0 else { return 1 }
        let sx = viewport.width/image.width, sy = viewport.height/image.height
        return min(sx, sy)/max(sx, sy)
    }
    private func bounded(_ n: Double, _ range: ClosedRange<Double>, _ fallback: Double) -> Double {
        min(range.upperBound, max(range.lowerBound, n.isFinite ? n : fallback))
    }
}

public struct CustomAppearance: Codable, Equatable, Sendable {
    public var version = 1
    public var colors: [ColorPreset] = []
    public var textPresets: [TextPreset] = []
    public var quotaHex: String?
    public var quotaPresetID: UUID?
    public var progressFollowsQuota = true
    public var progressHex = "#72D5E8"
    public var progressPresetID: UUID?
    public var chest: TextPreset?
    public var background: BackgroundComposition?
    public init() {}
    public mutating func save(_ preset: ColorPreset) {
        if let i = colors.firstIndex(where: { $0.id == preset.id }) { colors[i] = preset } else { colors.append(preset) }
        if quotaPresetID == preset.id { quotaHex = preset.hex }
        if progressPresetID == preset.id { progressHex = preset.hex }
    }
    public mutating func removeColor(_ id: UUID) {
        colors.removeAll { $0.id == id }
        if quotaPresetID == id { quotaPresetID = nil }
        if progressPresetID == id { progressPresetID = nil }
    }
    public mutating func save(_ preset: TextPreset) {
        if let i = textPresets.firstIndex(where: { $0.id == preset.id }) { textPresets[i] = preset } else { textPresets.append(preset) }
        if chest?.id == preset.id { chest = preset }
    }
    public mutating func removeText(_ id: UUID) { textPresets.removeAll { $0.id == id } }
}

public enum BackgroundReadability {
    /// Bound every pixel, including transparent pixels, rather than trusting a sampled average.
    /// The final bottom reflection is included in the bound used by the light glass material.
    public static func protection(opacity: Double, solid: Bool, darkestPixel: RGBColor? = nil) -> Double {
        if solid { return 1 }
        let base = RGBColor(hex: 0xBBD1E2).mixed(with: darkestPixel ?? RGBColor(0,0,0), amount: opacity)
        for step in 0...100 {
            let amount = Double(step) / 100
            let final = base.mixed(with: RGBColor(1,1,1), amount: amount).mixed(with: RGBColor(hex: 0x587894), amount: 0.2)
            if RGBColor(hex: 0x344B63).contrast(with: final) >= 4.5 { return amount }
        }
        return 1
    }
}
