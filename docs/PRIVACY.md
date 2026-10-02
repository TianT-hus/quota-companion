# 朝夕 · 隐私说明 / Zhaoxi Privacy

本说明对应朝夕 0.2.31（build 47）。

## 本地数据

应用通过本机官方 `codex app-server` 读取 `limitId = codex` 的额度窗口。持久化的额度快照不包含账户标识、令牌、邮箱、原始认证响应或重置券明细。官方 Codex 自身的网络通信由 Codex 管理。

应用还在本机保存偏好、日程、待办及关联、语音配置、声音条目与操作状态、角色和背景。声音 ID 和克隆操作记录用于恢复未完成的远端操作；它们不包含服务商 API Key。取消本地声音草稿会清理其临时材料；已提交给服务商的音频或声音不会仅因取消本地向导而自动撤回，需按应用的删除流程及服务商政策处理。

本地角色和卡片背景不会由应用上传。自选背景重新编码为最长边不超过 2048px 的 PNG，不复制原图的 GPS、拍摄时间或评论等元数据。恢复默认不删除用户原图。

## 用户启用的外部功能

- **云语音与 API 测试**：配置阿里云百炼或 MiniMax、同意相关说明并使用云语音后，实际播报文本会发送到所选官方 HTTPS 接口。文本可能包含日程标题、时间、额度或用户自定义文案；API 测试也会向所选服务发起请求。费用及数据处理遵循所选服务商政策。
- **声音克隆**：只有用户选择录音或导入、确认声音使用授权、上传及费用后，才提交处理后的音频用于远端建声。麦克风权限只在主动录音时请求。预览、查询和删除远端声音也需要请求对应服务商。
- **密钥**：服务商 API Key 写入 macOS 钥匙串，不写入偏好、声音操作记录或测试快照。使用时可能短暂缓存在内存中；缓存设有时限，并在锁屏、休眠或会话失活时清理。系统可能要求用户批准钥匙串访问。
- **Apple 提醒事项**：用户授权完整访问并选定列表后，可读取和修改该列表中的事项以实现双向同步。所选列表可能由系统同步到 iCloud 或其他账户；本地待办不会仅因打开应用而自动上传。
- **系统声音与翻译**：调用 macOS 的声音和翻译功能；准备语言资源时，macOS 可能按需下载资源。未准备翻译资源时不应把跨语言播报当作可用。
- **跟随 Codex 与登录启动**：用户主动启用后通过系统服务管理启动；跟随辅助程序观察本机应用启动/退出，不读取日程或额度内容。

公开文档与插件图标使用维护者指定的蓝色礼裙桌宠展示图，图中的额度为合成示例，图像文件不含 EXIF 或文本元数据。原始照片、完整个人角色包、真实日程、录音和密钥不随这次文档更新公开。0.2.31 安装包的资源范围以该版本附件为准。不要在公开 issue 或日志中粘贴个人数据，安全问题使用 [私密报告入口](https://github.com/TianT-hus/quota-companion/security/advisories/new)。

## English summary

Zhaoxi stores sanitized quota snapshots, schedules, todos, companion assets and settings locally. Optional cloud speech sends announcement text to the selected provider; confirmed voice cloning uploads processed audio and may incur charges. Provider keys are stored in macOS Keychain, with a short-lived in-memory cache. Authorized Reminders lists can synchronize through their system accounts. Local backgrounds and character assets are not uploaded by the app. Public documentation uses a maintainer-designated blue-gown companion preview with synthetic quota data; original photos, full personal character packages, recordings and credentials are not included.
