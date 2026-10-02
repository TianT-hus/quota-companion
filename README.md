# 朝夕 / Zhaoxi — Quota Companion

macOS 桌面伙伴：查看主 Codex 额度，管理每日安排和待办，并按需使用语音播报。

当前公开测试版：**0.2.31 · build 47**。需要 **macOS 14 或更新版本**，安装包同时包含 Apple Silicon（arm64）和 Intel（x86_64）。部分系统翻译功能需要 macOS 15 或更新版本及已下载的语言资源。

## 下载与安装

在 [GitHub Releases](https://github.com/TianT-hus/quota-companion/releases) 下载 `macos-universal.zip`，解压得到 `朝夕.app`，复制到 Applications 后打开。升级前先正常退出旧版，并备份自己的应用和数据；不要同时运行两份应用。

此包使用 **ad-hoc 测试签名，未经 Apple 公证**，不能验证发布者身份，macOS 可能阻止直接打开。请先核对来源和 `SHA256SUMS`，再根据系统显示的“隐私与安全性”提示决定是否打开。项目不提供关闭系统安全检查的安装脚本。

每次发布提供 5 个附件：Mac 应用、Codex 插件、源码 ZIP、`BUILD-INFO.json` 和 `SHA256SUMS`。在同一下载目录运行 `shasum -a 256 -c SHA256SUMS` 可校验另外 4 个文件。

## 功能

- **额度与桌宠**：通过本机官方 `codex app-server` 读取主 Codex 额度，区分实时、缓存和不可用状态。支持内置猫咪、自定义本地角色、外观与背景。
- **每日安排**：单日时间轴、前后一天导航、今天/回到现在、分类、重复规则、单日例外、冲突检查及待办关联。0.2.31 恢复纯每日视图，移除了日/周切换入口。
- **待办与提醒事项**：保留本地待办；用户授权后，可选择 Apple 提醒事项列表进行双向同步。
- **语音**：系统声音、播报模板、中英文设置；可自行配置阿里云百炼或 MiniMax 的受支持接口。声音克隆向导支持本地录音/导入、预览及上传前的授权和费用确认。
- **启动方式**：登录时启动或跟随 Codex 启停；启用其中一种时会确认切换，系统批准状态会在设置中显示。

这是独立社区项目，不代表 OpenAI、Apple、阿里云或 MiniMax。Codex 额度功能需要用户自行安装并登录官方 Codex；本项目不分发 Codex CLI。

## 数据与权限

额度快照、日程、待办、角色、背景及配置保存在本机。云语音会把实际播报文本发送给所选服务商；声音克隆会在用户确认后上传音频并可能产生服务费用。服务商 API Key 保存到 macOS 钥匙串，不写入偏好或诊断文件。Apple 提醒事项所用账户可能由系统同步到 iCloud 或其他账户。详见 [隐私说明](docs/PRIVACY.md)。

发布包只包含代码与内置资源，不包含个人角色、照片、真实日程、额度快照、录音、密钥或本地验收截图。

## Codex 插件

`plugin-universal.zip` 内含 `PluginMarketplace` 本地市场目录及通用架构 MCP 辅助程序。按 Codex 当前提供的本地插件安装入口添加该目录，也可在应用设置中使用插件安装入口。

插件提供 `get_quota_status`、`show_companion`、`collapse_companion`、`open_companion_settings` 四个工具；额度读取为只读。插件不提供密钥读取、声音克隆或日程编辑工具。不要把私人 Codex 配置或身份文件放进这个市场目录。

## 从源码构建

需要包含 macOS 26 SDK 的 Xcode 工具链及 Swift 6；此版本使用较新的系统 API，并以 availability 检查兼容较旧的 macOS。没有外部 Swift 包依赖。

```sh
./scripts/validate.sh
./scripts/package-app.sh release
```

输出为 `dist/朝夕.app`。构建不会自动安装、启动、替换现有应用，或注册系统启动服务。资源在打包时放入应用；`swift run` 不代替完整的应用打包流程。

维护者可在干净 Git 提交上运行 `python3 scripts/release-local.py`，从提交归档重新测试、构建并生成附件。详细步骤见 [发布流程](docs/RELEASE.md)。

## 测试范围

测试包含日程、重复规则、迁移、语音请求与异常处理、启动设置、角色渲染和中英文界面检查。云服务使用模拟客户端；真实 API 计费、真实声音上传、系统权限、VoiceOver、多屏交互、真实注销/重登和 Intel 真机表现需要独立验证。依赖私人角色或额外环境变量的可选测试在公共源码中不执行其素材检查，不应将测试总数视为全部人工验收通过。

[版本说明](docs/RELEASE-0.2.31.md) · [安全反馈](SECURITY.md) · [素材记录](THIRD_PARTY_NOTICES.md) · [MIT License](LICENSE)
