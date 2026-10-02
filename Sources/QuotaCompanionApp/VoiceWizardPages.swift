import SwiftUI

extension PersonalVoiceWizard {
    var platformPage: some View {
        VStack(alignment:.leading,spacing:20) {
            HStack(alignment:.top,spacing:20) {
                ForEach(APIProvider.allCases,id:\.self) { vendor in
                    choice(selected:draft.provider == vendor,id:"voiceWizard.provider.\(vendor.rawValue)",action:{draft.selectProvider(vendor)}) {
                        VStack(alignment:.leading,spacing:16) {
                            Text(vendor.name).font(.system(size:18,weight:.semibold)).padding(.trailing,24)
                            Label(speech.configuredProviders.contains(vendor) ? c.text("已保存平台配置","Configuration saved"):c.text("尚未配置","Not configured"),systemImage:speech.configuredProviders.contains(vendor) ? "checkmark.circle":"person.crop.circle.badge.plus")
                                .foregroundStyle(speech.configuredProviders.contains(vendor) ? WizardStyle.blue:WizardStyle.secondary)
                            Text(vendor == .bailian ? c.text("使用你的阿里云百炼账户创建声音。","Create a voice using your Alibaba Cloud Bailian account."):c.text("使用你的 MiniMax 账户创建声音。","Create a voice using your MiniMax account.")).foregroundStyle(WizardStyle.secondary).fixedSize(horizontal:false,vertical:true)
                            Text(c.text("录音只会发送到你选择的平台。","Your recording goes only to the provider you select.")).font(.system(size:12)).foregroundStyle(WizardStyle.secondary)
                        }
                    }
                }
            }
            HStack {
                Button(c.text("配置平台账户","Configure provider account")) { configure=true }.buttonStyle(WizardButtonStyle()).accessibilityIdentifier("voiceWizard.configure")
                Text(speech.configuredProviders.contains(draft.provider) ? c.text("可以继续。此处不会读取密钥或测试连接。","Ready to continue. No key is read and no connection is tested here."):c.text("请先保存所选平台的 API 配置，再继续。","Save the selected provider's API configuration before continuing.")).font(.system(size:12)).foregroundStyle(WizardStyle.secondary)
            }
            DisclosureGroup(c.text("第一次使用？查看账号准备步骤","First time? View account setup steps"),isExpanded:$guide) {
                VStack(alignment:.leading,spacing:12) {
                    Text(c.text("1. 进入所选平台的官方控制台，注册并登录。\n2. 按平台要求开通服务并完成认证；MiniMax 需要个人或企业认证。\n3. 在平台创建 API Key（密钥）。\n4. 点击“配置平台账户”，编辑相同平台并保存。\n5. 关闭配置窗口，回到这里继续。无需填写模型或音色 ID。","1. Open the selected provider's official console and sign in.\n2. Enable the service and complete required verification; MiniMax requires personal or company verification.\n3. Create an API key.\n4. Choose Configure provider account and save it for the same provider.\n5. Close configuration and continue here. No model or voice IDs needed.")).lineSpacing(5).textSelection(.enabled)
                    Link(c.text("打开所选平台控制台","Open selected provider console"),destination:URL(string:draft.provider == .bailian ? "https://bailian.console.aliyun.com/":"https://platform.minimax.cn/")!)
                }.padding(.top,10)
            }.accessibilityIdentifier("voiceWizard.guide")
            note(c.text("云端复刻可能产生创建、激活和后续播报费用。朝夕不承诺免费或固定总价。","Cloud cloning may incur creation, activation and ongoing speech fees. No free use or fixed total is promised."),icon:"cloud")
            billingLinks(c).font(.system(size:12))
        }
    }
    var methodPage: some View {
        VStack(alignment:.leading,spacing:22) {
            HStack(alignment:.top,spacing:20) {
                methodCard(.record); methodCard(.file)
            }
            note(c.text("无论哪种方式，都请使用本人或已获授权的声音。准备样本不上传；第三步确认后才会发送给平台。","Use your own voice or one you have permission to use. Preparing a sample is local; it is sent only after confirmation in step 3."),icon:"lock.shield")
            if draft.audio != nil { sampleCard }
        }
    }
    private func methodCard(_ method:VoiceWizardSession.Method) -> some View {
        choice(selected:draft.method == method,id:method == .record ? "voiceWizard.method.record":"voiceWizard.method.file",action:{draft.method=method}) {
            VStack(alignment:.leading,spacing:18) {
                Image(systemName:method == .record ? "mic":"waveform.badge.plus").font(.system(size:28)).foregroundStyle(WizardStyle.blue)
                Text(method == .record ? c.text("直接录音","Record here"):c.text("导入音频","Import a recording")).font(.system(size:18,weight:.semibold))
                Text(method == .record ? c.text("没有现成录音？跟着示范文案，用平常说话的声音录一段。","No recording yet? Read the sample text in your everyday voice."):c.text("已经有一段清晰录音？选择本机音频文件，检查后就能继续。","Already have a clear recording? Choose a local audio file and check it here.")).foregroundStyle(WizardStyle.secondary).fixedSize(horizontal:false,vertical:true)
                Text(method == .record ? c.text("准备：麦克风 · 建议 15～20 秒","Need: microphone · Aim for 15–20 seconds"):c.text("准备：WAV、MP3 或 M4A 文件","Need: a WAV, MP3 or M4A file")).font(.system(size:12,weight:.medium))
                Text(method == .record ? c.text("点击开始录音时才申请麦克风权限。","Microphone permission is requested only when you start recording."):c.text("无需麦克风权限，原文件不改动。","No microphone permission needed. Originals stay unchanged.")).font(.system(size:12)).foregroundStyle(WizardStyle.secondary)
            }
        }
    }
    var recordPage: some View {
        HStack(alignment:.top,spacing:24) {
            VStack(alignment:.leading,spacing:18) {
                card {
                    VStack(alignment:.leading,spacing:14) {
                        Text(c.text("示范文案 · 可以自由朗读","Sample script · Your own words are welcome")).fontWeight(.semibold)
                        Text(c.text(voiceReadingExample,"Hello, this is my everyday voice. Today I will organize my work at my own pace, prepare my notes, and finish the most important tasks. When it is time for a break, please remind me gently so each day feels clear and well organized."))
                            .font(.system(size:15)).lineSpacing(7).textSelection(.enabled).fixedSize(horizontal:false,vertical:true)
                    }
                }
                note(c.text("安静环境、单人说话、没有音乐。不唱歌，不刻意模仿播音腔，也不必逐字匹配。","Choose a quiet room with one speaker and no music. Speak naturally; do not sing or force a presenter voice. Exact wording is optional."),icon:"ear")
            }.frame(maxWidth:.infinity)
            VStack(alignment:.leading,spacing:18) {
                Text(c.text("录音设备","Recording device")).fontWeight(.semibold)
                SettingsPicker(c.text("输入设备","Input device"),selection:$recorder.inputID,options:recorder.inputs.map { SettingsChoice($0.id,$0.name) }).disabled(busy)
                Button(c.text("刷新设备","Refresh devices")) { recorder.refreshInputs() }.buttonStyle(WizardButtonStyle()).disabled(busy)
                VStack(spacing:14) {
                    Text(String(format:"%02d:%02d",Int(recorder.elapsed)/60,Int(recorder.elapsed)%60)).font(.system(size:32,weight:.medium,design:.monospaced))
                    ProgressView(value:recorder.level).tint(WizardStyle.blue).accessibilityLabel(c.text("麦克风音量","Microphone level"))
                    Text(recorder.recording ? c.text("正在录音 · 最长 60 秒","Recording · Up to 60 seconds"):c.text("点击下方按钮开始","Start when you are ready")).font(.system(size:12)).foregroundStyle(WizardStyle.secondary)
                    if recorder.recording {
                        Button(c.text("停止录音","Stop recording")) { recorder.stop() }.buttonStyle(WizardButtonStyle(primary:true)).accessibilityIdentifier("voiceWizard.record.stop")
                    } else {
                        Button(draft.recording == nil ? c.text("开始录音","Start recording"):c.text("重新录音","Record again")) { draft.record() }.buttonStyle(WizardButtonStyle(primary:true)).disabled(busy).accessibilityIdentifier("voiceWizard.record.start")
                    }
                }.padding(20).frame(maxWidth:.infinity).background(WizardStyle.soft,in:RoundedRectangle(cornerRadius:12))
                if draft.audio != nil { sampleCard }
                note(c.text("不能使用麦克风？点“上一步”，选择导入音频。","Cannot use a microphone? Go back and choose Import a recording."))
            }.frame(width:(size.width-84)*0.42)
        }
    }
    var importPage: some View {
        HStack(alignment:.top,spacing:24) {
            VStack(spacing:20) {
                Image(systemName:"waveform").font(.system(size:44)).foregroundStyle(WizardStyle.blue)
                Text(c.text("选择本机录音文件","Choose a local recording")).font(.system(size:18,weight:.semibold))
                Text("WAV / MP3 / M4A").foregroundStyle(WizardStyle.secondary)
                Button(draft.audio == nil ? c.text("选择音频文件","Choose audio file"):c.text("重新选择文件","Choose another file"),action:chooseAudio).buttonStyle(WizardButtonStyle(primary:true)).disabled(busy).accessibilityIdentifier("voiceWizard.import")
                Text(c.text("不会上传 · 不改动原文件","No upload · Original file stays unchanged")).font(.system(size:12)).foregroundStyle(WizardStyle.secondary)
                if draft.audio != nil { sampleCard }
            }.padding(22).frame(maxWidth:.infinity).background(WizardStyle.soft,in:RoundedRectangle(cornerRadius:12))
            VStack(alignment:.leading,spacing:24) {
                Text(c.text("怎样的录音更合适？","What makes a suitable recording?")).font(.system(size:17,weight:.semibold))
                Text(c.text("只有一个人在说话，声音清楚，没有背景音乐。推荐 15～20 秒，保持自然语速。","Use clear speech from one person, with no background music. Aim for 15–20 seconds at your natural pace.")).lineSpacing(5)
                card { VStack(alignment:.leading,spacing:14) {
                    Text(draft.provider.name).fontWeight(.semibold)
                    Text(draft.provider == .bailian ? c.text("本应用接收：3～60 秒，最大 10 MB。","Accepted here: 3–60 seconds, up to 10 MB."):c.text("本应用接收：10 秒～5 分钟，最大 20 MB。","Accepted here: 10 seconds–5 minutes, up to 20 MB."))
                } }
                note(c.text("只转换本地临时副本，不自动截短、去噪或识别多人声。文件有问题时会保留上一次合格样本。","Only a temporary local copy is converted. No automatic trimming, denoising or speaker detection. If a file fails checks, the previous valid sample is kept."))
            }.frame(maxWidth:.infinity)
        }
    }
    var sampleCard: some View {
        card { VStack(alignment:.leading,spacing:12) {
            Label(c.text("已准备的样本","Prepared sample"),systemImage:"checkmark.circle").foregroundStyle(WizardStyle.blue).fontWeight(.medium)
            Text(draft.filename).lineLimit(2).textSelection(.enabled)
            if let audio=draft.audio { Text(String(format:"%.1f s · %.2f MB",audio.duration,Double(audio.bytes)/1048576)).monospacedDigit().foregroundStyle(WizardStyle.secondary) }
            HStack(spacing:10) {
                Button(c.text("回听","Play sample")) { if let audio=draft.audio { do { try recorder.play(audio.url) } catch { draft.error=CloudSpeechError.audio.message(c) } } }.disabled(busy).accessibilityIdentifier("voiceWizard.sample.play")
                Button(c.text("停止","Stop")) { recorder.stopPlayback() }
            }.buttonStyle(WizardButtonStyle())
            if draft.recording != nil { Button(c.text("导出本次录音","Export this recording"),action:exportRecording).buttonStyle(WizardButtonStyle()).disabled(busy) }
        } }
    }
    var reviewPage: some View {
        HStack(alignment:.top,spacing:24) {
            VStack(alignment:.leading,spacing:18) {
                card { VStack(alignment:.leading,spacing:16) {
                    summary(c.text("发送到","Send to"),draft.provider.name)
                    summary(c.text("用途","Purpose"),c.text("创建个人播报音色","Create a personal announcement voice"))
                    Text(c.text("声音名称","Voice name")).fontWeight(.medium)
                    TextField(c.text("例如：我的日常声音","For example: My everyday voice"),text:$draft.name).textFieldStyle(.roundedBorder).disabled(current != nil || busy).accessibilityIdentifier("voiceWizard.name")
                    Text(c.text("1～30 个字符，仅用于在声音列表中识别。","1–30 characters, used to identify it in your voice list.")).font(.system(size:12)).foregroundStyle(WizardStyle.secondary)
                    if !draft.name.isEmpty && !PersonalVoice.validName(draft.name) { Text(c.text("名称不能为空或超过 30 个字符。","Enter a nonblank name of at most 30 characters.")).foregroundStyle(.red) }
                } }
                if draft.audio != nil { sampleCard }
            }.frame(maxWidth:.infinity)
            VStack(alignment:.leading,spacing:18) {
                Text(c.text("上传前，请确认","Before you upload")).font(.system(size:17,weight:.semibold))
                Text(c.text("录音会发送到所选平台用于云端复刻。创建、激活和后续播报可能计费，以平台规则为准。","Your recording will be sent to the selected provider for cloud cloning. Creation, activation and later speech may incur charges under its terms.")).lineSpacing(5)
                Toggle(c.text("这是我的声音，或我已获得声音主人的授权","This is my voice, or I have the speaker's permission"),isOn:$draft.rights).toggleStyle(.checkbox).disabled(current != nil || busy).accessibilityIdentifier("voiceWizard.rights")
                Toggle(c.text("我同意上传到所选平台，并了解可能产生费用","I agree to upload and understand possible charges"),isOn:$draft.consent).toggleStyle(.checkbox).disabled(current != nil || busy).accessibilityIdentifier("voiceWizard.consent")
                billingLinks(c).font(.system(size:12))
                note(c.text("本地已检查可解码性、时长、大小和明显静音，不保证平台接受或验证声音身份。","Local checks cover decoding, duration, size and obvious silence. They do not guarantee acceptance or verify identity."))
                if let current {
                    Divider()
                    Text(current.state.title(c)).fontWeight(.semibold)
                    if controller.hasRecovery(current) && current.state != .pending {
                        note(c.text("云端声音已保留。只重试本地保存，不会再次创建。","The cloud voice is retained. Retry only local saving, without creating again."))
                        Button(c.text("仅重试本地保存","Retry local save only")) { controller.retrySave(current,copy:c); draft.synchronize() }.disabled(busy)
                    } else if current.state == .pending {
                        note(c.text("还不能确认平台是否创建成功。请主动查询，不要重新提交；关闭向导后也可在管理页查询。","The provider result is not yet confirmed. Check explicitly; do not submit again. You can also check later in Manage my voices."))
                        Button(c.text("查询创建结果","Check creation result")) { controller.check(current,copy:c) }.disabled(busy).accessibilityIdentifier("voiceWizard.check")
                    }
                }
            }.frame(maxWidth:.infinity).buttonStyle(WizardButtonStyle())
        }
    }
    var previewPage: some View {
        HStack(alignment:.top,spacing:24) {
            VStack(alignment:.leading,spacing:20) {
                card { VStack(alignment:.leading,spacing:16) {
                    Image(systemName:"waveform").font(.system(size:36)).foregroundStyle(WizardStyle.blue)
                    Text(current?.name ?? draft.name).font(.system(size:19,weight:.semibold))
                    Text(draft.provider.name+" · "+(current?.state.title(c) ?? c.text("待确认","Unconfirmed"))).foregroundStyle(WizardStyle.secondary)
                    Text(c.text("固定试听文案","Fixed preview text")).fontWeight(.medium)
                    Text(SpeechTemplate.standard(.schedule,chinese:speech.cloudLanguage == .chinese).example(Copybook(language:speech.cloudLanguage == .chinese ? .zhHans:.english),language:speech.cloudLanguage))
                        .font(.system(size:15)).lineSpacing(6).textSelection(.enabled).fixedSize(horizontal:false,vertical:true)
                    HStack {
                        Button(current.map { controller.hasCachedPreview($0) } == true ? c.text("回放试听","Replay preview"):c.text("生成试听","Generate preview")) { requestPreview(regenerate:false) }.buttonStyle(WizardButtonStyle(primary:true)).disabled(busy).accessibilityIdentifier("voiceWizard.preview")
                        Button(c.text("停止","Stop")) { controller.stopAudio() }.buttonStyle(WizardButtonStyle())
                    }
                    if current.map({controller.hasCachedPreview($0)}) == true {
                        Text(c.text("这段试听已缓存，回放不再请求。","This preview is cached. Replaying makes no new request.")).font(.system(size:12)).foregroundStyle(WizardStyle.secondary)
                    }
                } }
                Button(c.text("重新生成试听（可能再次计费）","Regenerate preview (may incur charges)")) { requestPreview(regenerate:true) }.buttonStyle(WizardButtonStyle()).disabled(busy)
            }.frame(maxWidth:.infinity)
            VStack(alignment:.leading,spacing:20) {
                Text(c.text("听什么，怎么判断？","What should I listen for?")).font(.system(size:17,weight:.semibold))
                Text(c.text("听音色是否像自己，发音是否清楚、节奏是否自然。不满意可以返回准备样本；已有云端声音不会被静默删除。","Listen for a familiar tone, clear pronunciation and natural pacing. You can prepare another sample; the existing cloud voice will not be silently deleted.")).lineSpacing(5)
                note(previewBilling(c,provider:draft.provider),icon:"cloud")
                note(c.text("只使用虚构日程，不读取你的真实安排。生成失败时保留已创建的音色。","Uses a fictional schedule, never your real events. A failed preview does not remove the created voice."),icon:"lock.shield")
                if let current,current.warning != nil { note(c.text("平台提示可能采用备用复刻效果，请仔细试听。","The provider reported a fallback voice. Review it carefully."),icon:"exclamationmark.triangle") }
                if let current,controller.hasRecovery(current) { Button(c.text("仅重试本地保存","Retry local save only")) { controller.retrySave(current,copy:c) }.disabled(busy) }
                Button(c.text("不满意，重新准备样本","Prepare another sample")) { confirmation = .rerecord }.disabled(busy)
                Button(c.text("稍后再试听，先关闭","Preview later and close"),action:requestClose).disabled(busy)
                if !draft.verified { Text(c.text("正式合成验证成功后，才可进入完成步骤。","Successful synthesis verification is required before the final step.")).font(.system(size:12)).foregroundStyle(WizardStyle.secondary) }
            }.frame(maxWidth:.infinity).buttonStyle(WizardButtonStyle())
        }
    }
    var finishPage: some View {
        HStack(alignment:.top,spacing:24) {
            card { VStack(alignment:.leading,spacing:22) {
                Image(systemName:draft.page == .done ? "checkmark.circle.fill":"waveform.circle").font(.system(size:42)).foregroundStyle(draft.page == .done ? .green:WizardStyle.blue)
                Text(current?.name ?? draft.name).font(.system(size:21,weight:.semibold))
                summary(c.text("平台","Provider"),draft.provider.name)
                summary(c.text("声音状态","Voice status"),current?.state.title(c) ?? "")
                summary(c.text("播报语言","Speech language"),speech.cloudLanguage.title)
                Text(draft.applied ? c.text("当前播报声音已切换。","Your announcement voice has been switched."):c.text("当前播报声音没有改变。","Your current announcement voice is unchanged.")).foregroundStyle(WizardStyle.blue)
            } }.frame(maxWidth:.infinity)
            VStack(alignment:.leading,spacing:22) {
                Text(c.text("日常使用前，了解这些","For everyday use")).font(.system(size:17,weight:.semibold))
                Text(c.text("选择“用于日常播报”会应用到当前播报语言，供日程与额度语音提醒使用，不会自动开启原本关闭的播报。","Use for announcements applies this voice to the current speech language for schedule and quota speech. Announcements that are off stay off.")).lineSpacing(5)
                VStack(alignment:.leading,spacing:14) {
                    summary(c.text("日程播报","Schedule speech"),speech.scheduleEnabled ? c.text("开启","On"):c.text("关闭","Off"))
                    summary(c.text("额度语音提醒","Quota speech"),speech.configuration.value.quota.enabled && speech.configuration.value.quota.delivery.spoken ? c.text("开启","On"):c.text("关闭","Off"))
                }
                note(c.text("日常播报需要联网和可用的平台账户，并可能持续产生合成费用。","Daily announcements need an internet connection and a valid provider account, and may incur synthesis charges."),icon:"network")
                note(c.text("关闭后清理本次临时音频，但云端音色仍保留。平台上传数据的保留政策以官方说明为准。","Closing clears this session's temporary audio, not the cloud voice. Provider retention rules apply to uploaded data."),icon:"lock.shield")
            }.frame(maxWidth:.infinity)
        }
    }
    private func choice<V:View>(selected:Bool,id:String,action:@escaping ()->Void,@ViewBuilder content:()->V) -> some View {
        Button(action:action) {
            content().padding(20).frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
                .background(.white,in:RoundedRectangle(cornerRadius:12))
                .overlay(RoundedRectangle(cornerRadius:12).strokeBorder(selected ? WizardStyle.blue:WizardStyle.line,lineWidth:selected ? 1.5:1))
                .overlay(alignment:.topTrailing) { if selected { Image(systemName:"checkmark.circle.fill").foregroundStyle(WizardStyle.blue).padding(16).accessibilityHidden(true) } }
                .contentShape(RoundedRectangle(cornerRadius:12))
        }.buttonStyle(.plain).accessibilityIdentifier(id).accessibilityValue(selected ? c.text("已选择","Selected"):c.text("未选择","Not selected"))
    }
}
