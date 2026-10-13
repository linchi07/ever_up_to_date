import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ever_up_to_date/src/installer/windows_installer.dart';
import 'package:ever_up_to_date/src/model/package_type.dart';
import 'package:ever_up_to_date/src/model/platform_target.dart';

class _FakeProcess implements Process {
  @override
  final int pid = 1234;

  @override
  Future<int> get exitCode => Future.value(0);

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) => true;

  @override
  Stream<List<int>> get stderr => const Stream.empty();

  @override
  Stream<List<int>> get stdout => const Stream.empty();

  @override
  IOSink get stdin => throw UnimplementedError();
}

void main() {
  group('WindowsInstaller Tests', () {
    test('launches detached installer with default Inno Setup args', () async {
      String? launchedExe;
      List<String>? launchedArgs;
      ProcessStartMode? launchedMode;
      int? exitCode;

      final installer = WindowsInstaller(
        processLauncher: (exe, args, {mode = ProcessStartMode.normal}) async {
          launchedExe = exe;
          launchedArgs = args;
          launchedMode = mode;
          return _FakeProcess();
        },
        exitHandler: (code) {
          exitCode = code;
        },
      );

      const target = PlatformTarget(
        type: PackageType.innoSetup,
        url: 'https://example.com/setup.exe',
      );

      final success = await installer.install(
        filePath: r'C:\temp\setup.exe',
        target: target,
        autoExit: true,
      );

      expect(success, isTrue);
      expect(launchedExe, equals(r'C:\temp\setup.exe'));
      expect(
        launchedArgs,
        equals(WindowsInstaller.DEFAULT_INNO_SETUP_ARGS),
      );
      expect(launchedMode, equals(ProcessStartMode.detached));
      expect(exitCode, equals(0));
    });

    test('respects custom arguments and disables autoExit', () async {
      List<String>? launchedArgs;
      var exitCalled = false;

      final installer = WindowsInstaller(
        processLauncher: (exe, args, {mode = ProcessStartMode.normal}) async {
          launchedArgs = args;
          return _FakeProcess();
        },
        exitHandler: (code) {
          exitCalled = true;
        },
      );

      const target = PlatformTarget(
        type: PackageType.innoSetup,
        url: 'https://example.com/setup.exe',
        installerArgs: ['/SILENT'],
      );

      await installer.install(
        filePath: r'C:\temp\setup.exe',
        target: target,
        customArgs: ['/CUSTOM', '/PARAM'],
        autoExit: false,
      );

      expect(launchedArgs, equals(['/CUSTOM', '/PARAM']));
      expect(exitCalled, isFalse);
    });
  });
}
