# Appcast 协议与客户端约束

当前协议版本为 `1`。不支持的协议版本会被拒绝。版本号使用 SemVer；可接受前导 `v` 标签，但发布脚本会移除前导 `v`。同版本比较构建号；构建号应随构建增加。

```json
{
  "version": 1,
  "app_id": "com.example.app",
  "channels": {
    "stable": {
      "version": "1.2.3",
      "build_number": 123,
      "mandatory": false,
      "release_notes": {"zh-CN": "修复启动问题"},
      "platforms": {
        "windows": {
          "type": "inno_setup",
          "url": "https://cdn.example.com/releases/stable/1.2.3/123/windows-HASH.exe",
          "sha256": "64_HEX_CHARACTERS",
          "signature_ed25519": "BASE64_SIGNATURE",
          "file_size": 123456
        },
        "ios": {
          "type": "testflight",
          "url": "https://testflight.apple.com/join/YOUR_CODE"
        }
      }
    }
  }
}
```

上面哈希和签名是结构占位，使用发布脚本计算实际值。二进制的 Ed25519 签名覆盖完整文件内容；SHA-256 以流式方式计算，验签会读取完整文件，需要为安装包大小预留内存。清单通过受信任的 HTTPS 分发，二进制签名不对清单元数据签名。

`expectedAppId` 配置后会校验 `app_id`。清单必须使用 HTTP(S) URL；HTTP 只适合开发环境。安装器参数来自可信发布者的清单或应用本地配置，请将清单存储写权限与普通下载权限分离。

`mandatory` 作为状态数据交给应用 UI；SDK 不替应用禁用业务功能。用户交互、最低可用应用版本、检查频率和是否允许稍后更新由应用实现。

## 灰度与撤回

通道可设置 `rollout_percentage`（0 到 100，默认 100）和可选 `rollout_seed`。SDK 按设备的固定安装标识分组，同一标识与种子多次检查结果一致。默认随机标识保存在应用支持目录，不包含硬件标识；也可以用 `UpdateOptions.rolloutIdentifier` 传入自己的稳定分组标识。种子默认使用版本号，逐步增大比例会包含之前的设备。

`rollout_percentage=0` 暂停分发；`withdrawn=true` 撤回该通道当前版本。此时返回 `null` 并发出 `UpdateDeferredState`。撤回会优先于开发用 `force=true` 生效。`force=true` 可以绕过灰度比例用于开发验证，但仍需要满足平台、系统与签名约束。

## 最低系统版本与架构

可以为通道添加 `min_os_version`，例如 `"12.0"`。应用必须提供 `UpdateOptions.currentOsVersion`，填写操作系统发布版本而非内核版本；缺少当前系统版本或系统不兼容时拒绝更新。

不同架构可配置成以下格式：

```json
"windows": {
  "architectures": {
    "x64": {"type": "inno_setup", "url": "https://example.com/x64.exe", "sha256": "HASH", "signature_ed25519": "SIGNATURE"},
    "arm64": {"type": "inno_setup", "url": "https://example.com/arm64.exe", "sha256": "HASH", "signature_ed25519": "SIGNATURE"}
  }
}
```

SDK 根据运行进程的 ABI 选择目标，也可通过 `architecture` 覆盖。架构目标缺失时不会下载其他架构的安装包。默认 Builder 构建单一宿主架构；多架构构建和清单合并需扩展项目脚本。

## 文件与状态约束

- 同一引擎同时只能执行一个检查、下载、安装或版本确认操作。操作中重新初始化会失败。
- 检查更新会清除旧文件绑定；重新检查后需要重新下载。重新初始化也会清除当前更新。
- 配置公钥后必须同时有有效 SHA-256 和 Ed25519 签名；`trustedPublicKeysEd25519` 支持迁移期的多个可信公钥。
- 安装前再次核对本地哈希，文件大小存在时也会在下载后核对。
- `downloadTimeout` 限制整个请求与响应体的传输总时长，重试也计入预算。默认最多重试两次网络故障、429 和 5xx；4xx 永久错误不重试。
- `CancelToken.cancel()` 会立即终止等待中的请求或流，并删除不完整文件。下载错误不会留下可安装文件。
- 专用缓存目录只清除过期的 SDK 安装包，默认保留七天；没有断点续传，重试从头下载。

`installUpdate()` 返回成功表示系统安装器、替换助手或商店页面已启动。调用 `confirmInstalledUpdate()` 才能确认重启后的应用版本满足前次目标；结果 `confirmed=false` 表示仍未确认，可以提示用户重试。安装凭据保存在应用支持目录，不放在易清理的下载缓存中。
