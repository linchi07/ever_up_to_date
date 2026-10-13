import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ever_up_to_date/ever_up_to_date_method_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final platform = MethodChannelEverUpToDate();
  const channel = MethodChannel(MethodChannelEverUpToDate.CHANNEL_NAME);

  final methodCalls = <MethodCall>[];

  setUp(() {
    methodCalls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      methodCalls.add(call);
      switch (call.method) {
        case MethodChannelEverUpToDate.METHOD_INSTALL_APK:
          return true;
        case MethodChannelEverUpToDate.METHOD_CAN_REQUEST_PACKAGE_INSTALLS:
          return true;
        case MethodChannelEverUpToDate.METHOD_OPEN_INSTALL_PERMISSION_SETTINGS:
          return true;
        default:
          return null;
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('installApk sends correct method and arguments', () async {
    final result = await platform.installApk('/storage/emulated/0/app.apk');
    expect(result, isTrue);
    expect(methodCalls.length, equals(1));
    expect(
      methodCalls.first.method,
      equals(MethodChannelEverUpToDate.METHOD_INSTALL_APK),
    );
    expect(
      methodCalls.first.arguments,
      equals({'filePath': '/storage/emulated/0/app.apk'}),
    );
  });

  test('canRequestPackageInstalls invokes channel', () async {
    final result = await platform.canRequestPackageInstalls();
    expect(result, isTrue);
    expect(methodCalls.length, equals(1));
    expect(
      methodCalls.first.method,
      equals(MethodChannelEverUpToDate.METHOD_CAN_REQUEST_PACKAGE_INSTALLS),
    );
  });

  test('openInstallPermissionSettings invokes channel', () async {
    final result = await platform.openInstallPermissionSettings();
    expect(result, isTrue);
    expect(methodCalls.length, equals(1));
    expect(
      methodCalls.first.method,
      equals(MethodChannelEverUpToDate.METHOD_OPEN_INSTALL_PERMISSION_SETTINGS),
    );
  });
}
