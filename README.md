# EverUp (ever_up & ever_up_builder)

现代化、全流程的跨平台自动更新、构建编排与发布基础设施体系（仿照 Sparkle / TestFlight 理念）。

包含两大核心支柱：
1. **`ever_up` (客户端更新引擎)**：无 UI 绑定（Headless）、基于 JSON-First Appcast 协议的纯 Dart / Flutter 更新 SDK。
2. **`ever_up_builder` (构建与发布脚手架)**：纯 Go 驱动的 TUI 终端交互工具、动态工作流合成引擎与本地轻量可视化图像素材工作坊。

---

## 体系架构总览

```text
everup/
├── ever_up_builder/            # [Go] 终端 TUI 脚手架、动态工作流合成器与图像处理
│   ├── cmd/everup/             # CLI 命令行入口 (init, crop, gen-assets, reload-scripts, gen-keys)
│   ├── internal/
│   │   ├── tui/                # 基于 Charm Huh / Lipgloss 的现代化交互式向导
│   │   ├── loader/             # 动态脚本与模板发现与热重载引擎
│   │   ├── generator/          # GitHub Actions / Inno Setup 动态合成器
│   │   ├── asset/              # 图像裁切、Windows .ico 与 Inno .bmp 生成器
│   │   └── web/                # 嵌入式本地可视化 Web 裁切页面 (零 Node/NPM 依赖)
│   └── go.mod
├── scripts/                    # 模块化构建与发布脚本库 (TUI 动态扫描识别)
│   ├── flutter/                # Flutter 平台专属构建脚本
│   │   ├── build_android.sh    # 构建 Release APK
│   │   ├── build_windows.ps1   # 构建 Windows Release 并调用 Inno Setup 打包
│   │   └── build_macos.sh      # 构建 macOS Release 并调用 create-dmg 打包
│   └── common/                 # 跨语言通用发布脚本
│       ├── update_appcast.go   # 计算 SHA256、Ed25519 签名并同步 appcast.json
│       └── s3_upload.sh        # 通用 S3 / Cloudflare R2 / 阿里云 OSS 同步脚本
├── templates/                  # 动态流水线模板库
│   ├── github-actions/
│   │   └── release_matrix.yml.tpl # 矩阵多端编译、自动签名与上传流水线
│   ├── inno-setup/
│   │   └── everup_modern.iss.tpl  # 现代化、高分屏、静默安装 Inno Setup 模板
│   └── xcode-cloud/
│       └── ci_post_clone.sh.tpl   # Xcode Cloud 预置构建依赖安装脚本
├── lib/                        # [Dart] 客户端运行时核心代码 (Headless 更新引擎)
├── example/                    # Flutter 完整范例工程
└── test/                       # 单元测试全覆盖套件 (23+ 项测试全部通过)
```

---

## 一、 EverUp Builder (Go 脚手架与 TUI)

`ever_up_builder` 使用 Go 编写，可直接编译为单个二进制工具 `everup`，**交付使用完全不需要安装 Node.js、NPM 或任何前端依赖**。

### 1. 编译安装

```bash
cd ever_up_builder
go build -o ../bin/everup ./cmd/everup
```

### 2. 常用命令

#### ① 交互式向导初始化（`everup init`）
启动现代化终端向导（基于 Charm Huh），自动检测目标平台、配置 S3 存储凭据、生成 Ed25519 签名公私钥，并借助 `gh` CLI 自动把私钥注入 GitHub Secrets，最后根据模板动态合成 `.github/workflows/everup_release.yml` 和 `build/windows/installer.iss`。
```bash
./bin/everup init
```

#### ② 本地轻量可视化图像裁剪（`everup crop <image>`）
在本地临时拉起一个随机端口的轻量 HTTP 服务，自动唤起系统默认浏览器，在优雅的可视化界面中拖拽调整应用图标或 Inno Setup 侧边栏横幅。裁剪完成后点击保存，浏览器自动向 Go 回传数据并退出本地服务，全程无感、零外部环境依赖。
```bash
./bin/everup crop logo.png
```

#### ③ 一键合成全平台图标素材（`everup gen-assets <image>`）
一键自动将主图标裁剪缩放为：
- Windows 多尺寸合一的 `app_icon.ico` (包含 16x16, 32x32, 48x48, 64x64, 128x128, 256x256)
- Inno Setup 安装器向导侧边栏 `wizard.bmp` (164x314) 与小图标 `wizard_small.bmp` (55x58)
- 高清大图 `app_icon_512.png`
```bash
./bin/everup gen-assets logo.png assets/
```

#### ④ 动态重载脚本与模板目录（`everup reload-scripts`）
扫描 `scripts/` 与 `templates/` 目录，列出当前所有支持的构建环境与流水线。只需在此目录下新建文件夹与脚本，脚手架即可自动热识别。
```bash
./bin/everup reload-scripts
```

#### ⑤ 生成 Ed25519 签名密钥对（`everup gen-keys`）
```bash
./bin/everup gen-keys
```

---

## 二、 EverUp 客户端引擎 (Flutter/Dart SDK)

### 1. 特性与优势
- **极简 JSON-First 规范**：对标 Sparkle，支持 S3/OSS 静态托管，多通道（`stable` / `beta`）隔离。
- **纯粹 Headless 单例设计**：只提供 `EverUpToDate.instance` 状态机与事件流，不绑死任何 UI 弹窗。
- **Android APK 直接安装**：原生内置 `FileProvider` 与 `REQUEST_INSTALL_PACKAGES`，支持未知应用安装权限检测与跳转；海外 Google Play 自动合规跳转商店。
- **Windows 静默热升级**：内置 Inno Setup `/VERYSILENT` 分离进程启动并退出主程序，告别 Windows 文件锁。
- **iOS 导流**：自动引导跳转 TestFlight 测试通道或 App Store 页面。
- **密码学安全**：原生支持 SHA-256 哈希校验与 Ed25519 非对称数字签名验签。

### 2. 客户端调用示例

```dart
import 'package:ever_up_to_date/ever_up_to_date.dart';

void main() async {
  // 1. 初始化更新器
  EverUpToDate.instance.initialize(
    const UpdateOptions(
      manifestUrl: 'https://oss.example.com/appcast.json',
      channel: 'beta',
      publicKeyEd25519: 'YOUR_ED25519_PUBLIC_KEY',
      preferredLocale: 'zh-CN',
    ),
  );

  // 2. 检查更新
  final update = await EverUpToDate.instance.checkForUpdate();
  if (update != null) {
    // 3. 下载更新包
    await EverUpToDate.instance.downloadUpdate();

    // 4. 调起安装
    await EverUpToDate.instance.installUpdate();
  }
}
```

---

## 许可证

MIT License.
