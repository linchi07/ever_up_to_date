import '../model/platform_target.dart';

/// Abstract contract for installing or launching an update.
abstract class AppInstaller {
  /// Installs or launches the downloaded package at [filePath].
  Future<bool> install({
    required String filePath,
    required PlatformTarget target,
    List<String>? customArgs,
    bool autoExit = true,
  });
}
