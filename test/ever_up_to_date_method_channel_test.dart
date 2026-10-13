import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ever_up_to_date/ever_up_to_date_method_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  MethodChannelEverUpToDate platform = MethodChannelEverUpToDate();
  const MethodChannel channel = MethodChannel('ever_up_to_date');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
          return '42';
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('getPlatformVersion', () async {
    expect(await platform.getPlatformVersion(), '42');
  });
}
