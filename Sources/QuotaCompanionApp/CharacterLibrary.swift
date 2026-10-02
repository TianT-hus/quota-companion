import AppKit
import ImageIO
import SwiftUI
import QuotaCore

@MainActor final class ImportedCharacter: Identifiable {
    let id: String
    let manifest: CharacterManifest
    let base: CGImage
    let fillMask: CGImage
    let details: CGImage
    private let pixels: [UInt8]
    struct Textures { let base: CGImage; let fill: CGImage; let mask: CGImage; let details: CGImage }
    private var cache: [String: Textures] = [:]
    private var order: [String] = []
    private var cacheLimit = 16
    private(set) var animationFrames: [ImportedCharacter] = []
    var cachedCombinationCount: Int { cache.count }
    var cachedTextureBytes: Int { cache.values.reduce(0) { $0 + $1.base.width * $1.base.height * 4 * 4 } + animationFrames.reduce(0) { $0 + $1.cachedTextureBytes } }
    func clearTextures() { cache.removeAll(); order.removeAll(); animationFrames.forEach { $0.clearTextures() } }
    init(id: String, prepared: PreparedCharacter) throws {
        func image(_ data: Data) throws -> CGImage {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw CharacterPackageError.invalidImage }
            return image
        }
        self.id=id; manifest=prepared.manifest
        let decodedBase = try image(prepared.base)
        base = decodedBase; fillMask = try image(prepared.fillMask); details = try image(prepared.details)
        let width = decodedBase.width, height = decodedBase.height
        var bytes = [UInt8](repeating: 0, count: width*height*4)
        let success = bytes.withUnsafeMutableBytes { memory -> Bool in
            guard let context = CGContext(data: memory.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width*4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(decodedBase, in: CGRect(x: 0, y: 0, width: width, height: height)); return true
        }
        guard success else { throw CharacterPackageError.invalidImage }; pixels=bytes
        if prepared.manifest.version == 3 {
            guard prepared.frames.count == 8 else { throw CharacterPackageError.invalidLayers }
            cacheLimit = 1
            var frameManifest = manifest; frameManifest.version = 2; frameManifest.animation = nil
            animationFrames = try prepared.frames.enumerated().map { index, frame in
                let value = try ImportedCharacter(id: "\(id)-\(index)", prepared: PreparedCharacter(manifest: frameManifest, base: frame.base, fillMask: frame.fillMask, details: frame.details))
                value.cacheLimit = 1
                return value
            }
        }
    }
    func tinted(_ color: QuotaCore.RGBColor) -> CGImage {
        textures(color, pixelScale: Double(manifest.pixelsPerPoint)).fill
    }
    func textures(_ color: QuotaCore.RGBColor, pixelScale: Double) -> Textures {
        let scale = pixelScale.isFinite ? min(4, max(1, pixelScale)) : 1
        let width = Int((72*scale).rounded()), height = Int((80*scale).rounded())
        let key = "\(color.hexString)-\(width)x\(height)"
        if let textures = cache[key] { return textures }
        var output = pixels
        for i in stride(from: 0, to: output.count, by: 4) where pixels[i+3] > 0 {
            let alpha = Double(pixels[i+3])/255
            let l = (0.2126*Double(pixels[i])+0.7152*Double(pixels[i+1])+0.0722*Double(pixels[i+2]))/255/alpha
            for (channel, value) in [color.r,color.g,color.b].enumerated() {
                let shade = l <= 0.75 ? value*l/0.85 : value+(1-value)*(l-0.75)/0.25*0.65
                output[i+channel] = UInt8(min(255, max(0, shade*alpha*255)).rounded())
            }
        }
        guard let provider = CGDataProvider(data: Data(output) as CFData),
              let image = CGImage(width: base.width, height: base.height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: base.width*4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else {
            return Textures(base: base, fill: base, mask: fillMask, details: details)
        }
        func sized(_ source: CGImage) -> CGImage {
            if source.width == width && source.height == height { return source }
            guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width*4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return source }
            context.interpolationQuality = manifest.version == 1 ? .none : .high
            context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
            return context.makeImage() ?? source
        }
        let textures = Textures(base: sized(base), fill: sized(image), mask: sized(fillMask), details: sized(details))
        if order.count >= cacheLimit { cache.removeValue(forKey: order.removeFirst()) }; order.append(key); cache[key]=textures
        return textures
    }
}

@MainActor final class CharacterLibrary: ObservableObject {
    @Published var animationInterval: AnimationInterval {
        didSet { if animationInterval.valid, let data = try? JSONEncoder().encode(animationInterval) { defaults.set(data, forKey: "character.animationInterval.v2") } }
    }
    @Published var animationFrequency: AnimationFrequency {
        didSet { defaults.set(animationFrequency.rawValue, forKey: "character.animationFrequency.v1") }
    }
    @Published var characters: [ImportedCharacter] = []
    @Published private(set) var selectedID: String?
    @Published var aliases: [String: String]
    @Published var editRecords: [String: CharacterEditRecord] = [:]
    @Published var motionDrafts: [String: [CharacterMotionDraft]] = [:]
    var unavailableEdits: Set<String> = []
    lazy var builtinCharacter: ImportedCharacter? = {
        let t = FantasyCatTexture.shared
        func png(_ cg: CGImage) -> Data { NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])! }
        let m = CharacterManifest(name: "Built-in cat", label: .init(x: 7, y: 39, width: 48, height: 24), fillTop: FantasyCatTexture.top, fillBottom: FantasyCatTexture.bottom)
        return try? ImportedCharacter(id: "builtin", prepared: PreparedCharacter(manifest: m, base: png(t.body), fillMask: png(t.body), details: png(t.details)))
    }()
    @Published private(set) var isBusy = false
    @Published var errorMessage = ""
    @Published var animationEnabled: Bool { didSet { defaults.set(animationEnabled, forKey: "character.animation.enabled.v1") } }
    let storage: CharacterPackageStore
    let defaults: UserDefaults
    private var task: Task<Void, Never>?
    var selected: ImportedCharacter? { characters.first { $0.id == selectedID } }
    init(directory: URL, defaults: UserDefaults) {
        storage = CharacterPackageStore(directory: directory); self.defaults=defaults
        animationEnabled = defaults.object(forKey: "character.animation.enabled.v1") as? Bool ?? true
        let legacyFrequency = AnimationFrequency(rawValue: defaults.string(forKey: "character.animationFrequency.v1") ?? "") ?? .natural
        animationFrequency = legacyFrequency
        let interval = defaults.data(forKey: "character.animationInterval.v2").flatMap { try? JSONDecoder().decode(AnimationInterval.self, from: $0) }
        animationInterval = interval.flatMap { $0.valid ? $0 : nil } ?? AnimationInterval(legacy: legacyFrequency)
        selectedID = defaults.string(forKey: "character.selected.v1")
        aliases = defaults.dictionary(forKey: "character.displayAliases.v1") as? [String: String] ?? [:]
        let storage = storage
        isBusy = true
        task = Task { [weak self] in
            let loaded = await Task.detached(priority: .utility) {
                storage.identifiers().map { id in (id, try? storage.load(id: id)) }
            }.value
            guard let self, !Task.isCancelled else { return }
            self.characters = loaded.compactMap { id, data in data.flatMap { try? ImportedCharacter(id: id, prepared: $0) } }
            self.reloadEdits()
            if loaded.contains(where: { $0.1 == nil }) || (selectedID != nil && selected == nil) {
                self.errorMessage = "角色资源不可用，已显示内置猫咪。 / Character unavailable; using the built-in cat."
            }
            self.isBusy = false
        }
    }
    deinit { task?.cancel() }
    func displayName(for id: String?, copy: Copybook) -> String {
        editRecords[id ?? "builtin"]?.name ?? aliases[id ?? "builtin"] ?? characters.first(where: { $0.id == id })?.manifest.name ?? copy.text("内置猫咪", "Built-in cat")
    }
    @discardableResult func rename(_ id: String?, to proposed: String, copy: Copybook) -> Bool {
        guard id == nil || characters.contains(where: { $0.id == id }) else { return false }
        let value = proposed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard CharacterNamePolicy.valid(value) else { return false }
        do { try saveEdit(id, name: value, motions: draftMotions(for: id), copy: copy); return true }
        catch { return false }
    }
    func clearError() { errorMessage = "" }
    func select(_ id: String?) {
        guard id == nil || characters.contains(where: { $0.id == id }) else { return }
        if selectedID != id { selected?.clearTextures() }
        selectedID=id; defaults.set(id, forKey: "character.selected.v1")
    }
    func choose(copy: Copybook, selectAfterImport: Bool = true) {
        guard !isBusy else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories=true; panel.canChooseFiles=false; panel.allowsMultipleSelection=false; panel.treatsFilePackagesAsDirectories=true
        panel.message=copy.text("选择包含 character.json 和 PNG 图层的本地角色包；支持静态与动态角色，不会上传照片。", "Choose a local static or animated character package with character.json and PNG layers. No photos are uploaded.")
        panel.beginOwned { [weak self] response in
            guard response == .OK, let url=panel.url else { return }
            Task { @MainActor in self?.importPackage(url, copy: copy, selectAfterImport: selectAfterImport) }
        }
    }
    func importPackage(_ folder: URL, copy: Copybook, selectAfterImport: Bool = true) {
        guard !isBusy else { return }
        isBusy=true; errorMessage=""
        let storage=storage
        task=Task { [weak self] in
            do {
                let result = try await Task.detached(priority: .utility) {
                    let scoped=folder.startAccessingSecurityScopedResource(); defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
                    let prepared=try CharacterPackageStore.prepare(folder: folder)
                    return (try storage.save(prepared), prepared)
                }.value
                guard let self, !Task.isCancelled else { return }
                let character=try ImportedCharacter(id: result.0, prepared: result.1)
                self.characters.append(character)
                self.motionDrafts[character.id] = character.manifest.animation == nil ? [] : [CharacterMotionDraft(id: "original", name: "原包动画 / Original", character: character, enabled: true)]
                if selectAfterImport { self.select(character.id) }
                self.isBusy=false
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.isBusy=false
                self.errorMessage=(error as? CharacterPackageError)?.message(chinese: copy.locale.language.languageCode?.identifier == "zh") ?? copy.text("角色包读取或保存失败，当前形象未更改。", "Could not read or save the character package. Current character is unchanged.")
            }
        }
    }
}

struct CharacterSettings: View {
    @ObservedObject var library: CharacterLibrary
    let copy: Copybook
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsPicker(copy.text("桌宠形象", "Companion character"), selection: Binding(get: { library.selected?.id ?? "builtin" }, set: { library.select($0 == "builtin" ? nil : $0) }), options: [SettingsChoice("builtin", copy.text("内置猫咪", "Built-in cat"))] + library.characters.map { SettingsChoice($0.id, $0.manifest.name) }).disabled(library.isBusy)
            if library.selected?.manifest.animation != nil {
                SettingsRowDivider()
                SettingsToggle(copy.text("抛接手捧花", "Bouquet toss and catch"), isOn: $library.animationEnabled)
                SettingsPicker(copy.text("动画频率", "Animation frequency"), selection: $library.animationFrequency, options: AnimationFrequency.allCases.map { SettingsChoice($0, $0.title(chinese: copy.locale.language.languageCode?.identifier == "zh")) }).disabled(!library.animationEnabled).accessibilityIdentifier("settings.animationFrequency")
                    .help(copy.text("悬停、拖动和菜单打开时暂停；系统减少动态效果优先。", "Hover, dragging and menus pause playback; Reduce Motion takes priority."))
            }
            SettingsRowDivider()
            HStack {
                Button(copy.text("导入角色包…", "Import character…")) { library.choose(copy: copy) }.disabled(library.isBusy)
                    .help(copy.text("导入已确认的本地角色包，不接收原始照片。", "Import an approved local character package, not a reference photo."))
                Button(copy.text("恢复内置猫咪", "Use built-in cat")) { library.select(nil) }.disabled(library.selectedID == nil)
                if library.isBusy { ProgressView().controlSize(.small) }
            }
            if !library.errorMessage.isEmpty { Label(library.errorMessage, systemImage: "exclamationmark.triangle").foregroundStyle(ManagementStyle.ink) }
        }
    }
}
