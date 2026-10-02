import Foundation

public enum AnimationFrequency: String, Codable, CaseIterable, Sendable {
    case natural, once, twice, four, continuous, custom
    public var period: Double? {
        switch self { case .natural, .custom: nil; case .once: 60; case .twice: 30; case .four: 15; case .continuous: 3 }
    }
    public func delay(afterAction: Bool, naturalDelay: Double) -> Double {
        guard let period else { return min(40, max(25, naturalDelay.isFinite ? naturalDelay : 30)) }
        if self == .continuous { return 0 }
        return afterAction ? period - CharacterDancePlayback.duration : period
    }
    public func title(chinese: Bool) -> String {
        switch self {
        case .natural: chinese ? "自然间隔（原设置）" : "Natural (original)"
        case .once: chinese ? "每分钟 1 次" : "Once per minute"
        case .twice: chinese ? "每分钟 2 次" : "Twice per minute"
        case .four: chinese ? "每分钟 4 次" : "Four times per minute"
        case .continuous: chinese ? "连续播放" : "Continuous"
        case .custom: chinese ? "自定义" : "Custom"
        }
    }
}

public struct AnimationInterval: Codable, Equatable, Sendable {
    public var version = 1
    public var continuous: Bool
    public var seconds: Int
    public init(continuous: Bool = false, seconds: Int = 30) { self.continuous = continuous; self.seconds = seconds }
    public init(legacy: AnimationFrequency) {
        self.init(continuous: legacy == .continuous, seconds: [.once: 57, .twice: 27, .four: 12][legacy] ?? 30)
    }
    public static func parse(_ text: String) -> Int? {
        guard !text.isEmpty, text.utf8.allSatisfy({ (48...57).contains($0) }), let n = Int(text), (1...3600).contains(n) else { return nil }
        return n
    }
    public var valid: Bool { version == 1 && (1...3600).contains(seconds) }
}
