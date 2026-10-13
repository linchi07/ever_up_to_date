import '../../ever_up_to_date_platform_interface.dart';
import '../model/platform_target.dart';
import 'app_installer.dart';

/// Android APK installer using system PackageInstaller via FileProvider.
class AndroidInstaller implements AppInstaller {
  final EverUpToDatePlatform _platform;

  AndroidInstaller({EverUpToDatePlatform? platform})
      : _platform = platform ?? EverUpToDatePlatform.instance;

  @override
  Future<bool> install({
    required String filePath,
    required PlatformTarget target,
    List<String>? customArgs,
    bool autoExit = true,
  }) async {
    return _platform.installApk(filePath);
  }

  /// Checks if the application currently has permission to install unknown apps.
  Future<bool> canRequestPackageInstalls() {
    return _platform.canRequestPackageInstalls();
  }

  /// Directs the user to system settings to grant unknown apps installation permission.
  Future<bool> openInstallPermissionSettings() {
    return _platform.openInstallPermissionSettings();
  }
}
