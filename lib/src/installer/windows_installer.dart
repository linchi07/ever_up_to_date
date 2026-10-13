import 'dart:io';
import '../model/platform_target.dart';
import 'app_installer.dart';

typedef ProcessLauncher = Future<Process> Function(
  String executable,
  List<String> arguments, {
  ProcessStartMode mode,
});

typedef ExitHandler = void Function(int code);

/// Windows installer supporting Inno Setup, NSIS and generic executable installers.
class WindowsInstaller implements AppInstaller {
  static const List<String> DEFAULT_INNO_SETUP_ARGS = [
    '/VERYSILENT',
    '/SUPPRESSMSGBOXES',
    '/NORESTART',
    '/SP-',
  ];

  final ProcessLauncher _processLauncher;
  final ExitHandler _exitHandler;

  WindowsInstaller({
    ProcessLauncher? processLauncher,
    ExitHandler? exitHandler,
  })  : _processLauncher = processLauncher ?? Process.start,
        _exitHandler = exitHandler ?? exit;

  @override
  Future<bool> install({
    required String filePath,
    required PlatformTarget target,
    List<String>? customArgs,
    bool autoExit = true,
  }) async {
    final args = customArgs ?? target.installerArgs ?? DEFAULT_INNO_SETUP_ARGS;

    // Launch installer as an independent detached process
    await _processLauncher(
      filePath,
      args,
      mode: ProcessStartMode.detached,
    );

    // Terminate current application so installer can overwrite binaries
    if (autoExit) {
      _exitHandler(0);
    }

    return true;
  }
}
