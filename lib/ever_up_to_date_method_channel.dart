import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'ever_up_to_date_platform_interface.dart';

/// Method channel implementation of [EverUpToDatePlatform].
class MethodChannelEverUpToDate extends EverUpToDatePlatform {
  static const String CHANNEL_NAME = 'ever_up_to_date';
  static const String METHOD_INSTALL_APK = 'installApk';
  static const String METHOD_CAN_REQUEST_PACKAGE_INSTALLS =
      'canRequestPackageInstalls';
  static const String METHOD_OPEN_INSTALL_PERMISSION_SETTINGS =
      'openInstallPermissionSettings';

  @visibleForTesting
  final MethodChannel methodChannel = const MethodChannel(CHANNEL_NAME);

  @override
  Future<bool> installApk(String filePath) async {
    final result = await methodChannel.invokeMethod<bool>(
      METHOD_INSTALL_APK,
      {'filePath': filePath},
    );
    return result ?? false;
  }

  @override
  Future<bool> canRequestPackageInstalls() async {
    final result = await methodChannel.invokeMethod<bool>(
      METHOD_CAN_REQUEST_PACKAGE_INSTALLS,
    );
    return result ?? false;
  }

  @override
  Future<bool> openInstallPermissionSettings() async {
    final result = await methodChannel.invokeMethod<bool>(
      METHOD_OPEN_INSTALL_PERMISSION_SETTINGS,
    );
    return result ?? false;
  }
}
