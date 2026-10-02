import AppKit
import SwiftUI
import QuotaCore

@MainActor func chooseCharacterPackage(parent: NSWindow? = nil, _ completion: @escaping (URL) -> Void) {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
    panel.beginOwned(parent: parent) { response in if response == .OK, let url = panel.url { completion(url) } }
}
func readCharacterPackage(_ url: URL) async throws -> PreparedCharacter {
    try await Task.detached(priority: .utility) {
        let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
        return try CharacterPackageStore.prepare(folder: url)
    }.value
}
@MainActor struct NewCharacterDraft: Identifiable {
    let id = UUID()
    let prepared: PreparedCharacter
    let character: ImportedCharacter
}

struct NewCharacterSheet: View {
    @ObservedObject var model: CompanionModel
    let draft: NewCharacterDraft
    let close: () -> Void
    var cancel: (() -> Void)?
    @State private var name: String
    @State private var error: String?
    init(model: CompanionModel, draft: NewCharacterDraft, close: @escaping () -> Void, cancel: (() -> Void)? = nil) {
        self.model = model; self.draft = draft; self.close = close
        self.cancel = cancel
        _name = State(initialValue: draft.prepared.manifest.name)
    }
    var body: some View {
        VStack(spacing: 20) {
            Text(model.copy.text("新建桌宠", "New companion")).font(.system(size: 17, weight: .semibold)).frame(maxWidth: .infinity, alignment: .leading)
            CharacterThumbnail(model: model, character: draft.character, scale: 1.8)
            TextField(model.copy.text("桌宠名称", "Companion name"), text: $name).textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("character.import.name")
            HStack {
                Button(model.copy.text("取消", "Cancel"), action: cancel ?? close).keyboardShortcut(.cancelAction)
                Spacer()
                Button(model.copy.text("导入", "Import")) {
                    do { try model.characterLibrary.importPrepared(draft.prepared, name: name, copy: model.copy); close() }
                    catch { self.error = error.localizedDescription }
                }.keyboardShortcut(.defaultAction)
            }
        }.font(.system(size: 13)).padding(24).frame(width: 420).interactiveDismissDisabled()
        .ownedAlert(model.copy.text("未导入", "Not imported"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button(model.copy.text("确定", "OK")) { error = nil }
        } message: { Text(error ?? "") }
    }
}

struct CharacterEditor: View {
    @StateObject private var dialogOwner = DialogOwner()
    @ObservedObject var model: CompanionModel
    let item: GalleryCharacter
    let close: () -> Void
    let back: () -> Void
    @State private var name: String
    @State private var motions: [CharacterMotionDraft]
    @State private var previewID: String?
    @State private var proposed: CharacterMotionDraft?
    @State private var loading = false
    @State private var dialog: EditorDialog?
    @FocusState private var nameFocused: Bool
    private let originalName: String
    private let originalSignature: String
    enum EditorDialog { case discard, delete, error(String) }
    init(model: CompanionModel, item: GalleryCharacter, close: @escaping () -> Void, back: @escaping () -> Void) {
        self.model = model; self.item = item; self.close = close; self.back = back
        let n = model.characterLibrary.displayName(for: item.character?.id, copy: model.copy)
        let m = model.characterLibrary.draftMotions(for: item.character?.id)
        originalName = n; originalSignature = Self.signature(m)
        _name = State(initialValue: n); _motions = State(initialValue: m)
    }
    private static func signature(_ m: [CharacterMotionDraft]) -> String { m.map { "\($0.id):\($0.enabled)" }.joined(separator: ",") }
    private var dirty: Bool { name != originalName || Self.signature(motions) != originalSignature }
    private var c: Copybook { model.copy }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(c.text("编辑桌宠", "Edit companion")).font(.system(size: 17, weight: .semibold))
            HStack {
                Spacer()
                if let active = motions.first(where: { $0.id == previewID }) {
                    AnimatedCharacterView(character: active.character, tint: model.quotaTint ?? model.palette.color, remaining: 47, pixelScale: 3, frequency: .continuous, eligible: true)
                        .frame(width: 108, height: 120).id(active.id).accessibilityLabel(c.text("动画预览", "Animation preview"))
                } else { CharacterThumbnail(model: model, character: item.character, scale: 1.5) }
                Spacer()
            }
            TextField(c.text("桌宠名称", "Companion name"), text: $name).textFieldStyle(.roundedBorder).focused($nameFocused)
                .accessibilityIdentifier("settings.character.name")
            HStack {
                Text(c.text("动画", "Animations"))
                Spacer()
                Button(c.text("导入动画…", "Import animation…"), action: chooseMotion).disabled(loading)
                if loading { ProgressView().controlSize(.small) }
            }
            if !motions.isEmpty {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach($motions) { $motion in
                            HStack(spacing: 8) {
                                Toggle(isOn: $motion.enabled) { Text(motion.original ? c.text("原包动画", "Original animation") : motion.name).lineLimit(1).help(motion.name) }
                                    .toggleStyle(.checkbox)
                                Spacer(minLength: 0)
                                Button(previewID == motion.id ? c.text("停止", "Stop") : c.text("预览", "Preview")) { previewID = previewID == motion.id ? nil : motion.id }
                                if !motion.original {
                                    Button { if previewID == motion.id { previewID = nil }; motions.removeAll { $0.id == motion.id } } label: { Image(systemName: "minus.circle") }
                                        .accessibilityLabel(c.text("移除动画", "Remove animation") + " " + motion.name)
                                }
                            }
                        }
                    }.padding(2)
                }.frame(height: min(132, CGFloat(motions.count)*34))
            }
            HStack {
                if item.character != nil {
                    Button(c.text("删除桌宠", "Delete companion"), role: .destructive) { previewID = nil; dialog = .delete }
                }
                Spacer()
                Button(c.text("取消", "Cancel")) { previewID = nil; if dirty { dialog = .discard } else { back() } }.keyboardShortcut(.cancelAction)
                Button(c.text("保存", "Save"), action: save).keyboardShortcut(.defaultAction)
            }.disabled(loading)
        }.padding(24).frame(width: 460).font(.system(size: 13)).foregroundStyle(ManagementStyle.ink)
        .interactiveDismissDisabled().background(DialogOwnerReader(owner: dialogOwner)).onDisappear { previewID = nil }
        .ownedSheet(item: $proposed) { pending in
            MotionImportConfirmation(model: model, motion: pending, cancel: { proposed = nil }) {
                motions.append(pending); proposed = nil
            }
        }
        .ownedAlert(dialogTitle, isPresented: Binding(get: { dialog != nil }, set: { if !$0 { dialog = nil } })) {
            switch dialog {
            case .discard:
                Button(c.text("继续编辑", "Keep editing"), role: .cancel) { dialog = nil }
                Button(c.text("放弃修改", "Discard"), role: .destructive) { dialog = nil; back() }
            case .delete:
                Button(c.text("取消", "Cancel"), role: .cancel) { dialog = nil }
                Button(c.text("移入废纸篓", "Move to Trash"), role: .destructive) {
                    do { try model.characterLibrary.deleteCharacter(item.id); dialog = nil; close() }
                    catch { dialog = .error(error.localizedDescription) }
                }
            default: Button(c.text("确定", "OK")) { dialog = nil; nameFocused = true }
            }
        } message: { Text(dialogMessage) }
    }
    private var dialogTitle: String {
        switch dialog { case .discard: c.text("放弃未保存修改？", "Discard changes?"); case .delete: c.text("删除这个桌宠？", "Delete companion?"); default: c.text("未保存", "Not saved") }
    }
    private var dialogMessage: String {
        switch dialog {
        case .delete:
            c.text("桌宠及追加动画将移入废纸篓，原始导入文件不受影响。", "The companion and added animations will move to Trash. Original imports are untouched.") + (model.characterLibrary.selectedID == item.character?.id ? c.text("当前桌宠将切换为内置猫咪。", "The built-in cat will become active.") : "")
        case .error(let message): message
        default: c.text("名称和动画修改尚未保存。", "Name and animation changes have not been saved.")
        }
    }
    private func save() {
        previewID = nil
        do { try model.characterLibrary.saveEdit(item.character?.id, name: name, motions: motions, copy: c); back() }
        catch { dialog = .error(error.localizedDescription) }
    }
    private func chooseMotion() {
        previewID = nil
        chooseCharacterPackage(parent: dialogOwner.window) { url in
            loading = true
            Task { @MainActor in
                defer { loading = false }
                do { proposed = try await model.characterLibrary.prepareMotion(url, for: item.character?.id) }
                catch { dialog = .error(error.localizedDescription) }
            }
        }
    }
}

struct MotionImportConfirmation: View {
    @ObservedObject var model: CompanionModel
    let motion: CharacterMotionDraft
    let cancel: () -> Void
    let confirm: () -> Void
    @State private var playing = false
    var body: some View {
        VStack(spacing: 20) {
            Text(model.copy.text("确认动画", "Confirm animation")).font(.system(size: 17, weight: .semibold))
            AnimatedCharacterView(character: motion.character, tint: model.quotaTint ?? model.palette.color, remaining: 47, pixelScale: 4, frequency: .continuous, eligible: playing).frame(width: 144, height: 160)
            Text(motion.name).lineLimit(2)
            Button(playing ? model.copy.text("停止", "Stop") : model.copy.text("预览", "Preview")) { playing.toggle() }
            HStack {
                Button(model.copy.text("取消", "Cancel"), action: cancel).keyboardShortcut(.cancelAction)
                Spacer()
                Button(model.copy.text("添加到草稿", "Add to draft"), action: confirm).keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 380).font(.system(size: 13)).onDisappear { playing = false }
    }
}
