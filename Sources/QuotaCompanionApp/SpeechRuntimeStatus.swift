import Foundation

/// Runtime only. A successful request is evidence about that configuration,
/// never a promise of continuous connectivity.
struct SpeechRuntimeStatus: Equatable {
    enum Phase { case unknown, testing, ready, failed }
    var phase: Phase = .unknown
    var detail = ""
    var succeededAt: Date? = nil
    static let unknown = SpeechRuntimeStatus()
    static let testing = SpeechRuntimeStatus(phase: .testing)
    static func ready(_ detail: String, at date: Date? = nil) -> Self { .init(phase: .ready, detail: detail, succeededAt: date) }
    static func failed(_ detail: String) -> Self { .init(phase: .failed, detail: detail) }
    func description(_ copy: Copybook) -> String {
        switch phase {
        case .unknown: return copy.text("尚未验证；配置更改或重启后需要重新验证。", "Not verified. Configuration changes and restarts require verification.")
        case .testing: return copy.text("正在测试，请稍候。", "Testing. Please wait.")
        case .failed: return detail
        case .ready:
            guard let succeededAt else { return detail }
            return detail + " " + copy.text("最近成功：", "Last success: ") + succeededAt.formatted(date: .abbreviated, time: .standard)
                + copy.text("。不代表持续联网。", ". Not a continuous connectivity check.")
        }
    }
}

enum SpokenTime {
    static func format(_ minute: Int, language: SpeechLanguage) -> String {
        switch language {
        case .chinese:
            if minute == 1440 { return "次日零点" }
            let hour = chineseNumber(minute / 60), remainder = minute % 60
            if remainder == 0 { return hour + "点" }
            if remainder == 30 { return hour + "点半" }
            return hour + "点" + (remainder < 10 ? "零" : "") + chineseNumber(remainder) + "分"
        case .english: return String(format: "%02d:%02d", minute / 60, minute % 60)
        case .japanese: return "\(minute / 60)時\(minute % 60)分"
        }
    }
    private static func chineseNumber(_ value: Int) -> String {
        let digits = ["零", "一", "二", "三", "四", "五", "六", "七", "八", "九"]
        guard (0...99).contains(value) else { return String(value) }
        if value < 10 { return digits[value] }
        return (value < 20 ? "" : digits[value / 10]) + "十" + (value % 10 == 0 ? "" : digits[value % 10])
    }
}
