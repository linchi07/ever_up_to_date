import 'package:flutter_test/flutter_test.dart';
import 'package:ever_up_to_date/ever_up_to_date.dart';
import 'package:ever_up_to_date/ever_up_to_date_platform_interface.dart';
import 'package:ever_up_to_date/ever_up_to_date_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockEverUpToDatePlatform
    with MockPlatformInterfaceMixin
    implements EverUpToDatePlatform {
  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final EverUpToDatePlatform initialPlatform = EverUpToDatePlatform.instance;

  test('$MethodChannelEverUpToDate is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelEverUpToDate>());
  });

  test('getPlatformVersion', () async {
    EverUpToDate everUpToDatePlugin = EverUpToDate();
    MockEverUpToDatePlatform fakePlatform = MockEverUpToDatePlatform();
    EverUpToDatePlatform.instance = fakePlatform;

    expect(await everUpToDatePlugin.getPlatformVersion(), '42');
  });
}
