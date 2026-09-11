# 手动发布流程

## 本地可复现输入

发布前审计全部拟提交路径、图片元数据以及可到达 Git 历史；`.gitignore` 不能替代审计。原始照片、用户背景/角色、真实额度、凭据、个人绝对路径、旧截图、原 dist/helper 和开发日志不得进入提交。

```sh
python3 scripts/audit-public.py --history
./scripts/validate.sh
python3 scripts/release-local.py
```

`release-local.py` 要求干净 Git 提交，导出到全新 `work/release-<commit>/checkout`，从零运行测试并编译两个架构；产物在 `dist/quota-companion-<version>-build<build>-<signing>/`。同一目录重复执行会拒绝覆盖；保留证据后使用新的干净副本重建。提供 app、独立插件市场、源码 ZIP、`BUILD-INFO.json` 和 `SHA256SUMS`。Swift/Xcode 版本记录在构建信息中；这表示输入可追溯，不承诺跨编译器字节完全一致。

## 签名与公证

默认 ad-hoc 测试签名。Apple Development 证书不能替代 Developer ID Application。已有相应资格时，可通过本机环境变量 `DEVELOPER_ID_APPLICATION` 选择该证书；脚本先签 helper，再签 app，启用 hardened runtime 和安全时间戳。

经维护者明确授权向 Apple 上传后，使用已存入本机钥匙串的 `NOTARYTOOL_PROFILE` 运行 `scripts/notarize.sh <app> <final-zip>`。不要把密码、私钥或 API Key 写入仓库、命令历史或聊天。脚本公证后 staple、验证并重新打 ZIP，避免发布不含票据的旧压缩包。**此流程尚未实跑**。公证后须重建独立插件 ZIP、构建状态及所有 SHA256；standalone helper 的离线下载体验须单独验证。未通过全部验证的包不能改称正式公证版。

## 隔离原生 QA

创建短路径临时目录和 `.quota-isolated` 标记，再直接启动候选 app 的可执行文件，并设置 `QUOTA_COMPANION_TEST_ROOT` 指向该目录。不要复用真实用户资料目录。测试实例的偏好、素材和 socket 全在该目录；相同目录重新启动用于设置保存验证。它禁用通知、登录启动注册、插件安装与 MCP 的 LaunchServices 回退，保留正式 Bundle ID。

默认仍会读取当前用户 Codex 登录。无登录测试需给测试进程单独设置 `CODEX_HOME` 指向空目录；不得清空真实 Codex 目录。演示与离线恢复使用合成 App Server，不得把模拟结果表述为真实网络恢复证据。不得将真实读取结果写入公开截图。

## 发布门槛

- 确认精确 GitHub owner/repo、素材公开分发权、公开文件清单、提交 SHA、签名状态。
- 确认后才创建公开仓库、push 或建立 GitHub Release；不自动合并其他任务。
- 仓库确认后填插件 repository/homepage/privacy URL；启用并验证私密安全报告入口。
- 区分单元测试、实际原生窗口、Apple Silicon 运行、Intel 真机、外部下载首启、公证/staple。未验证项明确列出。
- 只发手动更新包；不添加自动更新器。本轮不提交通用插件目录。
