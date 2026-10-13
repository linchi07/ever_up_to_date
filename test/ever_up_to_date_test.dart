import 'package:flutter_test/flutter_test.dart';
import 'package:ever_up_to_date/ever_up_to_date.dart';
import 'package:ever_up_to_date/ever_up_to_date_platform_interface.dart';
import 'package:ever_up_to_date/ever_up_to_date_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockEverUpToDatePlatform
    with MockPlatformInterfaceMixin
    implements EverUpToDatePlatform {
  bool installApkCalled = false;
  String? lastApkPath;

  @override
  Future<bool> installApk(String filePath) {
    installApkCalled = true;
    lastApkPath = filePath;
    return Future.value(true);
  }

  @override
  Future<bool> canRequestPackageInstalls() {
    return Future.value(true);
  }

  @override
  Future<bool> openInstallPermissionSettings() {
    return Future.value(true);
  }
}

void main() {
  final initialPlatform = EverUpToDatePlatform.instance;

  test('default platform instance is MethodChannelEverUpToDate', () {
    expect(initialPlatform, isInstanceOf<MethodChannelEverUpToDate>());
  });

  test('EverUpToDate facade delegates Android permission calls', () async {
    final mockPlatform = MockEverUpToDatePlatform();
    EverUpToDatePlatform.instance = mockPlatform;

    final updater = EverUpToDate.instance;

    final canInstall = await updater.canRequestPackageInstalls();
    expect(canInstall, isTrue);

    final openSettings = await updater.openInstallPermissionSettings();
    expect(openSettings, isTrue);
  });
}
