import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'ever_up_to_date_method_channel.dart';

/// Platform interface for native operating system interactions.
abstract class EverUpToDatePlatform extends PlatformInterface {
  EverUpToDatePlatform() : super(token: _TOKEN);

  static final Object _TOKEN = Object();

  static EverUpToDatePlatform _instance = MethodChannelEverUpToDate();

  /// The default instance of [EverUpToDatePlatform] to use.
  static EverUpToDatePlatform get instance => _instance;

  /// Sets a platform-specific implementation.
  static set instance(EverUpToDatePlatform instance) {
    PlatformInterface.verifyToken(instance, _TOKEN);
    _instance = instance;
  }

  /// Installs an APK file from local [filePath] on Android.
  Future<bool> installApk(String filePath) {
    throw UnimplementedError('installApk() has not been implemented.');
  }

  /// Checks if the app is granted permission to install unknown apps on Android.
  Future<bool> canRequestPackageInstalls() {
    throw UnimplementedError(
      'canRequestPackageInstalls() has not been implemented.',
    );
  }

  /// Opens the system unknown app sources permission page on Android.
  Future<bool> openInstallPermissionSettings() {
    throw UnimplementedError(
      'openInstallPermissionSettings() has not been implemented.',
    );
  }
}
