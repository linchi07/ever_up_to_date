# EverUp

EverUp 包含 Flutter 更新 SDK `ever_up_to_date` 与 Go 发布工具 `everup`。SDK 提供状态、检查、下载、校验和安装接口；应用决定 UI、检查频率和强制更新策略。发布端生成 GitHub Actions 工作流，将版本化安装包与 JSON 清单发布到 S3 兼容存储。

## 已实现的平台能力

| 平台 | 分发方式 | 安装行为 |
| --- | --- | --- |
| Android | APK、Google Play | APK 调起系统安装器；Google Play 打开商店 |
| Windows | Inno Setup、通用 EXE、portable ZIP | 启动本地安装器；ZIP 通过独立助手备份、替换并重启 |
| macOS | DMG、PKG | 打开已验证的本地文件，由用户完成系统安装 |
| iOS | App Store、TestFlight | 打开已配置的商店链接 |
| Linux | AppImage | 原位替换 AppImage，保留备份；启动失败时恢复 |

Web 不受支持。Linux 发布包需由使用者构建并调用发布脚本；默认 GitHub 工作流包含 Android、Windows、macOS 构建和 iOS 商店导流。iOS 编译、签名与 TestFlight 上传交由 App Store Connect/Xcode Cloud；Builder 会生成 `ios/ci_scripts/ci_post_clone.sh`。

## 初始化发布项目

编译 Builder（Go 版本要求见 `ever_up_builder/go.mod`）：

```bash
cd ever_up_builder
go generate ./internal/resources
go build -o ../bin/everup ./cmd/everup
```

在需要更新的 Flutter **应用项目**中运行：

```bash
/path/to/everup init .
/path/to/everup doctor .
```

向导会保存以下文件：

- `everup.json`：平台、存储、商店地址和公钥等非敏感配置。
- `.everup/signing-private.key`：权限为 `0600` 的私钥，目录自动加入 Git 忽略规则。
- `.everup/signing-public.key`：公钥副本。
- `.github/workflows/everup_release.yml`：发布工作流。
- `windows/installer.iss`：可提交的 Inno Setup 脚本。
- `lib/everup_config.dart`：供客户端导入的公开更新配置。
- `scripts/` 与 `templates/`：二进制内嵌的默认资源，已有同名文件作为项目覆盖保留。

重复初始化会保留原密钥。请安全备份私钥；不要把私钥写入 `everup.json` 或提交到 Git。修改配置后运行 `everup generate .`，生成失败会返回非零退出码。`doctor` 检查本地命令和配置；远程 GitHub Secrets 及存储权限需要另行配置。

存储对象前缀 `s3_prefix` 与 `manifest_url` 的公开路径必须映射到同一目录；例如前缀 `updates` 对应 `https://cdn.example.com/updates/appcast.json`。通过 Bucket/CDN 策略提供读权限，上传脚本不会修改对象 ACL。存储后端需要支持条件写入，否则发布会失败并保留现有发现清单。

## 配置 GitHub Secrets

基础 Secrets：`S3_ACCESS_KEY_ID`、`S3_SECRET_ACCESS_KEY`、`EVERUP_SIGNING_PRIVATE_KEY`。签名私钥可通过向导中明确选择的 `gh secret set` 步骤上传，也可在 GitHub 设置中填写 `.everup/signing-private.key` 的内容。

默认 `require_platform_signing=true`，还需要为启用的平台配置：

| 平台 | Secrets |
| --- | --- |
| Android | `ANDROID_KEYSTORE_BASE64`、`ANDROID_KEYSTORE_PASSWORD`、`ANDROID_KEY_ALIAS`、`ANDROID_KEY_PASSWORD` |
| Windows | `WINDOWS_CERTIFICATE_BASE64`、`WINDOWS_CERTIFICATE_PASSWORD` |
| macOS | `MACOS_CERTIFICATE_BASE64`、`MACOS_CERTIFICATE_PASSWORD`、`MACOS_SIGNING_IDENTITY`、`APPLE_ID`、`APPLE_APP_PASSWORD`、`APPLE_TEAM_ID` |

Android 在构建后使用指定 keystore 重签 APK；Windows 使用 Authenticode 签名安装器；macOS 使用 Developer ID 签名并提交公证。开发环境可在配置中关闭平台代码签名要求；发布安装包仍必须具有 Ed25519 签名。

提交生成文件，然后推送 `v1.2.3` 标签，或手动运行工作流并指定版本。正式标签默认进入 `stable`，预发布标签默认进入 `beta`。全部平台共用版本号和构建号，默认构建号来自工作流运行编号。

发布顺序为校验配置、构建、签名、上传不可变安装包、保存历史清单、条件写入 `appcast.json`。失败的上传和并发冲突不会发布不完整的发现清单；重复发布相同内容可重试。

## 接入 Flutter 客户端

先把 `ever_up_to_date` 加入应用依赖，并导入 Builder 生成的配置：

```dart
import 'package:flutter/widgets.dart';
import 'package:ever_up_to_date/ever_up_to_date.dart';
import 'everup_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final updater = EverUpToDate.instance;
  updater.initialize(everupOptions);
  final previous = await updater.confirmInstalledUpdate();
  // previous?.confirmed == false：前次更新尚未得到版本确认，可提示重试。
  runApp(const MyApp());
}
```

由应用 UI 发起更新：

```dart
final update = await updater.checkForUpdate();
if (update != null) {
  final file = await updater.downloadUpdate();
  if (update.platformTarget.type.isExternalStore || file != null) {
    await updater.installUpdate();
  }
}
```

检查/下载失败返回 `null`，安装失败返回 `false`，详细原因通过 `UpdateErrorState` 获取。尚未初始化、没有可安装更新或操作正在进行时会抛出 `StateError`。订阅 `stateNotifier` 或 `stateStream` 展示进度；应用在 Android 上应先检查未知应用安装权限，并在用户从设置返回后重试安装。示例应用只会在 Android 上调用这些权限接口。

二进制默认必须带 SHA-256。配置任一可信公钥后，缺失或无效签名一律拒绝。无公钥只适合自行建立其他信任机制的开发场景；`requireChecksum=false` 仅影响无公钥的开发下载。`httpHeaders` 用于清单和安装包请求，受保护的分发应使用受信任的 HTTPS 地址。

灰度比例、版本撤回、portable/AppImage 配置、密钥轮换和恢复方式见 [更新协议](docs/appcast.md) 与 [发布和恢复](docs/release.md)。

## 工具与验证

```bash
everup gen-keys .                 # 恢复或保存已有密钥，不输出私钥
everup crop logo.png cropped.png  # 保存裁切结果
everup gen-assets cropped.png assets/
everup reload-scripts .

flutter analyze
flutter test
cd ever_up_builder && go test ./...
cd ../scripts/common && go test ./...
cd ../.. && python3 scripts/tests/test_release_pipeline.py
```

Go 的生成器测试覆盖实际模板的 15 种平台组合；发布流程测试使用真实签名脚本与本地 AWS 替代程序。CI 在 Linux、Windows、macOS 运行 Flutter 测试，并验证模板、脚本和资源同步。实际证书、公证、真机安装与生产存储需要使用自己的账号和设备验收。

MIT License。
