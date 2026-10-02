import AppKit
import SwiftUI
@preconcurrency import Translation
import NaturalLanguage

@MainActor protocol SpeechTranslating {
    func translate(_ text: String, to target: SpeechLanguage) async throws -> String
    func cancel()
}

@MainActor final class SystemSpeechTranslator: SpeechTranslating {
    private let defaults: UserDefaults
    init(defaults: UserDefaults) { self.defaults = defaults }
    static func pair(_ source: Locale.Language, _ target: SpeechLanguage) -> String {
        "\(source.languageCode?.identifier ?? "unknown"):\(Locale.Language(identifier: target.code).languageCode?.identifier ?? target.code)"
    }
    private var cache: [String: String] = [:]
    private var host: NSWindow?
    private var pending: CheckedContinuation<String, Error>?
    private var revision = UUID()
    private var cancelSession: (() -> Void)?
    static func source(_ text: String) -> Locale.Language? {
        let recognizer = NLLanguageRecognizer(); recognizer.processString(text)
        return recognizer.dominantLanguage.map { Locale.Language(identifier: $0.rawValue) }
    }
    func translate(_ text: String, to target: SpeechLanguage) async throws -> String {
        guard let source = Self.source(text) else { return text }
        if source.languageCode == Locale.Language(identifier: target.code).languageCode { return text }
        guard (defaults.stringArray(forKey: "speech.translation.prepared.v1") ?? []).contains(Self.pair(source, target)) else { throw SpeechConfigError.translationUnavailable }
        let key = "\(target.rawValue):\(text)"
        if let value = cache[key] { return value }
        guard #available(macOS 15, *) else { throw SpeechConfigError.translationUnavailable }
        let destination = Locale.Language(identifier: target.code)
        guard await LanguageAvailability().status(from: source, to: destination) == .installed else { throw SpeechConfigError.translationUnavailable }
        try Task.checkCancellation()
        let value: String
        if #available(macOS 26, *) {
            let session = TranslationSession(installedSource: source, target: destination)
            cancelSession = { session.cancel() }
            defer { cancelSession = nil }
            value = try await session.translate(text).targetText
        } else {
            // The host is owned by the service, not the settings window. Installed resources only.
            value = try await withCheckedThrowingContinuation { continuation in
                pending = continuation; let token = revision
                let window = NSPanel(contentRect: NSRect(x: -10000,y: -10000,width: 1,height: 1), styleMask: [.borderless,.nonactivatingPanel], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false; window.alphaValue = 0; window.ignoresMouseEvents = true
                window.contentView = NSHostingView(rootView: InstalledTranslationTask(text: text, source: source, target: destination) { [weak self] result in
                    guard let self, revision == token else { return }
                    let completion = pending; pending = nil; host?.close(); host = nil
                    completion?.resume(with: result)
                })
                host = window; window.orderFront(nil)
            }
        }
        try Task.checkCancellation()
        guard !value.isEmpty else { throw SpeechConfigError.translationUnavailable }
        if cache.count >= 128 { cache.removeAll() }; cache[key] = value
        return value
    }
    func cancel() {
        revision = UUID(); let completion = pending; pending = nil
        cancelSession?(); cancelSession = nil
        host?.close(); host = nil; completion?.resume(throwing: CancellationError())
    }
}
@available(macOS 15, *) private struct InstalledTranslationTask: View {
    let text: String
    let source: Locale.Language
    let target: Locale.Language
    let completion: @MainActor (Result<String, Error>) -> Void
    var body: some View {
        Color.clear.translationTask(source: source, target: target) { session in
            do { let result = try await session.translate(text); completion(.success(result.targetText)) }
            catch { completion(.failure(error)) }
        }
    }
}
@available(macOS 15, *) struct TranslationPreparation: View {
    let target: SpeechLanguage
    let copy: Copybook
    let prepared: (SpeechLanguage) -> Void
    @Environment(\.ownedDismiss) private var dismiss
    @State private var source: SpeechLanguage = .chinese
    @State private var configuration: TranslationSession.Configuration?
    @State private var result = ""
    @State private var preparing = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(copy.text("翻译语言资源", "Translation resources")).font(.headline)
            Text(copy.text("仅在事项或文案的语言与播报语言不同时需要。例如英文事项用中文播报，需准备英文 → 中文资源。同语言播报无需准备；这里不下载声音，也不配置 API。", "Only needed when text and speech use different languages. For example, English text spoken in Chinese needs English → Chinese resources. Same-language speech needs no preparation. This does not download voices or configure an API."))
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            SettingsPicker(copy.text("原文语言", "Source language"), selection: $source, options: SpeechLanguage.allCases.filter { $0 != target }.map { SettingsChoice($0, $0.title) })
            Text(copy.text("目标语言：", "Target language: ") + target.title)
            HStack {
                Button(copy.text("准备语言资源", "Prepare language resources")) {
                    configuration = .init(source: Locale.Language(identifier: source.code), target: Locale.Language(identifier: target.code))
                    preparing = true
                }
                .disabled(preparing)
                Button(copy.text("关闭", "Close")) { dismiss() }
            }
            Text(result.isEmpty ? copy.text("点击准备后，由 macOS 检查并按需下载语言资源。", "macOS checks and downloads resources when you click Prepare.") : result)
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.padding(24).frame(width: 380).onAppear { source = target == .chinese ? .english : .chinese }
        .translationTask(configuration) { session in
            do { try await session.prepareTranslation(); prepared(source); result = copy.text("语言资源已就绪。", "Language resources are ready.") }
            catch { result = copy.text("语言资源未就绪，请稍后重试。", "Language resources are not ready. Try again later.") }
            preparing = false
        }
    }
}
