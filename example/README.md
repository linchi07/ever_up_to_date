# EverUp Flutter 示例

示例展示 SDK 状态和更新按钮。`demo_appcast.json` 仅供清单结构演示，安装包和商店链接是占位地址，不能用于真实升级。

运行自己的分发：

```bash
flutter run --dart-define=EVERUP_MANIFEST_URL=https://updates.example.com/appcast.json \
  --dart-define=EVERUP_PUBLIC_KEY=YOUR_BASE64_PUBLIC_KEY
```

真实验收需要先发布一个更高版本/构建号的安装包。Android 安装需要未知应用权限，Windows 启动安装器后默认退出，macOS 需要完成系统安装。用 `confirmInstalledUpdate()` 在下一次启动确认新版本。

```bash
flutter test test/widget_test.dart
flutter test integration_test/plugin_integration_test.dart -d macos
```

集成测试使用本地 HTTP 服务和测试签名，验证检查、下载、验签、安装交接与重启后的版本确认；不自动操作系统安装弹窗。
