import AppKit
import QuotaCore

@MainActor enum CharacterNamePolicy {
    // Four columns with a permanently visible scrollbar, 12pt gaps and 10pt tile insets.
    static let maximumWidth: CGFloat = 108
    static func units(_ name: String) -> Int {
        name.reduce(0) { $0 + ($1.unicodeScalars.allSatisfy { $0.value < 128 } ? 1 : 2) }
    }
    static func valid(_ name: String) -> Bool {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !n.isEmpty && units(n) <= 16 && !n.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
            && (n as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 13, weight: .semibold)]).width <= maximumWidth
    }
}

struct CharacterEditRecord: Codable, Equatable {
    struct Motion: Codable, Equatable { var id: String; var name: String }
    var version = 1
    var name: String?
    var enabled: [String]
    var motions: [Motion]
}

@MainActor struct CharacterMotionDraft: Identifiable {
    var id: String
    var name: String
    var character: ImportedCharacter
    var pending: PreparedCharacter?
    var enabled: Bool
    var original: Bool { id == "original" }
}

enum CharacterEditError: LocalizedError {
    case invalidName, incompatible, noSelection, missing, corrupt
    var errorDescription: String? {
        switch self {
        case .invalidName: "名称最多 16 单位，汉字计 2、英文计 1，且需完整放入卡片。请缩短名称。 / Shorten the name to fit (16 units maximum)."
        case .incompatible: "动画包需为兼容的 v3 包：8 帧、3 秒，画布、填充范围及数字位置须与该桌宠一致。 / Incompatible animation package."
        case .noSelection: "请至少选择一个动画；如需停止播放，请关闭桌宠动画总开关。 / Select at least one animation."
        case .missing: "桌宠文件已不可用，未保存更改。 / Companion no longer available."
        case .corrupt: "动画配置不可用，未覆盖原文件。 / Animation settings could not be read."
        }
    }
}

@MainActor extension CharacterLibrary {
    func editFolder(_ id: String?) throws -> URL {
        guard id == nil || UUID(uuidString: id!) != nil else { throw CharacterEditError.missing }
        let folder = storage.directory.appendingPathComponent(id ?? "builtin")
        if FileManager.default.fileExists(atPath: folder.path) {
            guard try folder.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { throw CharacterEditError.missing }
        } else if id != nil { throw CharacterEditError.missing }
        return folder
    }
    func readRecord(_ id: String?) throws -> CharacterEditRecord? {
        let url = try editFolder(id).appendingPathComponent("companion-edit-v1.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let v = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .fileSizeKey])
        guard v.isSymbolicLink != true, (v.fileSize ?? Int.max) < 1_048_576 else { throw CharacterEditError.corrupt }
        let r = try JSONDecoder().decode(CharacterEditRecord.self, from: Data(contentsOf: url))
        guard r.version == 1, Set(r.motions.map(\.id)).count == r.motions.count,
              r.motions.allSatisfy({ UUID(uuidString: $0.id) != nil }) else { throw CharacterEditError.corrupt }
        return r
    }
    func reloadEdits() {
        for id in [nil] + characters.map({ Optional($0.id) }) {
            do {
                let record = try readRecord(id)
                if let record { editRecords[id ?? "builtin"] = record }
                var motions: [CharacterMotionDraft] = []
                if let base = characters.first(where: { $0.id == id }), base.manifest.animation != nil {
                    motions.append(CharacterMotionDraft(id: "original", name: "原包动画 / Original", character: base, enabled: record?.enabled.contains("original") ?? true))
                }
                if let record {
                    let store = CharacterPackageStore(directory: try editFolder(id).appendingPathComponent("motions"))
                    for motion in record.motions {
                        let prepared = try store.load(id: motion.id)
                        try validateMotion(prepared, for: id)
                        motions.append(CharacterMotionDraft(id: motion.id, name: motion.name,
                            character: try ImportedCharacter(id: motion.id, prepared: prepared), enabled: record.enabled.contains(motion.id)))
                    }
                }
                motionDrafts[id ?? "builtin"] = motions
            } catch { unavailableEdits.insert(id ?? "builtin"); errorMessage = CharacterEditError.corrupt.localizedDescription }
        }
    }
    func draftMotions(for id: String?) -> [CharacterMotionDraft] { motionDrafts[id ?? "builtin"] ?? [] }
    func playbackMotions(for id: String?) -> [ImportedCharacter] {
        guard !unavailableEdits.contains(id ?? "builtin") else { return [] }
        return draftMotions(for: id).filter(\.enabled).map(\.character)
    }
    func validateMotion(_ prepared: PreparedCharacter, for id: String?) throws {
        guard let base = id == nil ? builtinCharacter : characters.first(where: { $0.id == id }), prepared.manifest.version == 3,
              prepared.manifest.label == base.manifest.label,
              prepared.manifest.fillTop == base.manifest.fillTop,
              prepared.manifest.fillBottom == base.manifest.fillBottom,
              prepared.frames.count == 8 else { throw CharacterEditError.incompatible }
    }
    func prepareMotion(_ url: URL, for id: String?) async throws -> CharacterMotionDraft {
        let prepared = try await Task.detached(priority: .utility) {
            let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
            return try CharacterPackageStore.prepare(folder: url)
        }.value
        try validateMotion(prepared, for: id)
        let uuid = UUID().uuidString
        return CharacterMotionDraft(id: uuid, name: prepared.manifest.name,
            character: try ImportedCharacter(id: uuid, prepared: prepared), pending: prepared, enabled: true)
    }
    /// Assets are written first; a single atomic index is the commit point. Old assets
    /// referenced by the rollback index stay private in the role folder, never in playback.
    func saveEdit(_ id: String?, name: String, motions: [CharacterMotionDraft], copy: Copybook,
                  writeIndex: (Data, URL) throws -> Void = { try $0.write(to: $1, options: .atomic) }) throws {
        guard !unavailableEdits.contains(id ?? "builtin") else { throw CharacterEditError.corrupt }
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard name == displayName(for: id, copy: copy) || CharacterNamePolicy.valid(name) else { throw CharacterEditError.invalidName }
        guard motions.isEmpty || motions.contains(where: \.enabled) else { throw CharacterEditError.noSelection }
        let folder = try editFolder(id), fm = FileManager.default
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("companion-edit-v1.json")
        let store = CharacterPackageStore(directory: folder.appendingPathComponent("motions"))
        var added: [String] = [], committed = motions
        do {
            for i in committed.indices where committed[i].pending != nil {
                let prepared = committed[i].pending!
                try validateMotion(prepared, for: id)
                let newID = try store.save(prepared); added.append(newID)
                committed[i].id = newID
                committed[i].character = try ImportedCharacter(id: newID, prepared: prepared)
                committed[i].pending = nil
            }
            let record = CharacterEditRecord(name: name, enabled: committed.filter(\.enabled).map(\.id),
                motions: committed.filter { !$0.original }.map { .init(id: $0.id, name: $0.name) })
            if fm.fileExists(atPath: url.path) {
                let history = folder.appendingPathComponent("edit-backups")
                try fm.createDirectory(at: history, withIntermediateDirectories: true)
                try fm.copyItem(at: url, to: history.appendingPathComponent(UUID().uuidString + ".json"))
            }
            try writeIndex(JSONEncoder().encode(record), url)
            editRecords[id ?? "builtin"] = record; motionDrafts[id ?? "builtin"] = committed
            objectWillChange.send()
        } catch {
            for addedID in added { try? fm.removeItem(at: store.directory.appendingPathComponent(addedID)) }
            throw error
        }
    }
    /// Injectable trash operation permits failure/rollback testing without real library mutations.
    func deleteCharacter(_ id: String, trash: (URL) throws -> Void = { url in
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
    }) throws {
        guard characters.contains(where: { $0.id == id }) else { throw CharacterEditError.missing }
        let folder = try editFolder(id)
        try trash(folder)
        if selectedID == id { select(nil) }
        characters.removeAll { $0.id == id }
        var renamed = aliases; renamed.removeValue(forKey: id); aliases = renamed
        defaults.set(renamed, forKey: "character.displayAliases.v1")
        editRecords.removeValue(forKey: id); motionDrafts.removeValue(forKey: id); unavailableEdits.remove(id)
    }
    @discardableResult func importPrepared(_ prepared: PreparedCharacter, name: String, copy: Copybook) throws -> String {
        guard CharacterNamePolicy.valid(name) else { throw CharacterEditError.invalidName }
        let id = try storage.save(prepared)
        do {
            let character = try ImportedCharacter(id: id, prepared: prepared)
            let motions = character.manifest.animation == nil ? [] : [CharacterMotionDraft(id: "original", name: "原包动画 / Original", character: character, enabled: true)]
            let record = CharacterEditRecord(name: name.trimmingCharacters(in: .whitespacesAndNewlines), enabled: motions.map(\.id), motions: [])
            try JSONEncoder().encode(record).write(to: storage.directory.appendingPathComponent(id).appendingPathComponent("companion-edit-v1.json"), options: .atomic)
            characters.append(character); editRecords[id] = record; motionDrafts[id] = motions
            return id
        } catch { try? FileManager.default.removeItem(at: storage.directory.appendingPathComponent(id)); throw error }
    }
}
