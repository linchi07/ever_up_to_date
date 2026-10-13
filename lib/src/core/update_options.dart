/// Configuration options for the EverUpToDate updater engine.
class UpdateOptions {
  static const String DEFAULT_CHANNEL = 'stable';
  static const Duration DEFAULT_CHECK_TIMEOUT = Duration(seconds: 15);
  static const Duration DEFAULT_DOWNLOAD_TIMEOUT = Duration(minutes: 10);

  /// The HTTPS/HTTP URL of the JSON update manifest (hosted on S3, OSS, CDN, etc.).
  final String manifestUrl;

  /// The distribution channel to track ('stable', 'beta', 'dev', etc.).
  final String channel;

  /// Optional Ed25519 public key (Base64 or Hex) for verifying package signatures.
  final String? publicKeyEd25519;

  /// Override the current application version (defaults to PackageInfo version).
  final String? currentVersion;

  /// Override the current application build number (defaults to PackageInfo buildNumber).
  final int? currentBuildNumber;

  /// Preferred locale tag for release notes (e.g., 'zh-CN', 'en-US').
  final String? preferredLocale;

  /// Timeout for fetching and parsing the update manifest.
  final Duration checkTimeout;

  /// Timeout for downloading the binary package.
  final Duration downloadTimeout;

  /// Optional HTTP headers (e.g. for authentication or CDN routing).
  final Map<String, String>? httpHeaders;

  /// Optional custom installer arguments (e.g. overriding Windows Inno Setup switches).
  final List<String>? customInstallerArgs;

  /// Whether to terminate the current process after launching Windows installer.
  final bool autoExitOnInstall;

  const UpdateOptions({
    required this.manifestUrl,
    this.channel = DEFAULT_CHANNEL,
    this.publicKeyEd25519,
    this.currentVersion,
    this.currentBuildNumber,
    this.preferredLocale,
    this.checkTimeout = DEFAULT_CHECK_TIMEOUT,
    this.downloadTimeout = DEFAULT_DOWNLOAD_TIMEOUT,
    this.httpHeaders,
    this.customInstallerArgs,
    this.autoExitOnInstall = true,
  });
}
