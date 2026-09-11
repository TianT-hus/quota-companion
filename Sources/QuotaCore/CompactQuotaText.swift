import Foundation

extension QuotaWindow {
    public func shortResetText(now: Date, locale: Locale) -> String {
        let seconds = max(0, Int(resetsAt.timeIntervalSince(now)))
        let zh = locale.language.languageCode?.identifier == "zh"
        if seconds >= 86400 { return zh ? "\(seconds / 86400)天\(seconds % 86400 / 3600)时" : "\(seconds / 86400)d\(seconds % 86400 / 3600)h" }
        if seconds >= 3600 { return zh ? "\(seconds / 3600)时\(seconds % 3600 / 60)分" : "\(seconds / 3600)h\(seconds % 3600 / 60)m" }
        return zh ? "\(seconds / 60)分\(seconds % 60)秒" : "\(seconds / 60)m\(seconds % 60)s"
    }
}
