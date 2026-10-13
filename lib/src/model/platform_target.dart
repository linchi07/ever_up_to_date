import 'package_type.dart';

/// Target configuration for a specific operating system.
class PlatformTarget {
  final PackageType type;
  final String url;
  final String? sha256;
  final String? signatureEd25519;
  final int? fileSize;
  final List<String>? installerArgs;
  final Map<String, dynamic> extra;

  const PlatformTarget({
    required this.type,
    required this.url,
    this.sha256,
    this.signatureEd25519,
    this.fileSize,
    this.installerArgs,
    this.extra = const {},
  });

  factory PlatformTarget.fromJson(Map<String, dynamic> json) {
    final typeStr = json['type'] as String? ?? 'custom';
    final url = json['url'] as String? ?? '';
    final sha256 = json['sha256'] as String?;
    final signatureEd25519 =
        json['signature_ed25519'] as String? ?? json['signature'] as String?;
    final fileSize = json['file_size'] as int? ?? json['size'] as int?;
    final argsRaw = json['installer_args'];
    final installerArgs =
        argsRaw is List ? argsRaw.map((e) => e.toString()).toList() : null;

    return PlatformTarget(
      type: PackageType.fromString(typeStr),
      url: url,
      sha256: sha256,
      signatureEd25519: signatureEd25519,
      fileSize: fileSize,
      installerArgs: installerArgs,
      extra: json,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type.name,
      'url': url,
      if (sha256 != null) 'sha256': sha256,
      if (signatureEd25519 != null) 'signature_ed25519': signatureEd25519,
      if (fileSize != null) 'file_size': fileSize,
      if (installerArgs != null) 'installer_args': installerArgs,
      ...extra,
    };
  }
}
