# 隐私说明 / Privacy

应用在本机启动官方 `codex app-server`，读取主 Codex 桶的额度窗口。应用本身没有遥测、广告、远端数据库或上传接口；官方 CLI 会使用当前用户的本机登录并按其自身机制连接 OpenAI。账户登录由 Codex 管理，应用不提供代登录或账号共享。

本地目录 `~/Library/Application Support/QuotaCompanion` 保存额度快照、提醒去重状态、处理后的背景和角色；偏好设置沿用 `dev.quota-companion.mac`。快照包含额度百分比、窗口长度和重置/观察时间，不含令牌、邮箱、账户 ID、原始认证响应或重置券。不要把真实快照、诊断日志或偏好文件附到公开 issue。

背景经方向校正、缩采样并重新编码为最长边 2048px 的 PNG；角色包按 v1/v2 校验、重新编码并剥离图片元数据。恢复默认不删除用户原图。旧版宠物图导入功能可能按原文件复制；用户资料目录始终应按私人数据处理。

MCP 读取额度时，结果会进入当前 Codex 会话，并受该会话的数据处理规则约束。它不会把额度变成公开数据。Unix socket 限当前用户读写；同一用户权限下的其他进程可能读取本地数据。公开代码与发布包只包含内置素材和明确的合成示例，不含用户照片、配置或真实额度。

卸载 app 不会自动删除用户资料。若需清除，请先退出 app，按上述目录和偏好域自行备份后删除；重新安装或升级不需要清除。

The app has no telemetry or upload backend. It uses the official local Codex CLI, which manages authentication and network access separately. Quota results requested through the plugin are returned to the current Codex conversation. Local settings, processed images and identity-free quota snapshots remain private user data, not release assets.
