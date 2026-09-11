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
    var cachedCombinationCount: Int { cache.count }
    var cachedTextureBytes: Int { cache.values.reduce(0) { $0 + $1.base.width * $1.base.height * 4 * 4 } }
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
        if order.count >= 16 { cache.removeValue(forKey: order.removeFirst()) }; order.append(key); cache[key]=textures
        return textures
    }
}

@MainActor final class CharacterLibrary: ObservableObject {
    @Published private(set) var characters: [ImportedCharacter] = []
    @Published private(set) var selectedID: String?
    @Published private(set) var isBusy = false
    @Published private(set) var errorMessage = ""
    private let storage: CharacterPackageStore
    private let defaults: UserDefaults
    private var task: Task<Void, Never>?
    var selected: ImportedCharacter? { characters.first { $0.id == selectedID } }
    init(directory: URL, defaults: UserDefaults) {
        storage = CharacterPackageStore(directory: directory); self.defaults=defaults
        selectedID = defaults.string(forKey: "character.selected.v1")
        let storage = storage
        isBusy = true
        task = Task { [weak self] in
            let loaded = await Task.detached(priority: .utility) {
                storage.identifiers().map { id in (id, try? storage.load(id: id)) }
            }.value
            guard let self, !Task.isCancelled else { return }
            self.characters = loaded.compactMap { id, data in data.flatMap { try? ImportedCharacter(id: id, prepared: $0) } }
            if loaded.contains(where: { $0.1 == nil }) || (selectedID != nil && selected == nil) {
                self.errorMessage = "角色资源不可用，已显示内置猫咪。 / Character unavailable; using the built-in cat."
            }
            self.isBusy = false
        }
    }
    deinit { task?.cancel() }
    func select(_ id: String?) {
        guard id == nil || characters.contains(where: { $0.id == id }) else { return }
        selectedID=id; defaults.set(id, forKey: "character.selected.v1")
    }
    func choose(copy: Copybook) {
        guard !isBusy else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories=true; panel.canChooseFiles=false; panel.allowsMultipleSelection=false; panel.treatsFilePackagesAsDirectories=true
        panel.message=copy.text("选择包含 character.json 和三张 PNG 的本地角色包文件夹，不会上传照片。", "Choose a local folder with character.json and three PNG layers. No photos are uploaded.")
        panel.begin { [weak self] response in
            guard response == .OK, let url=panel.url else { return }
            Task { @MainActor in self?.importPackage(url, copy: copy) }
        }
    }
    func importPackage(_ folder: URL, copy: Copybook) {
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
                self.characters.append(character); self.select(character.id); self.isBusy=false
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
            Picker(copy.text("桌宠形象", "Companion character"), selection: Binding(get: { library.selected?.id ?? "builtin" }, set: { library.select($0 == "builtin" ? nil : $0) })) {
                Text(copy.text("内置猫咪", "Built-in cat")).tag("builtin")
                ForEach(library.characters) { character in Text(character.manifest.name).tag(character.id) }
            }.disabled(library.isBusy)
            HStack {
                Button(copy.text("导入角色包…", "Import character…")) { library.choose(copy: copy) }.disabled(library.isBusy)
                Button(copy.text("恢复内置猫咪", "Use built-in cat")) { library.select(nil) }.disabled(library.selectedID == nil)
                if library.isBusy { ProgressView().controlSize(.small) }
            }
            Text(copy.text("先在对话中根据照片生成并确认形象，再导入本地角色包。这里不接收原始照片，也不会上传。", "Generate and approve a character in chat, then import its local package. This app does not receive or upload reference photos."))
                .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if !library.errorMessage.isEmpty { Text(library.errorMessage).font(.system(size: 12)).foregroundStyle(.red) }
        }
    }
}
