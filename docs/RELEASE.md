# 朝夕 · 发布流程

1. 核对 `Packaging/Info.plist`、插件 manifest、README 和版本说明。对外名称统一为“朝夕 / Zhaoxi”，桌宠展示采用蓝色礼裙。逐项核对展示图和安装包实际内置资源的区别；只提交公开代码、文档及明确指定公开的展示素材。
2. 运行 `python3 scripts/audit-public.py --history` 和 `./scripts/validate.sh`。可选私人素材检查不是公共验收覆盖；真实系统权限和硬件测试应单独记录。
3. 在干净 Git 提交上运行 `python3 scripts/release-local.py`。脚本从该提交归档到独立目录，重新执行测试、构建两个 CPU 架构，校验签名和二进制路径，再生成应用 ZIP、插件 ZIP、源码 ZIP、构建信息和校验文件。
4. 默认使用 ad-hoc 签名，以测试版发布。只有提供有效 `DEVELOPER_ID_APPLICATION`、完成公证及 stapler/Gatekeeper 检查后，才能另行声明 Developer ID 或公证状态；当前脚本不会自动公证。
5. 若公开仓库通过 API 导入同一文件树，必须校验公开树 SHA 与构建树一致，并在 `BUILD-INFO.json` 的 `public_source_commit` 记录公开提交。`commit` 是本地构建提交；二者不能混写。可通过 `PUBLIC_SOURCE_COMMIT` 向构建脚本传入已核实的公开提交。
6. 将上述 5 个附件上传到对应公开提交的 GitHub Release，设置为 Pre-release。发布后重新读取 tag、提交、附件清单，并匿名下载全部附件核对大小和 SHA-256。

此流程不会安装或启动应用，不读取真实日程、录音或密钥，也不自动修改启动服务。
