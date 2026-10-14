import 'dart:io';
import 'package:path/path.dart' as p;
import '../model/package_type.dart';
import '../model/platform_target.dart';
import 'app_installer.dart';
import 'windows_installer.dart';

typedef ProcessRunner =
    Future<ProcessResult> Function(String executable, List<String> arguments);

/// Opens the verified local DMG or PKG in the system installer.
/// macOS asks the user to complete installation; a successful launch is not installation confirmation.
class MacOSInstaller implements AppInstaller {
  final ProcessRunner _run;
  MacOSInstaller({ProcessRunner? run})
    : _run = run ?? ((exe, args) => Process.run(exe, args));

  @override
  Future<bool> install({
    required String filePath,
    required PlatformTarget target,
    List<String>? customArgs,
    bool autoExit = true,
  }) async {
    if (target.type != PackageType.dmg && target.type != PackageType.pkg) {
      throw UnsupportedError('macOS supports DMG and PKG distributions');
    }
    if (!await File(filePath).exists()) {
      throw StateError('Local installer does not exist');
    }
    final result = await _run('/usr/bin/open', [filePath]);
    if (result.exitCode != 0) {
      throw ProcessException(
        '/usr/bin/open',
        [filePath],
        '${result.stderr}',
        result.exitCode,
      );
    }
    return true;
  }
}

/// Updates an AppImage in place with an adjacent backup and restores it on launch failure.
class LinuxInstaller implements AppInstaller {
  final String? appImagePath;
  final ProcessRunner _run;
  final ProcessLauncher _launch;
  final ExitHandler _exit;
  LinuxInstaller({
    String? appImagePath,
    ProcessRunner? run,
    ProcessLauncher? launch,
    ExitHandler? exitHandler,
  }) : appImagePath = appImagePath ?? Platform.environment['APPIMAGE'],
       _run = run ?? ((exe, args) => Process.run(exe, args)),
       _launch = launch ?? Process.start,
       _exit = exitHandler ?? exit;

  @override
  Future<bool> install({
    required String filePath,
    required PlatformTarget target,
    List<String>? customArgs,
    bool autoExit = true,
  }) async {
    if (target.type != PackageType.appImage) {
      throw UnsupportedError('Linux supports AppImage distributions');
    }
    final current = appImagePath;
    if (current == null || !p.isAbsolute(current)) {
      throw StateError('Run from an AppImage or configure appImagePath');
    }
    if (await FileSystemEntity.type(current, followLinks: false) !=
        FileSystemEntityType.file) {
      throw StateError('Current AppImage must be a regular file');
    }
    final original = File(current);
    final stage = File('$current.everup-next');
    final backup = File('$current.everup-backup');
    if (await backup.exists() || await stage.exists()) {
      throw StateError(
        'An unfinished AppImage update exists; recover it first',
      );
    }
    try {
      await File(filePath).copy(stage.path);
      final result = await _run('/bin/chmod', ['755', stage.path]);
      if (result.exitCode != 0) {
        throw StateError(
          'Cannot make the AppImage executable: ${result.stderr}',
        );
      }
      await original.rename(backup.path);
      try {
        await stage.rename(current);
        if (autoExit) {
          await _launch(
            current,
            customArgs ?? [],
            mode: ProcessStartMode.detached,
          );
        }
      } catch (_) {
        if (await File(current).exists()) await File(current).delete();
        await backup.rename(current);
        rethrow;
      }
      if (autoExit) _exit(0);
      return true;
    } finally {
      if (await stage.exists()) await stage.delete();
    }
  }
}
