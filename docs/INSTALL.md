# 安装和手动升级

需要 macOS 14 或更新版本。通用包同时包含 arm64 和 x86_64；构建架构检查不等同于 Intel 真机验证。

1. 在自己的 Mac 安装并登录 Codex。不要复制他人的认证目录，也不要把密钥发到聊天或 issue 中。
2. 从维护者已确认的 Release 下载对应 ZIP 和 `SHA256SUMS`，在下载目录运行 `shasum -a 256 -c SHA256SUMS`。校验文件完整性不能代替开发者身份验证。
3. **当前只提供 ad-hoc 测试包，未经过 Apple 公证**。优先自行审查并从源码构建；受信任的测试者如选择例外打开，请参照 [Apple 的单应用打开说明](https://support.apple.com/102445)。不要全局关闭 Gatekeeper。企业策略可能禁止例外。
4. 首次安装可将 app 移入“应用程序”。升级时先从菜单栏退出旧版，再替换同名 app。保留 `~/Library/Application Support/QuotaCompanion` 以及对应偏好设置，不要为升级清空配置。启动后检查角色、背景、位置、设置和额度连接。
5. 只有需要对话内工具时才安装随包插件；添加市场和安装插件是两个步骤。升级后在 Codex 插件管理界面更新/重装该本地插件，并开启新会话。

CLI 查找顺序：设置中的自定义可执行路径，ChatGPT/Codex app 的 Resources 中的 `codex`，`/opt/homebrew/bin/codex`、`/usr/local/bin/codex`，最后查找进程 `PATH`。Finder 启动的 app 可能没有终端中的 PATH；可在“连接与高级”填写自定义路径并刷新。插件在 app 运行时优先读取本地 socket；app 未运行时 helper 使用默认 CLI 搜索，所以自定义路径用户应先启动 app。

本地源码预览不会主动覆盖已安装 app。要在现有运行版旁验证候选包，必须使用 [隔离模式](RELEASE.md)，不要直接双击第二个同 Bundle ID 实例。
