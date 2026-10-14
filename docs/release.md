# 发布、密钥迁移与恢复

## 平台更新

Windows EXE 支持 Inno Setup 默认静默参数。通用 EXE 只使用明确传入的参数，不自动附加 Inno 参数。

Windows portable ZIP 需要应用本地配置 `portableInstallDirectory` 和 `portableExecutableName`。目录必须是独立应用目录，ZIP 根目录必须包含对应 EXE，用户数据应保存在应用数据目录。默认升级助手等待当前进程退出后将旧目录改名为 `.everup-backup`，再替换新目录并启动。启动失败会恢复旧目录；展开失败、路径越界、符号链接和超过 2 GiB 的包会被拒绝。此模式要求 `autoExit=true`，不接受清单指定本地安装目录。

Linux AppImage 默认使用 `APPIMAGE` 环境变量，也可以配置绝对路径 `appImagePath`。升级会保留相邻的 `.everup-backup`；无法启动新文件时立即恢复旧文件。启动后的崩溃不属于启动失败，旧备份会一直保留到应用明确确认版本。未完成更新时再次更新会拒绝覆盖备份。

新版本运行正常后调用 `confirmInstalledUpdate()`。确认版本成功时，SDK 清理其 portable/AppImage 备份。macOS DMG/PKG 需要用户完成系统安装，Android APK 需要用户授予安装权限并确认系统安装提示；这些平台的恢复由系统安装器和应用分发策略处理。

如果 portable/AppImage 新版本不能正常启动，先停止应用，保留新版本用于排查，把相邻 `.everup-backup` 恢复为原应用文件/目录，然后再启动旧版本。不要在应用运行时手工替换 Windows 目录。

## 发布失败与重试

安装包路径包含通道、版本、构建号和内容哈希。已经存在且元数据哈希相同的包会复用；不同内容使用不同对象键。所有安装包上传成功后才保存历史清单并更新发现清单。

发现清单使用 `If-Match` 或 `If-None-Match` 条件写入；并发冲突会停止发布。GitHub 工作流也会串行执行发布。S3 兼容后端必须支持相应条件请求，参见 [AWS PutObject 条件写入说明](https://docs.aws.amazon.com/cli/latest/reference/s3api/put-object.html)。发生冲突后重新获取最新清单再重试，不要通过移除条件参数覆盖其他发布者的更新。

历史清单位于 `releases/<channel>/<version>/<build>/appcast-<hash>.json`，可用于审计或恢复发布目录。在生产存储开启版本管理，并为历史安装包设置独立保留策略。

## 灰度发布

在 `everup.json` 中设置 `rollout_percentage`（默认 100），运行 `everup generate` 后发布。可以先设为 10，在验证后把同一个版本的比例扩大到 50 或 100；使用相同版本号与构建号更新清单即可保持相同设备分组。手工脚本支持 `--rollout-percentage` 和 `--rollout-seed`。

## 撤回问题版本

先取得当前清单，再使用本地脚本标记撤回：

```bash
go run scripts/common/update_appcast.go --manifest=appcast.json --channel=stable \
  --version=1.2.3 --withdraw
```

脚本保留安装包与签名，并检查版本没有改变。将修改后的清单通过条件写入发布，可以阻止尚未更新的客户端继续安装问题版本；也可恢复之前已验证的通道数据。不要覆盖其他发布者的并发更新。

普通客户端拒绝版本降级；恢复旧清单不会自动降级已经升级的用户。需要向已升级用户发布一个更高版本号的修复版本。发布脚本的 `--allow-downgrade` 只用于明确的管理员目录恢复；客户端的 `force=true` 是开发测试功能。

## 密钥迁移

1. 在安全位置生成新密钥，保留原密钥备份。`gen-keys` 会恢复已有密钥；在新的空目录执行可以生成新密钥。
2. 先用旧私钥发布客户端过渡版本，将新公钥加入 `trustedPublicKeysEd25519`。
3. 过渡版本覆盖所需用户后再替换 CI 私钥，并修改 `everup.json` 的公开公钥配置。向导不会自动旋转已有密钥。
4. 验证新签名发布成功，再在后续客户端中移除旧公钥。尚未收到过渡版本的旧客户端将拒绝新密钥签名，需要保留旧签名分发渠道或另行迁移。

私钥只通过环境变量传给默认发布脚本，不出现在普通命令输出。GitHub Secrets 使用标准输入注入，避免将私钥放进命令参数。Ed25519 发布签名与 Android/Windows/Apple 平台签名分别配置。
