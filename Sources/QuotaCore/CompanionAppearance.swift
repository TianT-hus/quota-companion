import Foundation

public enum CompanionSize: String, CaseIterable, Sendable {
    case medium, large, extraLarge
    public var scale: Double { switch self { case .medium: 1; case .large: 1.5; case .extraLarge: 2 } }
    public var petSize: CGSize { CGSize(width: 72 * scale, height: 80 * scale) }
    public func title(chinese: Bool) -> String {
        switch self { case .medium: chinese ? "中" : "Medium"; case .large: chinese ? "大" : "Large"; case .extraLarge: chinese ? "超大" : "Extra large" }
    }
}
public enum CompanionPalette: String, CaseIterable, Sendable {
    case water, mint, lavender
    public var color: RGBColor {
        switch self { case .water: RGBColor(hex: 0x72D5E8); case .mint: RGBColor(hex: 0x64CDB3); case .lavender: RGBColor(hex: 0xB49ADE) }
    }
    public var textureIndex: Int { switch self { case .water: 0; case .mint: 4; case .lavender: 5 } }
    public func title(chinese: Bool) -> String {
        switch self { case .water: chinese ? "清水蓝" : "Water"; case .mint: chinese ? "薄荷青" : "Mint"; case .lavender: chinese ? "浅紫" : "Lavender" }
    }
}
public enum ChestTextStyle: String, CaseIterable, Sendable {
    case whiteInk, goldInk, inkWhite
    public var text: RGBColor { switch self { case .whiteInk: RGBColor(hex: 0xF4FDFF); case .goldInk: RGBColor(hex: 0xFFE5A3); case .inkWhite: RGBColor(hex: 0x10233C) } }
    public var outline: RGBColor { self == .inkWhite ? RGBColor(hex: 0xF4FDFF) : RGBColor(hex: 0x10233C) }
    public func title(chinese: Bool) -> String {
        switch self { case .whiteInk: chinese ? "A 白字深描边" : "A White / ink"; case .goldInk: chinese ? "B 暖金字深描边" : "B Gold / ink"; case .inkWhite: chinese ? "C 深字白描边" : "C Ink / white" }
    }
}
