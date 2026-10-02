import AppKit
import SwiftUI
import UniformTypeIdentifiers
import QuotaCore

struct NewCompanionWizard: View {
    @StateObject var dialogOwner = DialogOwner()
    @ObservedObject var model: CompanionModel
    let close: () -> Void
    @StateObject var session: CompanionWizardSession
    @State var discard = false
    @State var guide = false
    @State var brush = 12.0
    @State var erasing = false
    @State var sample = 79.0
    @State var size = CGSize(width: 868, height: 728)
    @FocusState var nameFocused: Bool
    init(model: CompanionModel, close: @escaping () -> Void, session: CompanionWizardSession? = nil,
         previewDraft: ImageCharacterDraft? = nil, previewStep: Int = 0, previewRoute: String = "") {
        self.model = model; self.close = close
        let state = session ?? CompanionWizardSession(source: previewDraft ?? ImageCharacterDraft())
        if session == nil {
            if previewRoute == "package" { state.route = .package; state.previewPage(.package) }
            else if previewRoute == "image" { state.previewPage([.image,.arrange,.quota,.imageName][min(3,max(0,previewStep))]); state.imageName = previewDraft?.name ?? "" }
        }
        _session = StateObject(wrappedValue: state)
    }
    var c: Copybook { model.copy }
    var leftWidth: CGFloat { min(288, (size.width-88)*0.36) }
    var draft: ImageCharacterDraft { session.draft }
    var package: Bool { session.route == .package }
    private var labels: [String] {
        package ? [c.text("选择方式","Choose path"),c.text("导入角色包","Import folder"),c.text("检查效果","Review"),c.text("命名保存","Name & save"),c.text("完成","Done")] :
            [c.text("选择方式","Choose path"),c.text("上传图片","Choose image"),c.text("准备形象","Prepare"),c.text("调整形象","Arrange"),c.text("额度显示","Quota"),c.text("命名保存","Name & save"),c.text("完成","Done")]
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(c.text("新建桌宠", "New companion")).font(.system(size: 23, weight: .semibold))
                    Text(session.page == .choice ? c.text("选择适合你的制作方式", "Choose how to make your companion") : package ? c.text("导入角色包", "Import a character package") : c.text("从图片制作", "Create from an image"))
                        .font(.system(size: 12)).foregroundStyle(WizardStyle.secondary)
                }
                Spacer()
                Label(c.text("本机处理", "On this Mac"), systemImage: "lock.shield").font(.system(size: 11)).foregroundStyle(WizardStyle.secondary)
            }
            Divider()
            WizardStepBar(titles: labels, step: session.step, complete: session.completed, copy: c)
            Divider()
            ScrollViewReader { scroll in
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(title).font(.system(size: 21, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 12)
                                Text(c.text("第 \(session.step+1) / \(session.stepCount) 步", "Step \(session.step+1) of \(session.stepCount)"))
                                    .font(.system(size: 12, weight: .medium)).foregroundStyle(WizardStyle.secondary).fixedSize()
                            }
                            Text(subtitle).font(.system(size: 13)).foregroundStyle(WizardStyle.secondary).fixedSize(horizontal: false, vertical: true)
                        }.id("top")
                        if let error = session.error {
                            Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                                .padding(12).frame(maxWidth: .infinity, alignment: .leading).background(Color.red.opacity(0.04),in: RoundedRectangle(cornerRadius:8))
                                .textSelection(.enabled).accessibilityIdentifier("wizard.error")
                        }
                        content
                        if let notice = session.notice { Label(notice,systemImage:"checkmark.circle").foregroundStyle(WizardStyle.secondary).font(.system(size:12)).textSelection(.enabled) }
                    }.padding(.vertical, 3).padding(.horizontal, 2)
                }.onChange(of: session.page) { _, _ in scroll.scrollTo("top", anchor: .top); nameFocused = false }
                    .onChange(of: session.error) { _, value in if value != nil { scroll.scrollTo("top",anchor:.top) } }
            }.frame(maxHeight: .infinity)
            Divider()
            footer
        }.font(.system(size: 13)).foregroundStyle(ManagementStyle.ink).tint(WizardStyle.blue)
            .padding(28).frame(width:size.width,height:size.height).background(.white)
            .background(DialogOwnerReader(owner:dialogOwner)).interactiveDismissDisabled()
            .onAppear(perform: fitScreen)
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didChangeScreenNotification)) { note in
                if let window = note.object as? NSWindow, window === dialogOwner.window { fitScreen() }
            }
            .onDisappear { session.finish() }
            .ownedSheet(isPresented:$discard) { WizardDiscardConfirmation(copy:c,onDiscard:finish) }
    }
    private func fitScreen() {
        let visible = (dialogOwner.window?.screen ?? NSScreen.main)?.visibleFrame.size ?? CGSize(width:1000,height:900)
        size = CGSize(width:min(868,max(580,visible.width-48)),height:min(728,max(480,visible.height-72)))
    }
    private func finish() { session.finish(); close() }
    private var footer: some View {
        HStack(spacing: 12) {
            if !session.completed {
                Button(c.text("取消", "Cancel")) { if session.dirty { discard=true } else { finish() } }
                    .keyboardShortcut(.cancelAction).accessibilityIdentifier("wizard.cancel")
            }
            if session.loading { ProgressView().controlSize(.small); Text(c.text("正在检查文件…", "Checking files…")).font(.system(size:11)).foregroundStyle(WizardStyle.secondary) }
            Spacer(minLength: 8)
            if session.page != .choice && !session.completed {
                Button(c.text("上一步", "Back")) { session.back() }.disabled(session.loading).accessibilityIdentifier("wizard.back")
            }
            Button(session.completed ? c.text("返回图库", "Back to gallery") : session.page == .imageName || session.page == .packageName ? c.text("保存到图库", "Save to gallery") : c.text("下一步", "Next")) {
                if session.completed { finish() } else { session.advance(library:model.characterLibrary,copy:c) }
            }.buttonStyle(WizardButtonStyle(primary:true)).keyboardShortcut(.defaultAction)
                .disabled(!session.completed && (!session.canAdvance || model.characterLibrary.isBusy)).accessibilityIdentifier("wizard.next")
        }.buttonStyle(WizardButtonStyle()).frame(minHeight:36)
    }
    @ViewBuilder private var content: some View {
        switch session.page {
        case .choice: routeCards
        case .image: imageUpload
        case .purpose: purposeCards
        case .prompt: promptEditor
        case .result: resultImport
        case .arrange: arrangement
        case .quota: quotaEditor
        case .imageName, .packageName: naming
        case .imageDone, .packageDone: completion
        case .package: packageUpload
        case .check: packageCheck
        }
    }
    private var title: String {
        switch session.page {
        case .choice: c.text("选择制作方式", "Choose your starting point")
        case .image: c.text("选择一张图片", "Choose an image")
        case .purpose: c.text("这张图片准备怎么使用？", "How would you like to use this image?")
        case .prompt: c.text("写清楚你想要的形象", "Describe the companion you want")
        case .result: c.text("制作好后，把结果带回来", "Bring your finished image back")
        case .arrange: c.text("让形象完整地放进画布", "Fit the whole companion on the canvas")
        case .quota: c.text("安排额度数字的位置", "Place the quota label")
        case .imageName: c.text("给它起个名字", "Give your companion a name")
        case .packageName: c.text("确认名称，再保存到图库", "Confirm the name and save")
        case .imageDone: c.text("你的桌宠准备好了", "Your companion is ready")
        case .packageDone: c.text("角色包已加入图库", "Your character is in the gallery")
        case .package: c.text("选择完整的角色包文件夹", "Choose the complete package folder")
        case .check: c.text("检查导入后的效果", "Review your character")
        }
    }
    private var subtitle: String {
        switch session.page {
        case .choice: c.text("有一张喜欢的图片，或者已经准备好了角色包？请选择一种方式。", "Start with an image you like, or import a ready-made character package.")
        case .image: c.text("成品图和参考图都可以。下一步会帮你选择合适的制作方式。", "Use a finished image or a reference. Next, choose the right path for it.")
        case .purpose: c.text("已经满意就直接用；想换画风或造型，可以先准备一份制作描述。", "Use it as-is, or prepare instructions for a new style or appearance.")
        case .prompt: c.text("准备形象 · 1/2　把想改变的部分写清楚，复制完整提示词到自己的绘图工具。", "Prepare · 1/2. Describe what you want, then copy the full prompt to your own image tool.")
        case .result: c.text("准备形象 · 2/2　在你选择的绘图工具中完成制作，再导入 PNG 结果。", "Prepare · 2/2. Create the image in your chosen tool, then import its PNG here.")
        case .arrange: c.text("拖动图片调整位置，或使用右侧滑条微调。保持原比例，不会拉伸。", "Drag to position the image or use the sliders. Its proportions are preserved.")
        case .quota: c.text("让数字避开脸部和重要细节。左侧额度是固定示例，不是真实额度。", "Keep the label clear of the face and important details. The quota is fictional.")
        case .imageName, .packageName: c.text("确认名称和预览，保存后会出现在“我的桌宠”中。", "Review the name and preview. It will appear in My companions after saving.")
        case .imageDone, .packageDone: c.text("当前桌宠没有改变。回到“我的桌宠”，即可选择使用新形象。", "Your current companion is unchanged. Select the new one in My companions when ready.")
        case .package: c.text("角色包是一整组配套文件。请选择直接包含 character.json 的那个文件夹。", "Choose the folder directly containing character.json, not its parent folder.")
        case .check: c.text("检查形象、文件和额度显示。确认后再保存到图库，原文件不会改动。", "Review its appearance, files and quota label. Original files will not be changed.")
        }
    }
    func card<V:View>(@ViewBuilder _ content: () -> V) -> some View {
        content().padding(20).frame(maxWidth:.infinity,alignment:.leading).background(.white,in:RoundedRectangle(cornerRadius:12))
            .overlay(RoundedRectangle(cornerRadius:12).strokeBorder(WizardStyle.line))
    }
    func selectionCard<V:View>(_ selected:Bool,id:String,action:@escaping () -> Void,@ViewBuilder content:() -> V) -> some View {
        Button(action:action) {
            content().padding(20).frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
                .background(.white,in:RoundedRectangle(cornerRadius:12))
                .overlay(RoundedRectangle(cornerRadius:12).strokeBorder(selected ? WizardStyle.blue : WizardStyle.line,lineWidth:selected ? 1.5:1))
                .overlay(alignment:.topTrailing) { if selected { Image(systemName:"checkmark.circle.fill").foregroundStyle(WizardStyle.blue).padding(16).accessibilityHidden(true) } }
                .contentShape(RoundedRectangle(cornerRadius:12))
        }.buttonStyle(.plain).accessibilityIdentifier(id).accessibilityValue(selected ? c.text("已选择","Selected"):c.text("未选择","Not selected"))
    }
    func instruction(_ number:String,_ title:String,_ detail:String) -> some View {
        HStack(alignment:.top,spacing:12) {
            Text(number).font(.system(size:12,weight:.semibold)).foregroundStyle(WizardStyle.blue).frame(width:24,height:24).background(WizardStyle.pale,in:Circle())
            VStack(alignment:.leading,spacing:10) { Text(title).font(.system(size:14,weight:.semibold)); Text(detail).font(.system(size:12)).foregroundStyle(WizardStyle.secondary).fixedSize(horizontal:false,vertical:true) }
        }
    }
    func summaryRow(_ label:String,_ value:String) -> some View {
        HStack(alignment:.top,spacing:12) { Text(label).foregroundStyle(WizardStyle.secondary).frame(width:110,alignment:.leading); Text(value).frame(maxWidth:.infinity,alignment:.leading) }.font(.system(size:12))
    }
    var routeCards: some View {
        VStack(alignment:.leading,spacing:22) {
            HStack(alignment:.top,spacing:20) { routeCard(.image); routeCard(.package) }.fixedSize(horizontal:false,vertical:true)
            Label(c.text("朝夕内的图片处理均在本机完成，不会自动上传到外部服务。", "Image processing in Zhaoxi stays on this Mac. Nothing is automatically uploaded."),systemImage:"lock.shield").font(.system(size:12)).foregroundStyle(WizardStyle.secondary)
        }
    }
    private func routeCard(_ route: CompanionWizardSession.Route) -> some View {
        let image = route == .image
        return selectionCard(session.route == route,id:image ? "wizard.route.image":"wizard.route.package",action:{ session.route=route; session.error=nil }) {
            VStack(alignment:.leading,spacing:20) {
                Image(systemName:image ? "photo":"folder").font(.system(size:26)).foregroundStyle(WizardStyle.blue).frame(width:48,height:48).background(WizardStyle.pale,in:RoundedRectangle(cornerRadius:12))
                Text(image ? c.text("从图片制作","Create from an image"):c.text("导入角色包","Import a character package")).font(.system(size:19,weight:.semibold)).padding(.trailing,16)
                Text(image ? c.text("适合有成品图，或想参考图片重新制作的你。","Use a finished image, or create a new one from a reference."):c.text("适合已经有朝夕角色包文件夹的你。","Use a complete Zhaoxi character package folder."))
                    .foregroundStyle(WizardStyle.secondary).fixedSize(horizontal:false,vertical:true).frame(minHeight:48,alignment:.topLeading)
                Divider()
                Text(image ? c.text("准备：一张 PNG 图片","Bring: one PNG image"):c.text("准备：完整角色包文件夹","Bring: a complete package folder")).fontWeight(.medium)
                Text(image ? c.text("共 7 步 · 上传、调整、配置额度后保存","7 steps · Choose, arrange, add quota, save"):c.text("共 5 步 · 导入、检查效果后保存","5 steps · Import, review, save")).font(.system(size:12)).foregroundStyle(WizardStyle.secondary)
            }
        }
    }
    var naming: some View {
        HStack(alignment:.top,spacing:28) {
            card {
                VStack(spacing:16) {
                    if package,let item=session.packageDraft { WizardPackagePreview(character:item.character,quota:false,copy:c).frame(width:min(180,leftWidth-40)) }
                    else { WizardImageCanvas(draft:draft,copy:c).frame(width:min(180,leftWidth-40),height:min(180,leftWidth-40)*80/72) }
                    Text(package ? session.packageName : session.imageName).font(.system(size:18,weight:.semibold)).lineLimit(2)
                    Text(c.text("图库卡片预览 · 不叠加额度","Gallery preview · No quota overlay")).font(.system(size:11)).foregroundStyle(WizardStyle.secondary)
                }.frame(maxWidth:.infinity)
            }.frame(width:leftWidth)
            VStack(alignment:.leading,spacing:20) {
                Text(c.text("桌宠名称","Companion name")).font(.system(size:12,weight:.medium)).foregroundStyle(WizardStyle.secondary)
                TextField(c.text("输入名称","Enter a name"),text:package ? $session.packageName : $session.imageName).textFieldStyle(.roundedBorder).focused($nameFocused).accessibilityIdentifier("wizard.name")
                Text(c.text("名称需放入图库卡片：最多 16 单位，英文计 1，汉字计 2。","The name must fit the gallery card: up to 16 units, ASCII counts as 1 and other characters as 2.")).font(.system(size:12)).foregroundStyle(WizardStyle.secondary)
                if !(package ? session.packageName : session.imageName).isEmpty && !CharacterNamePolicy.valid(package ? session.packageName : session.imageName) {
                    Text(c.text("名称太长或无效，请缩短后再保存。","This name is too long or invalid. Shorten it before saving.")).font(.system(size:12)).foregroundStyle(.red)
                }
                VStack(alignment:.leading,spacing:14) {
                    summaryRow(c.text("保存方式","Save mode"),package ? c.text("复制到图库，原文件不变","Copy to gallery; keep originals") : c.text("静态桌宠 · PNG 图层","Static companion · PNG layers"))
                    summaryRow(c.text("形象尺寸","Image size"),package ? "\(session.packageDraft?.character.base.width ?? 288) × \(session.packageDraft?.character.base.height ?? 320)" : "288 × 320")
                    summaryRow(c.text("额度显示","Quota display"),package ? c.text("保留角色包设置","Keep package settings"):draft.tintEnabled ? c.text("数字与标记区域染色","Label and marked tint region"):c.text("显示数字 · 保持原图颜色","Label · Original colors"))
                }.padding(18).background(WizardStyle.soft,in:RoundedRectangle(cornerRadius:10))
                Label(c.text("保存不会自动切换当前桌宠。之后可在图库中选择使用。","Saving does not switch your current companion. Select it in the gallery later."),systemImage:"info.circle").foregroundStyle(WizardStyle.secondary)
            }.frame(maxWidth:.infinity)
        }
    }
    var completion: some View {
        HStack(alignment:.center,spacing:36) {
            if let character=session.savedCharacter { WizardPackagePreview(character:character,quota:false,copy:c).frame(width:leftWidth-36) }
            VStack(alignment:.leading,spacing:24) {
                Label(c.text("已保存到图库","Saved to the gallery"),systemImage:"checkmark.circle.fill").font(.system(size:21,weight:.semibold)).foregroundStyle(.green)
                Text(package ? session.packageName : session.imageName).font(.system(size:18,weight:.semibold))
                Text(c.text("当前桌宠没有改变。回到“我的桌宠”，点击新形象即可选择使用。","Your current companion is unchanged. Return to My companions and select the new character."))
                Divider()
                Text(session.savedCharacter?.animationFrames.isEmpty != false ? c.text("这是静态形象。需要动画时，可在桌宠编辑中导入兼容的动画角色包。","This is a static character. Import a compatible animation package in Edit later if needed.") : c.text("角色包中的动画已保留，可在桌宠编辑中管理。","Its animation is preserved. Manage it in the character editor."))
                    .font(.system(size:12)).foregroundStyle(WizardStyle.secondary)
            }.frame(maxWidth:.infinity,alignment:.leading)
        }.padding(24).frame(maxWidth:.infinity,alignment:.leading).background(WizardStyle.soft,in:RoundedRectangle(cornerRadius:12))
    }
    func copyPrompt() {
        NSPasteboard.general.clearContents()
        if NSPasteboard.general.setString(session.promptText(copy:c),forType:.string) { session.notice=c.text("完整提示词已复制。","Full prompt copied.") }
        else { session.error=c.text("无法复制，请展开完整提示词后手动复制。","Could not copy. Expand the full prompt and copy it manually.") }
    }
    func chooseImage(result:Bool) {
        let panel=NSOpenPanel(); panel.allowedContentTypes=[.png]; panel.allowsMultipleSelection=false
        panel.beginOwned(parent:dialogOwner.window) { response in if response == .OK,let url=panel.url { session.loadImage(url,result:result) } }
    }
    func choosePackage() { chooseCharacterPackage(parent:dialogOwner.window) { session.loadPackage($0) } }
    func exportExample() {
        let panel=NSOpenPanel(); panel.canChooseDirectories=true; panel.canChooseFiles=false; panel.canCreateDirectories=true
        panel.beginOwned(parent:dialogOwner.window) { response in
            guard response == .OK,let folder=panel.url else { return }
            do {
                let destination=folder.appendingPathComponent("朝夕角色包示例-\(UUID().uuidString.prefix(6))")
                let sample=ImageCharacterDraft(); sample.image=FantasyCatTexture.shared.body; sample.name="示例猫咪"
                let store=CharacterPackageStore(directory:destination), id=try store.save(sample.prepared())
                let instructions="朝夕角色包示例 / Companion package example\n选择本文件所在的 UUID 文件夹导入，不是外层目录。Choose the folder containing this guide.\ncharacter.json: v4，288×320，label 使用 72×80 逻辑坐标。\nbase.png: 原图；fill-mask.png: 染色区，可全透明；details.png: 细节，可全透明。\nv4 需要朝夕 0.2.22 或以上。不支持直接导入 GIF。建议首次使用图片制作向导。\n"
                try Data(instructions.utf8).write(to:destination.appendingPathComponent(id).appendingPathComponent("制作说明.txt"),options:.atomic)
                session.notice=c.text("示例包已导出。导入时选择含 character.json 的内部文件夹：\(id)","Example exported. Import the inner folder containing character.json: \(id)")
            } catch { session.error=error.localizedDescription }
        }
    }
}
