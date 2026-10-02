import Foundation

public struct CompanionSize: RawRepresentable, CaseIterable, Hashable, Sendable {
    private let physicalPercent: Double
    /// Legacy physical scale, retained for old call sites and rollback formats.
    public var percent: Int { Int(physicalPercent.rounded()) }
    public init(percent: Int) { physicalPercent = Double(min(125, max(50, percent))) }
    public init(sliderPercent: Double) { physicalPercent = 50 + min(100, max(0, sliderPercent.isFinite ? sliderPercent : 0))*0.75 }
    public var sliderPercent: Double { (physicalPercent-50)/0.75 }
    public var displayedPercent: Int { Int(sliderPercent.rounded()) }
    public static let medium = Self(percent: 50)
    public static let large = Self(percent: 75)
    public static let extraLarge = Self(percent: 100)
    public static let allCases: [Self] = [.medium, .large, .extraLarge]
    public init?(rawValue: String) {
        switch rawValue {
        case "medium": self = .medium
        case "large": self = .large
        case "extraLarge": self = .extraLarge
        default:
            guard rawValue.hasPrefix("percent:"), let value = Int(rawValue.dropFirst(8)), (50...125).contains(value) else { return nil }
            self.init(percent: value)
        }
    }
    public var rawValue: String {
        switch percent { case 50: "medium"; case 75: "large"; case 100: "extraLarge"; default: "percent:\(percent)" }
    }
    public var scale: Double { physicalPercent/50 }
    public var petSize: CGSize { CGSize(width: 72 * scale, height: 80 * scale) }
    public func title(chinese: Bool) -> String {
        switch percent { case 50: chinese ? "中" : "Medium"; case 75: chinese ? "大" : "Large"; case 100: chinese ? "超大" : "Extra large"; default: "\(percent)%" }
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
