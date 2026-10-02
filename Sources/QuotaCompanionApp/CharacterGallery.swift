import AppKit
import SwiftUI
import QuotaCore

struct GalleryCharacter: Identifiable {
    let character: ImportedCharacter?
    var id: String { character?.id ?? "builtin" }
}

/// Four stable columns; tapping opens the sheet without mutating the selection.
struct CharacterGallery: View {
    @ObservedObject var model: CompanionModel
    @ObservedObject var library: CharacterLibrary
    let copy: Copybook
    @State private var inspected: GalleryCharacter?
    @State private var incoming: NewCharacterDraft?
    @State private var importError: String?
    @State private var loading = false
    @State private var creating = false
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(copy.text("我的桌宠", "My companions")).font(SettingsCardStyle.heading)
                Spacer()
                if library.isBusy { ProgressView().controlSize(.small) }
                Button { creating = true } label: { Label(copy.text("新建", "New"), systemImage: "plus") }
                    .buttonStyle(CalendarPillStyle()).disabled(library.isBusy || loading).accessibilityIdentifier("settings.character.new")
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                CharacterTile(model: model, library: library, item: GalleryCharacter(character: nil), copy: copy) { inspected = GalleryCharacter(character: nil) }
                ForEach(library.characters) { character in
                    CharacterTile(model: model, library: library, item: GalleryCharacter(character: character), copy: copy) { inspected = GalleryCharacter(character: character) }
                }
            }
        }.ownedSheet(isPresented: $creating) { NewCompanionWizard(model: model) { creating = false } }
        .ownedSheet(item: $inspected) { item in
            CharacterDetail(model: model, library: library, item: item, copy: copy) { inspected = nil }
        }.ownedSheet(item: $incoming) { value in NewCharacterSheet(model: model, draft: value) { incoming = nil } }
        .ownedAlert(copy.text("桌宠", "Companion"), isPresented: Binding(get: { importError != nil || !library.errorMessage.isEmpty }, set: { if !$0 { library.clearError(); importError = nil } })) {
            Button(copy.text("确定", "OK")) { library.clearError(); importError = nil }
        } message: { Text(importError ?? library.errorMessage) }
    }
    private func chooseNew() {
        chooseCharacterPackage { url in
            loading = true
            Task { @MainActor in
                defer { loading = false }
                do {
                    let prepared = try await readCharacterPackage(url)
                    incoming = NewCharacterDraft(prepared: prepared, character: try ImportedCharacter(id: UUID().uuidString, prepared: prepared))
                } catch { importError = error.localizedDescription }
            }
        }
    }
}

struct CharacterTile: View {
    @ObservedObject var model: CompanionModel
    @ObservedObject var library: CharacterLibrary
    let item: GalleryCharacter
    let copy: Copybook
    let action: () -> Void
    @State private var hovering = false
    @FocusState private var focused: Bool
    var accessibility = CompanionAccessibility()
    private var selected: Bool { library.selectedID == item.character?.id }
    private var name: String { library.displayName(for: item.character?.id, copy: copy) }
    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                CharacterThumbnail(model: model, character: item.character, scale: 0.85)
                Text(name).font(.system(size: 13, weight: selected ? .semibold : .regular)).lineLimit(1).truncationMode(.middle)
            }.padding(.horizontal, 10).frame(maxWidth: .infinity).frame(height: 112)
                .foregroundStyle(ManagementStyle.ink)
                .background(hovering ? Color(white: 0.965) : .white, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(selected ? ManagementStyle.selectionBorder : Color(white: accessibility.contrast == .increased ? 0.5 : 0.9), lineWidth: accessibility.contrast == .increased ? 2 : 1))
                .overlay(alignment: .topTrailing) {
                    if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(ManagementStyle.selectionBorder).padding(8).accessibilityHidden(true) }
                }.overlay(RoundedRectangle(cornerRadius: 12).stroke(focused ? Color.accentColor : .clear, lineWidth: 2).padding(-2))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).focused($focused).onHover { hovering = $0 }.help(name)
            .accessibilityLabel(name).accessibilityValue(selected ? copy.text("当前使用", "In use") : copy.text("未使用", "Not in use"))
            .accessibilityHint(copy.text("打开详情后选择或编辑", "Open details to use or edit"))
            .accessibilityIdentifier("settings.character.\(item.id)")
    }
}

/// Static real layers: gallery previews never start additional animation timers.
struct CharacterThumbnail: View {
    @ObservedObject var model: CompanionModel
    let character: ImportedCharacter?
    var scale: Double = 1
    var body: some View {
        Group {
            if let character {
                ZStack(alignment: .topLeading) {
                    image(character.base)
                    image(character.details)
                }.frame(width: 72*scale, height: 80*scale)
            } else {
                Image(decorative: FantasyCatTexture.shared.body, scale: 1).resizable().interpolation(.none).frame(width: 72*scale, height: 80*scale)
            }
        }.accessibilityHidden(true)
    }
    private func image(_ cg: CGImage) -> some View { Image(decorative: cg, scale: 1).resizable().interpolation(.high).frame(width: 72*scale, height: 80*scale) }
}

struct CharacterDetail: View {
    @ObservedObject var model: CompanionModel
    @ObservedObject var library: CharacterLibrary
    let item: GalleryCharacter
    let copy: Copybook
    let close: () -> Void
    @State private var editing = false
    private var name: String { library.displayName(for: item.character?.id, copy: copy) }
    var body: some View {
        if editing {
            CharacterEditor(model: model, item: item, close: close) { editing = false }
        } else {
        VStack(spacing: 20) {
            Text(copy.text("桌宠详情", "Companion details"))
                .font(.system(size: 17, weight: .semibold)).frame(maxWidth: .infinity, alignment: .leading)
            CharacterThumbnail(model: model, character: item.character, scale: 2.5)
                Text(name).font(.system(size: 14, weight: .medium)).lineLimit(3).frame(maxWidth: .infinity)
                HStack {
                    Button(copy.text("关闭", "Close"), action: close).keyboardShortcut(.cancelAction)
                    Button(copy.text("编辑", "Edit")) { editing = true }
                    Spacer()
                    Button(library.selectedID == item.character?.id ? copy.text("正在使用", "In use") : copy.text("使用此桌宠", "Use companion")) {
                        library.select(item.character?.id); close()
                    }.disabled(library.selectedID == item.character?.id).keyboardShortcut(.defaultAction)
                }
        }.padding(24).frame(width: 420).font(.system(size: 13)).foregroundStyle(ManagementStyle.ink)
        }
    }
}
