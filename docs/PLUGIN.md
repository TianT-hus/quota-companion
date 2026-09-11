# Codex 插件

标识 `quota-companion`，插件版本与 app 主版本一致。内置市场标识保留 `quota-companion-dev`，不会修改用户既有市场名称。

| 工具 | 行为 |
| --- | --- |
| `get_quota_status` | 只读主 Codex 额度，标注 live / stale / unavailable |
| `show_companion` | 暂时显示桌宠详情；不会永久固定 |
| `collapse_companion` | 收起详情，保留桌宠 |
| `open_companion_settings` | 打开本机设置窗口 |

工具不会购买额度、兑换重置、切换账户或读取账户身份。控制工具通过当前用户 socket 工作；正常模式找不到 socket 时尝试启动已安装 app。启动请求成功不代表窗口已经验证可见。

打包后的 app 包含完整 helper、资源和 `.agents/plugins/marketplace.json`。使用应用内安装入口，或将设置页给出的精确 `codex plugin marketplace add` 命令复制到终端。随后在 Codex 的 Plugins 界面安装插件，开启新会话再调用。源码仓库本身不含 helper 二进制；应先构建，或使用 Release 中的独立 PluginMarketplace ZIP。

项目仓库为 [TianT-hus/quota-companion](https://github.com/TianT-hus/quota-companion)，[隐私说明](https://github.com/TianT-hus/quota-companion/blob/main/docs/PRIVACY.md) 已随源码提供。GitHub 发布与通用插件目录审核是两件独立工作，本轮不提交目录审核。

格式与安装行为参考 [官方插件文档](https://learn.chatgpt.com/docs/plugins) 和 [打包规范](https://developers.openai.com/plugins/build/plugins)。CLI 命令应以本机 `codex plugin marketplace add --help` 为准。
