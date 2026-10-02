import Foundation

public enum ColorEntryFormat: String, CaseIterable, Sendable { case hex = "HEX", rgb = "RGB" }

/// Raw input is kept separately from the last valid opaque color; validation never truncates it.
public struct ColorEntry: Equatable, Sendable {
    public private(set) var format: ColorEntryFormat = .hex
    public private(set) var hex: String
    public private(set) var rgb: [String]
    public private(set) var color: RGBColor
    public init(_ color: RGBColor) {
        self.color = color; hex = color.hexString
        rgb = [color.r, color.g, color.b].map { String(Int(($0 * 255).rounded())) }
    }
    public var invalidField: Int? {
        if format == .hex { return RGBColor(hexString: hex) == nil ? 0 : nil }
        return rgb.indices.first { !Self.validByte(rgb[$0]) }.map { $0 + 1 }
    }
    private static func validByte(_ text: String) -> Bool {
        !text.isEmpty && text.utf8.allSatisfy { (48...57).contains($0) } && Int(text).map { (0...255).contains($0) } == true
    }
    public mutating func editHex(_ text: String) {
        hex = text
        if let value = RGBColor(hexString: text) { color = value; rgb = Self(value).rgb }
    }
    public mutating func editRGB(_ text: String, at index: Int) {
        guard rgb.indices.contains(index) else { return }
        rgb[index] = text
        if rgb.allSatisfy(Self.validByte), let value = RGBColor.rgbStrings(rgb) { color = value; hex = value.hexString }
    }
    @discardableResult public mutating func select(_ next: ColorEntryFormat) -> Bool {
        guard invalidField == nil else { return false }
        let value = color; self = Self(value); format = next; return true
    }
    public mutating func load(_ color: RGBColor) {
        let mode = format; self = Self(color); format = mode
    }
}
