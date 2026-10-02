import AppKit
import Combine
import QuotaCore

/// Session-only drafts. Nothing enters the library until the explicit save action succeeds.
@MainActor final class CompanionWizardSession: ObservableObject {
    enum Route { case image, package }
    enum Purpose { case ready, reference }
    enum Page: String, CaseIterable {
        case choice, image, purpose, prompt, result, arrange, quota, imageName, imageDone
        case package, check, packageName, packageDone
    }
    @Published var route: Route = .image
    @Published var purpose: Purpose = .ready
    @Published private(set) var page: Page = .choice
    let source: ImageCharacterDraft
    let result = ImageCharacterDraft()
    @Published private(set) var sourceFilename = ""
    @Published private(set) var resultFilename = ""
    @Published var characterDescription = ""
    @Published var clothing = ""
    @Published var artStyle = ""
    @Published var imageName = ""
    @Published var packageName = ""
    @Published private(set) var packageFilename = ""
    @Published private(set) var packageDraft: NewCharacterDraft?
    @Published private(set) var savedCharacter: ImportedCharacter?
    @Published private(set) var loading = false
    @Published var error: String?
    @Published var notice: String?
    private var request: UUID?
    private var readTask: Task<Void, Never>?
    private var closed = false
    private var observers: Set<AnyCancellable> = []

    init(source: ImageCharacterDraft = ImageCharacterDraft()) {
        self.source = source
        for draft in [source, result] {
            draft.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &observers)
        }
    }
    var draft: ImageCharacterDraft { purpose == .reference ? result : source }
    var completed: Bool { page == .imageDone || page == .packageDone }
    var stepCount: Int { route == .image ? 7 : 5 }
    var step: Int {
        switch page {
        case .choice: 0
        case .image, .package: 1
        case .purpose, .prompt, .result, .check: 2
        case .arrange, .packageName: 3
        case .quota, .packageDone: 4
        case .imageName: 5
        case .imageDone: 6
        }
    }
    var dirty: Bool {
        !completed && (source.image != nil || result.image != nil || packageDraft != nil ||
            [characterDescription, clothing, artStyle, imageName, packageName].contains { !$0.isEmpty })
    }
    var canAdvance: Bool {
        guard !loading, !closed else { return false }
        switch page {
        case .image, .purpose: return source.image != nil
        case .result, .arrange, .quota: return draft.image != nil
        case .package, .check: return packageDraft != nil
        case .imageName: return draft.image != nil && CharacterNamePolicy.valid(imageName)
        case .packageName: return packageDraft != nil && CharacterNamePolicy.valid(packageName)
        default: return true
        }
    }
    func back() {
        guard !loading, !closed, !completed else { return }
        error = nil; notice = nil
        switch page {
        case .choice: break
        case .image, .package: page = .choice
        case .purpose: page = .image
        case .prompt: page = .purpose
        case .result: page = .prompt
        case .arrange: page = purpose == .reference ? .result : .purpose
        case .quota: page = .arrange
        case .imageName: page = .quota
        case .check: page = .package
        case .packageName: page = .check
        case .imageDone, .packageDone: break
        }
    }
    func advance(library: CharacterLibrary, copy: Copybook) {
        guard canAdvance, !completed else { return }
        error = nil; notice = nil
        do {
            switch page {
            case .choice: page = route == .image ? .image : .package
            case .image: page = .purpose
            case .purpose: page = purpose == .ready ? .arrange : .prompt
            case .prompt: page = .result
            case .result: _ = try draft.prepared(); page = .arrange
            case .arrange: _ = try draft.prepared(); page = .quota
            case .quota: _ = try draft.prepared(); page = .imageName
            case .package: page = .check
            case .check: page = .packageName
            case .imageName, .packageName:
                guard !library.isBusy else { return }
                let package = page == .packageName
                let prepared = try package ? packageDraft!.prepared : draft.prepared()
                loading = true; defer { loading = false }
                let id = try library.importPrepared(prepared, name: package ? packageName : imageName, copy: copy)
                savedCharacter = library.characters.first { $0.id == id }
                page = package ? .packageDone : .imageDone
            case .imageDone, .packageDone: break
            }
        } catch { self.error = error.localizedDescription }
    }
    func loadImage(_ url: URL, result isResult: Bool) {
        guard !closed else { return }
        error = nil; notice = nil
        do {
            try (isResult ? result : source).load(url)
            if isResult { resultFilename = url.lastPathComponent }
            else { sourceFilename = url.lastPathComponent }
        } catch { self.error = error.localizedDescription }
    }
    func loadPackage(_ url: URL) {
        guard !closed, !loading else { return }
        let id = UUID(); request = id; loading = true; error = nil; notice = nil
        readTask = Task { [weak self] in
            do {
                let prepared = try await readCharacterPackage(url)
                guard let self, self.request == id, !self.closed, !Task.isCancelled else { return }
                try self.acceptPackage(prepared, filename: url.lastPathComponent)
                self.loading = false; self.readTask = nil
            } catch {
                guard let self, self.request == id, !self.closed else { return }
                self.error = error.localizedDescription; self.loading = false; self.readTask = nil
            }
        }
    }
    func acceptPackage(_ prepared: PreparedCharacter, filename: String) throws {
        let character = try ImportedCharacter(id: UUID().uuidString, prepared: prepared)
        if packageName.isEmpty || packageName == packageDraft?.prepared.manifest.name { packageName = prepared.manifest.name }
        packageDraft = .init(prepared: prepared, character: character); packageFilename = filename
    }
    func finish() { closed = true; request = nil; readTask?.cancel(); readTask = nil; loading = false }
    func promptText(copy c: Copybook) -> String {
        let descriptions = [characterDescription, clothing, artStyle].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let subject = descriptions.isEmpty ? c.text("保留参考图中的主体形象和主要特征。", "Keep the subject and defining features from the reference image.") : descriptions.joined(separator: "\n")
        return c.text("请参考我提供的图片，制作一张桌宠角色图。", "Use my reference image to create a desktop companion.") + "\n" + subject + "\n" + Self.requirements(copy: c)
    }
    static func requirements(copy c: Copybook) -> String {
        c.text("保留完整全身，正面或四分之三视角，主体居中，四周留少量空白。背景需要真正透明，不要画棋盘格来模拟透明。不要文字、数字或水印。导出 PNG 图片。", "Show the full body, front or three-quarter view, centered with a little space around it. Use a genuinely transparent background, not a painted checkerboard. No text, numbers or watermarks. Export as PNG.")
    }
    // Internal deterministic fixture hook used only by isolated native rendering tests.
    func previewPage(_ page: Page) { self.page = page }
}
