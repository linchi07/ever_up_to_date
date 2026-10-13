# EverUpToDate (ever_up_to_date)

仿照 macOS Sparkle / Appcast 设计理念的现代化、跨平台 Flutter 自动更新插件。

专为**多端分发、测试版交付（Android / Windows / iOS TestFlight）与正式版发布**设计。完全兼容 S3 / OSS / CDN 等静态文件托管，无需搭建复杂的动态更新后端。

---

## 核心设计与特性

- **JSON-First Appcast 规范**：告别陈旧的 RSS 2.0 XML 命名空间，拥抱现代清晰、体积轻量、易于 CI/CD 自动生成的 JSON 描述文件。
- **S3 / OSS / CDN 友好**：仅需上传二进制安装包与静态 `appcast.json`，极低成本即可支撑高并发更新请求。
- **多平台无缝分发**：
  - **Android**：
    - 国内 / 官网 / 内部测试版：后台分片流式下载 APK，支持校验后通过 `FileProvider` 调起原生系统安装器；支持未知应用安装权限检测与跳转。
    - 海外版：适配 Google Play 渠道规范，支持跳转商店。
  - **Windows**：下载安装包（原生支持 Inno Setup `/VERYSILENT` 完全静默安装、NSIS 等），以独立分离进程（Detached Process）静默执行安装，主程序优雅退出完成热替换。
  - **iOS**：遵从 Apple 规范，提供更新通知与导流能力，支持一键打开 TestFlight 邀请链接或 App Store 页面。
  - **macOS / Linux**：支持引导打开 DMG / PKG / AppImage 或自定义外部链接。
- **纯粹的 Headless 单例 API**：**绝不强制绑定任何预制 UI 弹窗**。提供响应式状态机与事件流（`idle` -> `checking` -> `updateAvailable` -> `downloading` -> `verifying` -> `readyToInstall` -> `installing`），开发者可以自由融入自己应用的 Material 3 / Cupertino / Fluent 设计系统。
- **工业级密码学安全**：
  - 支持 **SHA-256** 散列值完整性校验。
  - 支持 **Ed25519** 非对称数字签名校验（完全对标 Sparkle 的 `sparkle:edSignature`），有效防御 OSS 劫持与中间人篡改。
- **多渠道（Channels）隔离**：一套 Manifest 天然支持 `stable`、`beta`、`alpha`、`dev` 等多发布渠道分流。
- **国际化更新日志**：支持按语言代码（如 `zh-CN`、`en-US`、`zh`）自动解析匹配多语言 Release Notes。

---

## 快速接入

### 1. 添加依赖

在 `pubspec.yaml` 中添加：

```yaml
dependencies:
  ever_up_to_date:
    git:
      url: https://github.com/linchi07/ever_up_to_date.git
```

### 2. 初始化与检查更新

在应用启动时（例如 `main.dart` 或初始化阶段）配置更新器选项：

```dart
import 'package:ever_up_to_date/ever_up_to_date.dart';

void initUpdater() {
  EverUpToDate.instance.initialize(
    const UpdateOptions(
      // S3/OSS/CDN 上托管的静态 manifest 地址
      manifestUrl: 'https://oss.example.com/appcast.json',
      // 当前应用订阅的发布渠道：'stable' 或 'beta'
      channel: 'beta',
      // 可选：内置 Ed25519 公钥（Base64 或 Hex），开启签名校验
      publicKeyEd25519: 'YOUR_ED25519_PUBLIC_KEY',
      // 可选：指定偏好语言，用于匹配 release notes（默认自动按环境解析）
      preferredLocale: 'zh-CN',
    ),
  );
}
```

### 3. 调用更新逻辑（Headless）

```dart
// 1. 检查是否有更新
final updateInfo = await EverUpToDate.instance.checkForUpdate();

if (updateInfo != null) {
  print('发现新版本: ${updateInfo.targetVersion}');
  print('更新内容:\n${updateInfo.releaseNotes}');

  // 2. 触发下载（支持 CancelToken 取消）
  final downloadedFile = await EverUpToDate.instance.downloadUpdate();

  // 3. 调起安装
  if (downloadedFile != null || updateInfo.platformTarget.type.isExternalStore) {
    // Android 端如需检查安装未知应用权限：
    if (Platform.isAndroid) {
      final canInstall = await EverUpToDate.instance.canRequestPackageInstalls();
      if (!canInstall) {
        await EverUpToDate.instance.openInstallPermissionSettings();
        return;
      }
    }

    // 执行安装或跳转商店
    await EverUpToDate.instance.installUpdate();
  }
}
```

### 4. 监听状态（响应式 UI 绑定）

通过 `stateNotifier`（推荐配合 `ValueListenableBuilder`）或 `stateStream` 随时刷新界面：

```dart
ValueListenableBuilder<UpdateState>(
  valueListenable: EverUpToDate.instance.stateNotifier,
  builder: (context, state, child) {
    if (state is UpdateDownloadingState) {
      return LinearProgressIndicator(value: state.progress);
    }
    if (state is UpdateVerifyingState) {
      return const Text('正在校验文件完整性...');
    }
    if (state is UpdateReadyToInstallState) {
      return ElevatedButton(
        onPressed: () => EverUpToDate.instance.installUpdate(),
        child: const Text('立即安装'),
      );
    }
    return const SizedBox.shrink();
  },
)
```

---

## Appcast JSON 规范示例

将生成的 `appcast.json` 放置在你的 S3 兼容存储桶或静态文件服务器上：

```json
{
  "version": 1,
  "app_id": "com.example.app",
  "channels": {
    "stable": {
      "version": "1.0.1",
      "build_number": 101,
      "mandatory": false,
      "pub_date": "2026-10-13T12:00:00Z",
      "release_notes": {
        "zh-CN": "1. 修复了若干已知问题\n2. 提升了启动性能",
        "en-US": "1. Bug fixes\n2. Performance improvements"
      },
      "platforms": {
        "android": {
          "type": "direct_apk",
          "url": "https://oss.example.com/downloads/app-v1.0.1.apk",
          "sha256": "abcdef1234567890...",
          "signature_ed25519": "...",
          "file_size": 25165824
        },
        "windows": {
          "type": "inno_setup",
          "url": "https://oss.example.com/downloads/setup-v1.0.1.exe",
          "sha256": "123456abcdef7890...",
          "installer_args": ["/VERYSILENT", "/SUPPRESSMSGBOXES", "/NORESTART", "/SP-"]
        },
        "ios": {
          "type": "app_store",
          "url": "https://apps.apple.com/app/id123456789"
        }
      }
    },
    "beta": {
      "version": "1.1.0-beta.1",
      "build_number": 110,
      "mandatory": false,
      "pub_date": "2026-10-13T18:00:00Z",
      "release_notes": {
        "zh-CN": "1. [测试版] 全新架构体验",
        "en-US": "1. [Beta] Architecture preview"
      },
      "platforms": {
        "android": {
          "type": "direct_apk",
          "url": "https://oss.example.com/downloads/app-v1.1.0-beta.apk"
        },
        "windows": {
          "type": "inno_setup",
          "url": "https://oss.example.com/downloads/setup-v1.1.0-beta.exe"
        },
        "ios": {
          "type": "testflight",
          "url": "https://testflight.apple.com/join/xxxxxx"
        }
      }
    }
  }
}
```

---

## 平台特定说明

### Android
* 插件已内置 `androidx.core.content.FileProvider` 与 `REQUEST_INSTALL_PACKAGES` 权限声明。
* 如果你的目标是 Google Play 商店，Manifest 中平台 `type` 应配置为 `google_play`，将自动引导跳转商店，严格避免因外部下载 APK 导致的违规下架。

### Windows
* 支持 Inno Setup、NSIS 等标准安装器。
* 默认 Inno Setup 参数使用 `/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP-` 实现无感静默安装，启动后自动结束当前进程避免文件加锁。
* 建议将 Windows 应用安装在 `%LOCALAPPDATA%\Programs\YourApp`（Per-User 模式），更新时无需弹出 UAC 管理员提权。

---

## 许可证

MIT License.
