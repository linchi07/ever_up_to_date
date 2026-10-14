import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ever_up_to_date/src/installer/desktop_installer.dart';
import 'package:ever_up_to_date/src/installer/windows_installer.dart';
import 'package:ever_up_to_date/src/model/platform_target.dart';
import 'package:ever_up_to_date/src/model/package_type.dart';

class FakeProcess implements Process {
  @override
  int get pid => 123;
  @override
  Future<int> get exitCode async => 0;
  @override
  Stream<List<int>> get stderr => const Stream.empty();
  @override
  Stream<List<int>> get stdout => const Stream.empty();
  @override
  IOSink get stdin => throw UnimplementedError();
  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) => true;
}

void main() {
  test('macOS opens verified local package instead of remote URL', () async {
    final root = await Directory.systemTemp.createTemp('everup-macos');
    final file = await File('${root.path}/installer.dmg').writeAsString('dmg');
    String? executable;
    List<String>? arguments;
    final installer = MacOSInstaller(
      run: (exe, args) async {
        executable = exe;
        arguments = args;
        return ProcessResult(0, 0, '', '');
      },
    );
    expect(
      await installer.install(
        filePath: file.path,
        target: const PlatformTarget(
          type: PackageType.dmg,
          url: 'https://example.com/app.dmg',
        ),
      ),
      isTrue,
    );
    expect(executable, '/usr/bin/open');
    expect(arguments, [file.path]);
    await root.delete(recursive: true);
  });
  test(
    'AppImage replacement keeps backup and restores on launch failure',
    () async {
      final root = await Directory.systemTemp.createTemp('everup-linux');
      final current = await File(
        '${root.path}/app.AppImage',
      ).writeAsString('old');
      final update = await File(
        '${root.path}/new.AppImage',
      ).writeAsString('new');
      var exited = false;
      final installer = LinuxInstaller(
        appImagePath: current.path,
        run: (exe, args) async => ProcessResult(0, 0, '', ''),
        launch: (exe, args, {mode = ProcessStartMode.normal}) async =>
            throw const ProcessException('app', [], 'failed'),
        exitHandler: (_) => exited = true,
      );
      await expectLater(
        installer.install(
          filePath: update.path,
          target: const PlatformTarget(
            type: PackageType.appImage,
            url: 'https://example.com/app',
          ),
        ),
        throwsA(isA<ProcessException>()),
      );
      expect(await current.readAsString(), 'old');
      expect(exited, isFalse);
      final success = LinuxInstaller(
        appImagePath: current.path,
        run: (exe, args) async => ProcessResult(0, 0, '', ''),
      );
      expect(
        await success.install(
          filePath: update.path,
          target: const PlatformTarget(
            type: PackageType.appImage,
            url: 'https://example.com/app',
          ),
          autoExit: false,
        ),
        isTrue,
      );
      expect(await current.readAsString(), 'new');
      expect(await File('${current.path}.everup-backup').readAsString(), 'old');
      await root.delete(recursive: true);
    },
  );
  test(
    'Windows portable ZIP launches replacement helper with safe validation',
    () async {
      final root = await Directory.systemTemp.createTemp('everup-portable');
      final archive = await File('${root.path}/app.zip').writeAsString('zip');
      String? launched;
      List<String>? arguments;
      var exited = false;
      final installer = WindowsInstaller(
        portableInstallDirectory: r'C:\Apps\Example',
        portableExecutableName: 'example.exe',
        processLauncher: (exe, args, {mode = ProcessStartMode.normal}) async {
          launched = exe;
          arguments = args;
          return FakeProcess();
        },
        exitHandler: (_) => exited = true,
      );
      expect(
        await installer.install(
          filePath: archive.path,
          target: const PlatformTarget(
            type: PackageType.portableArchive,
            url: 'https://example.com/app.zip',
          ),
        ),
        isTrue,
      );
      expect(launched, 'powershell.exe');
      expect(exited, isTrue);
      final script = await File(arguments!.last).readAsString();
      expect(script, contains('Unsafe ZIP entry'));
      expect(script, contains('Move-Item -LiteralPath \$backup'));
      expect(script, contains('Wait-Process'));
      expect(script, contains('example.exe'));
      await root.delete(recursive: true);
    },
  );
  test(
    'Windows portable helper restores previous installation after launch failure',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'everup-portable-native',
      );
      final installed = await Directory('${root.path}/installed').create();
      final old = await File(
        '${installed.path}/example.exe',
      ).writeAsString('old installation');
      final package = await Directory('${root.path}/package').create();
      await File(
        '${package.path}/example.exe',
      ).writeAsString('invalid executable fixture');
      final archive = '${root.path}/release.zip';
      String quote(String value) => "'${value.replaceAll("'", "''")}'";
      final compressed = await Process.run('powershell.exe', [
        '-NoProfile',
        '-Command',
        'Compress-Archive -Path ${quote('${package.path}/*')} -DestinationPath ${quote(archive)}',
      ]);
      expect(compressed.exitCode, 0, reason: '${compressed.stderr}');
      Process? helper;
      final installer = WindowsInstaller(
        portableInstallDirectory: installed.path,
        portableExecutableName: 'example.exe',
        exitHandler: (_) {},
        processLauncher: (exe, args, {mode = ProcessStartMode.normal}) async {
          final script = File(args.last);
          // Keep the test runner alive while still executing the production helper.
          final body = (await script.readAsString()).replaceFirst(
            RegExp(r'\$parentPid = \d+'),
            r'$parentPid = 2147483647',
          );
          await script.writeAsString(body);
          helper = await Process.start(exe, args);
          return helper!;
        },
      );
      try {
        expect(
          await installer.install(
            filePath: archive,
            target: const PlatformTarget(
              type: PackageType.portableArchive,
              url: 'https://example.com/release.zip',
            ),
          ),
          isTrue,
        );
        // Drain pipes so a verbose PowerShell failure cannot block process completion.
        final output = helper!.stdout.drain<void>();
        final errors = helper!.stderr.drain<void>();
        expect(await helper!.exitCode.timeout(const Duration(seconds: 20)), 1);
        await output;
        await errors;
        expect(await old.readAsString(), 'old installation');
        expect(
          await Directory('${installed.path}.everup-backup').exists(),
          isFalse,
        );
        expect(await File('$archive.install-error.txt').exists(), isTrue);
      } finally {
        await root.delete(recursive: true);
      }
    },
    skip: !Platform.isWindows,
  );
}
