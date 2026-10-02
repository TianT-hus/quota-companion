import Foundation

extension QuotaWindow {
    /// Absolute reset time; never infer restored quota from a passed timestamp.
    public func resetTimestampText(locale: Locale, timeZone: TimeZone = .autoupdatingCurrent, full: Bool = false) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = full ? "yyyy/MM/dd HH:mm zzz" : "MM/dd HH:mm"
        let date = formatter.string(from: resetsAt)
        return locale.language.languageCode?.identifier == "zh" ? "\(date) 重置" : "Resets \(date)"
    }

    public func shortResetText(now: Date, locale: Locale) -> String {
        let seconds = max(0, Int(resetsAt.timeIntervalSince(now)))
        let zh = locale.language.languageCode?.identifier == "zh"
        if seconds >= 86400 { return zh ? "\(seconds / 86400)天\(seconds % 86400 / 3600)时" : "\(seconds / 86400)d\(seconds % 86400 / 3600)h" }
        if seconds >= 3600 { return zh ? "\(seconds / 3600)时\(seconds % 3600 / 60)分" : "\(seconds / 3600)h\(seconds % 3600 / 60)m" }
        return zh ? "\(seconds / 60)分\(seconds % 60)秒" : "\(seconds / 60)m\(seconds % 60)s"
    }
}
