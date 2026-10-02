import AppKit
import SwiftUI
import QuotaCore

extension NewCompanionWizard {
    var imageUpload: some View {
        HStack(alignment:.top,spacing:28) {
            VStack(spacing:18) {
                if let image=session.source.image {
                    WizardSourceImage(image:image).frame(width:166,height:184)
                    Text(session.sourceFilename).lineLimit(2).textSelection(.enabled)
                } else {
                    Image(systemName:"photo.badge.plus").font(.system(size:40)).foregroundStyle(WizardStyle.blue).padding(.top,24)
                    Text(c.text("选择一张 PNG 图片","Choose a PNG image")).font(.system(size:17,weight:.semibold))
                    Text(c.text("文件只在本机读取，不上传云端","Read locally, never uploaded here")).font(.system(size:12)).foregroundStyle(WizardStyle.secondary)
                }
                Button(session.source.image == nil ? c.text("选择 PNG 图片","Choose PNG"):c.text("更换图片","Replace image")) { chooseImage(result:false) }.buttonStyle(WizardButtonStyle(primary:true)).accessibilityIdentifier("wizard.chooseImage")
                Text(c.text("单张 PNG · 最大 20 MB","One PNG · Up to 20 MB")).font(.system(size:11)).foregroundStyle(WizardStyle.secondary)
                if session.source.opaque { Text(c.text("这张图片没有透明背景，背景将保留。","This image has an opaque background; it will be kept.")).foregroundStyle(WizardStyle.secondary) }
            }.frame(maxWidth:.infinity).padding(20).background(WizardStyle.soft,in:RoundedRectangle(cornerRadius:12))
            VStack(alignment:.leading,spacing:22) {
                HStack(alignment:.top,spacing:16) {
                    WizardSourceImage(image:FantasyCatTexture.shared.body).frame(width:100,height:112)
                    VStack(alignment:.leading,spacing:10) {
                        Text(c.text("合适的形象示例","A suitable image")).fontWeight(.semibold)
                        Text(c.text("主体完整，四周有空白。透明背景会更自然。","Keep the whole subject with space around it. A transparent background blends naturally.")).foregroundStyle(WizardStyle.secondary)
                    }
                }
                card { VStack(alignment:.leading,spacing:12) {
                    Text(c.text("没有透明背景也可以吗？","Can I use an opaque background?")).fontWeight(.semibold)
                    Text(c.text("可以，但原背景会保留。朝夕不会自动抠图，也不支持直接导入 GIF。","Yes, but it will be kept. Zhaoxi does not remove backgrounds or import GIFs here.")).foregroundStyle(WizardStyle.secondary)
                } }
            }.frame(maxWidth:.infinity)
        }
    }
    var purposeCards: some View {
        HStack(alignment:.top,spacing:28) {
            VStack(spacing:12) {
                WizardSourceImage(image:session.source.image).frame(width:leftWidth,height:leftWidth*80/72)
                Text(session.sourceFilename).font(.system(size:12)).foregroundStyle(WizardStyle.secondary).lineLimit(2)
            }.frame(width:leftWidth)
            VStack(spacing:16) { purposeCard(.ready); purposeCard(.reference) }.fixedSize(horizontal:false,vertical:true)
        }
    }
    private func purposeCard(_ purpose:CompanionWizardSession.Purpose) -> some View {
        let ready=purpose == .ready
        return selectionCard(session.purpose == purpose,id:ready ? "wizard.purpose.ready":"wizard.purpose.reference",action:{ session.purpose=purpose }) {
            VStack(alignment:.leading,spacing:14) {
                Text(ready ? c.text("这张图可以直接使用","Use this image as-is"):c.text("我想参考它重新制作","Create a new image from this reference")).font(.system(size:16,weight:.semibold)).padding(.trailing,20)
                Text(ready ? c.text("保持当前形象，接下来只调整大小、位置和额度显示。","Keep its appearance and adjust only its size, position and quota display."):c.text("编辑提示词 → 去自己的绘图工具制作 → 导入结果。这里不会自动生成图片，也不会把参考图传出去。","Edit a prompt → create in your own image tool → import the result. This app does not generate or upload your image.")).foregroundStyle(WizardStyle.secondary).fixedSize(horizontal:false,vertical:true)
                if ready { Text(c.text("下一步：调整形象","Next: arrange the image")).font(.system(size:12,weight:.medium)).foregroundStyle(WizardStyle.blue) }
            }
        }
    }
    var promptEditor: some View {
        HStack(alignment:.top,spacing:28) {
            VStack(alignment:.leading,spacing:20) {
                promptField(c.text("角色描述 · 可以自由修改","Character · Customize freely"),hint:c.text("例如：奶油色长毛猫，蓝眼睛，坐姿，神情温柔。","For example: a cream-colored longhair cat, blue eyes, sitting calmly."),value:$session.characterDescription,id:"wizard.prompt.character")
                promptField(c.text("服装和配饰 · 可以留空","Clothing and accessories · Optional"),hint:c.text("例如：不穿衣服，保留蓬松的尾巴。","For example: no clothing; keep the fluffy tail."),value:$session.clothing,id:"wizard.prompt.clothing")
                promptField(c.text("画风 · 可以自由修改","Art style · Customize freely"),hint:c.text("例如：清晰、细腻的像素画，边缘干净。","For example: detailed pixel art with clean edges."),value:$session.artStyle,id:"wizard.prompt.style")
            }.frame(maxWidth:.infinity)
            VStack(alignment:.leading,spacing:18) {
                VStack(alignment:.leading,spacing:16) {
                    Text(c.text("制作要求 · 建议保留","Image requirements · Recommended")).font(.system(size:14,weight:.semibold))
                    Text(c.text("• 完整全身，主体居中\n• 正面或四分之三视角\n• 真正透明的背景，不是棋盘格\n• 四周少量空白\n• 不含文字、数字或水印\n• 导出为 PNG 图片","• Full body, centered\n• Front or three-quarter view\n• True transparency, not a checkerboard\n• A little space around the subject\n• No text, numbers or watermarks\n• Export as PNG"))
                        .lineSpacing(6).foregroundStyle(WizardStyle.secondary).fixedSize(horizontal:false,vertical:true)
                }.padding(18).frame(maxWidth:.infinity,alignment:.leading).background(WizardStyle.soft,in:RoundedRectangle(cornerRadius:10))
                Button(c.text("复制完整提示词","Copy full prompt"),action:copyPrompt).buttonStyle(WizardButtonStyle(primary:true)).accessibilityIdentifier("wizard.copyPrompt")
                Text(c.text("复制内容包含左侧描述和制作要求。朝夕不调用图像服务；外部工具的收费和上传规则由你自行确认。","Copies your descriptions and requirements. Zhaoxi does not call an image service. Check your tool's pricing and upload terms.")).font(.system(size:12)).foregroundStyle(WizardStyle.secondary)
                DisclosureGroup(c.text("查看完整提示词","View the full prompt")) { Text(session.promptText(copy:c)).textSelection(.enabled).font(.system(size:12)).padding(.top,8) }
            }.frame(width:(size.width-84)*0.40)
        }
    }
    private func promptField(_ label:String,hint:String,value:Binding<String>,id:String) -> some View {
        VStack(alignment:.leading,spacing:8) {
            Text(label).font(.system(size:12,weight:.medium)).foregroundStyle(WizardStyle.secondary)
            TextField(hint,text:value,axis:.vertical).lineLimit(2...5).textFieldStyle(.plain).padding(12)
                .background(.white,in:RoundedRectangle(cornerRadius:8)).overlay(RoundedRectangle(cornerRadius:8).strokeBorder(WizardStyle.line))
                .accessibilityLabel(label).accessibilityIdentifier(id)
        }
    }
    var resultImport: some View {
        HStack(alignment:.top,spacing:28) {
            VStack(alignment:.leading,spacing:24) {
                instruction("1",c.text("复制提示词","Copy the prompt"),c.text("上一页的角色描述和制作要求会一起复制。","Copies the description and requirements from the previous page."))
                instruction("2",c.text("去自己的绘图工具制作","Create in your own image tool"),c.text("粘贴提示词，并添加同一张参考图。检查主体完整、背景透明、没有水印。","Paste the prompt and attach the same reference. Check the full body, transparency and lack of watermarks."))
                instruction("3",c.text("下载 PNG，再回到这里","Download PNG and return here"),c.text("导入你确认满意的结果，原参考图会保留。","Import the result you like. The reference stays in this draft."))
                Button(c.text("重新复制提示词","Copy prompt again"),action:copyPrompt).buttonStyle(WizardButtonStyle())
            }.frame(maxWidth:.infinity)
            VStack(spacing:16) {
                HStack(alignment:.center,spacing:12) {
                    VStack(spacing:10) {
                        WizardSourceImage(image:session.source.image).frame(width:resultComparisonWidth*0.42,height:resultComparisonWidth*0.42*80/72)
                        Text(c.text("原参考图","Reference")).font(.system(size:12)).foregroundStyle(WizardStyle.secondary)
                    }
                    Image(systemName:"arrow.right").foregroundStyle(WizardStyle.secondary).accessibilityHidden(true)
                    VStack(spacing:10) {
                        WizardSourceImage(image:session.result.image).frame(width:resultComparisonWidth*0.58,height:resultComparisonWidth*0.58*80/72)
                            .overlay { if session.result.image == nil { Image(systemName:"photo.badge.plus").font(.system(size:28)).foregroundStyle(WizardStyle.blue) } }
                        Text(session.result.image == nil ? c.text("等待导入结果","Choose the result"):c.text("已导入结果","Result imported")).font(.system(size:12)).foregroundStyle(session.result.image == nil ? WizardStyle.secondary : .green)
                    }
                }
                Text(session.resultFilename).font(.system(size:12)).lineLimit(2).textSelection(.enabled)
                Button(session.result.image == nil ? c.text("导入结果图片","Import result PNG"):c.text("更换结果图片","Replace result")) { chooseImage(result:true) }.buttonStyle(WizardButtonStyle(primary:session.result.image == nil)).accessibilityIdentifier("wizard.chooseResult")
                if session.result.opaque { Text(c.text("结果图片的背景不透明，朝夕会原样保留。可返回绘图工具调整后重新导入。","The result has an opaque background, which will be kept. Adjust it in your image tool and reimport if needed.")).font(.system(size:12)).foregroundStyle(WizardStyle.secondary) }
            }.frame(width:(size.width-84)*0.48)
        }
    }
    private var resultComparisonWidth: CGFloat { (size.width-84)*0.48-44 }
    var arrangement: some View {
        HStack(alignment:.top,spacing:28) {
            VStack(spacing:10) {
                WizardImageCanvas(draft:draft,arranging:true,copy:c).frame(width:leftWidth,height:leftWidth*80/72)
                Text(c.text("透明画布 · 288 × 320 像素","Transparent canvas · 288 × 320 pixels")).font(.system(size:11)).foregroundStyle(WizardStyle.secondary)
            }.frame(width:leftWidth)
            card { VStack(alignment:.leading,spacing:24) {
                slider(c.text("缩放","Scale"),value:Binding(get:{draft.zoom},set:{draft.zoom=$0}),range:0.25...3,display:String(format:"%.0f%%",draft.zoom*100))
                slider(c.text("横向位置","Horizontal position"),value:Binding(get:{Double(draft.offset.x)},set:{draft.offset.x=$0}),range:-288...288,display:String(format:"%.0f",draft.offset.x))
                slider(c.text("纵向位置","Vertical position"),value:Binding(get:{Double(draft.offset.y)},set:{draft.offset.y=$0}),range:-320...320,display:String(format:"%.0f",draft.offset.y))
                Button(c.text("重置位置","Reset position")) { draft.offset = .zero; draft.zoom=1 }.buttonStyle(WizardButtonStyle())
                Text(c.text("让耳朵、脚和尾巴都留在画布内。","Keep the ears, feet and tail inside the canvas.")).font(.system(size:12)).foregroundStyle(WizardStyle.secondary)
            } }
        }
    }
    var quotaEditor: some View {
        HStack(alignment:.top,spacing:28) {
            WizardImageCanvas(draft:draft,showQuota:true,showBounds:true,brush:brush,erasing:erasing,sample:sample,copy:c).frame(width:leftWidth,height:leftWidth*80/72)
            VStack(alignment:.leading,spacing:18) {
                slider(c.text("数字横向位置","Label X"),value:Binding(get:{draft.label.x},set:{draft.label.x=$0}),range:0...(72-draft.label.width))
                slider(c.text("数字纵向位置","Label Y"),value:Binding(get:{draft.label.y},set:{draft.label.y=$0}),range:0...(80-draft.label.height))
                HStack(spacing:20) {
                    slider(c.text("显示范围宽度","Label width"),value:Binding(get:{draft.label.width},set:{draft.label.width=$0}),range:28...(72-draft.label.x))
                    slider(c.text("显示范围高度","Label height"),value:Binding(get:{draft.label.height},set:{draft.label.height=$0}),range:22...(80-draft.label.y))
                }
                Divider()
                HStack {
                    Text(c.text("区域染色（可选）","Tint region (optional)")).fontWeight(.semibold); Spacer()
                    SettingsNativeSwitch(title:c.text("区域染色","Tint region"),isOn:Binding(get:{draft.tintEnabled},set:{draft.tintEnabled=$0}),highContrast:NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast).frame(width:40,height:24)
                }
                if draft.tintEnabled {
                    HStack {
                        Picker(c.text("工具","Tool"),selection:$erasing) { Text(c.text("画笔","Brush")).tag(false); Text(c.text("橡皮","Eraser")).tag(true) }.pickerStyle(.segmented).labelsHidden().frame(maxWidth:200)
                        Spacer()
                        Button(c.text("撤销","Undo")) { draft.undo() }.disabled(!draft.canUndo)
                        Button(c.text("清空","Clear")) { draft.clearMask() }.disabled(draft.strokes.isEmpty)
                    }.buttonStyle(WizardButtonStyle())
                    slider(c.text("画笔大小","Brush size"),value:$brush,range:2...40)
                    slider(c.text("示例额度","Sample quota"),value:$sample,range:0...100,display:"\(Int(sample))%")
                    Text(c.text("只影响标记区域内可见的图像，不给透明背景填色。关闭后保留本次标记。","Only marked, visible pixels are tinted; transparent background stays clear. Turning this off keeps your marks.")).font(.system(size:12)).foregroundStyle(WizardStyle.secondary)
                } else {
                    Text(c.text("关闭时保持原图颜色，只显示额度数字。开启后，可用画笔标记随额度变化的填色区域。","When off, the original colors stay and only the quota label is shown. Turn it on to paint a region that fills with quota.")).foregroundStyle(WizardStyle.secondary)
                }
            }.frame(maxWidth:.infinity)
        }
    }
    private func slider(_ title:String,value:Binding<Double>,range:ClosedRange<Double>,display:String? = nil) -> some View {
        VStack(alignment:.leading,spacing:7) {
            HStack { Text(title).fontWeight(.medium); Spacer(); Text(display ?? String(format:"%.0f",value.wrappedValue)).monospacedDigit() }
            SettingsAdjustmentSlider(value:value,range:range,title:title).frame(height:24)
        }
    }
    var packageUpload: some View {
        VStack(alignment:.leading,spacing:22) {
            HStack(alignment:.top,spacing:24) {
                VStack(spacing:20) {
                    Image(systemName:"folder").font(.system(size:40)).foregroundStyle(WizardStyle.blue)
                    Text(session.packageDraft == nil ? c.text("选择完整文件夹","Choose a complete folder"):session.packageFilename).font(.system(size:17,weight:.semibold)).lineLimit(2)
                    Text(c.text("不是单张 PNG、GIF，也不是压缩包","Not a single PNG, GIF or ZIP file")).font(.system(size:12)).foregroundStyle(WizardStyle.secondary)
                    Button(session.packageDraft == nil ? c.text("选择角色包文件夹","Choose package folder"):c.text("重新选择文件夹","Choose another folder"),action:choosePackage).buttonStyle(WizardButtonStyle(primary:true)).disabled(session.loading).accessibilityIdentifier("wizard.choosePackage")
                    if session.packageDraft != nil { Label(c.text("检查通过，可继续","Checked and ready to continue"),systemImage:"checkmark.circle").foregroundStyle(.green) }
                }.padding(24).frame(maxWidth:.infinity,minHeight:240).background(WizardStyle.soft,in:RoundedRectangle(cornerRadius:12))
                card { VStack(alignment:.leading,spacing:18) {
                    Text(c.text("文件夹里通常包含","The folder usually contains")).font(.system(size:14,weight:.semibold))
                    summaryRow("character.json",c.text("角色说明","Manifest"))
                    summaryRow("base.png",c.text("原始形象","Original image"))
                    summaryRow("fill-mask.png",c.text("染色区域","Tint region"))
                    summaryRow("details.png",c.text("细节图层","Detail layer"))
                    Text(c.text("动画角色包还包含对应帧文件。","Animated packages also include frame files.")).font(.system(size:11)).foregroundStyle(WizardStyle.secondary)
                } }
            }
            HStack {
                Button(c.text("导出示例包","Export example package"),action:exportExample)
                Button(c.text("查看制作说明","View package instructions")) { guide.toggle() }
            }.buttonStyle(WizardButtonStyle()).disabled(session.loading)
            if guide {
                Text(c.text("1. 导出示例包，打开其中的制作说明。\n2. 用绘图工具准备同尺寸 PNG 图层，按示例保留文件名。\n3. 选择直接包含 character.json 的文件夹进行检查。\nv1 为 72×80；v2/v3/v4 为 288×320。v3 动画还需对应帧文件。v4 支持透明填色图层，需要朝夕 0.2.22 或以上。","1. Export the example and open its guide.\n2. Prepare matching PNG layers with the example's filenames.\n3. Choose the folder directly containing character.json.\nv1 uses 72×80; v2/v3/v4 use 288×320. v3 animation also needs frame files. v4 supports an empty tint mask and requires Zhaoxi 0.2.22 or later."))
                    .font(.system(size:12)).foregroundStyle(WizardStyle.secondary).textSelection(.enabled)
            }
            Text(c.text("还没有角色包？可返回第一步，选择更简单的图片制作。","No package yet? Go back and choose the simpler image workflow.")).font(.system(size:12)).foregroundStyle(WizardStyle.secondary)
        }
    }
    var packageCheck: some View {
        HStack(alignment:.top,spacing:28) {
            if let item=session.packageDraft {
                WizardPackagePreview(character:item.character,quota:true,copy:c).frame(width:leftWidth)
                VStack(alignment:.leading,spacing:28) {
                    Label(c.text("检查通过","Checks passed"),systemImage:"checkmark.circle.fill").foregroundStyle(.green).font(.system(size:14,weight:.semibold))
                    instruction("✓",c.text("文件齐全","Files are complete"),c.text("角色说明、原图、染色区域和细节图层均可读取。","The manifest, image, tint mask and detail layer can all be read."))
                    instruction("✓",c.text("格式与尺寸符合要求","Format and size are valid"),"\(item.character.base.width) × \(item.character.base.height) · v\(item.prepared.manifest.version)")
                    instruction("✓",c.text("可以继续保存","Ready to save"),item.character.animationFrames.isEmpty ? c.text("这是静态形象，没有动画。左侧显示固定示例额度 79%。","A static character without animation. The preview uses a fixed 79% quota."):c.text("角色包包含动画，可在左侧主动播放检查。额度为固定示例 79%。","The package includes animation. Play it to check it. The quota is a fixed 79%."))
                    Button(c.text("重新选择文件夹","Choose another folder")) { session.back() }.buttonStyle(WizardButtonStyle())
                }.frame(maxWidth:.infinity,alignment:.leading)
            }
        }
    }
}
