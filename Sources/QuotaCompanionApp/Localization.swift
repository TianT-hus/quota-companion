import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case zhHans
    case english

    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: return "跟随系统 / System"
        case .zhHans: return "简体中文"
        case .english: return "English"
        }
    }
}

struct Copybook {
    let language: AppLanguage

    private var chinese: Bool {
        switch language {
        case .zhHans: return true
        case .english: return false
        case .system: return Locale.current.language.languageCode?.identifier == "zh"
        }
    }

    func text(_ zh: String, _ en: String) -> String { chinese ? zh : en }
    var locale: Locale { chinese ? Locale(identifier: "zh-Hans") : Locale(identifier: "en") }
}
