import 'dart:io';
import '../model/platform_target.dart';
import 'app_installer.dart';
import '../model/package_type.dart';
import 'package:path/path.dart' as p;

typedef ProcessLauncher =
    Future<Process> Function(
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
  final String? portableInstallDirectory;
  final String? portableExecutableName;

  WindowsInstaller({
    ProcessLauncher? processLauncher,
    ExitHandler? exitHandler,
    this.portableInstallDirectory,
    this.portableExecutableName,
  }) : _processLauncher = processLauncher ?? Process.start,
       _exitHandler = exitHandler ?? exit;

  @override
  Future<bool> install({
    required String filePath,
    required PlatformTarget target,
    List<String>? customArgs,
    bool autoExit = true,
  }) async {
    if (target.type == PackageType.portableArchive) {
      return _installPortable(filePath, autoExit: autoExit);
    }
    if (target.type != PackageType.innoSetup &&
        target.type != PackageType.genericInstaller) {
      throw UnsupportedError('Unsupported Windows package: ${target.type}');
    }
    final args =
        customArgs ??
        target.installerArgs ??
        (target.type == PackageType.innoSetup
            ? DEFAULT_INNO_SETUP_ARGS
            : const <String>[]);

    // Launch installer as an independent detached process
    await _processLauncher(filePath, args, mode: ProcessStartMode.detached);

    // Terminate current application so installer can overwrite binaries
    if (autoExit) {
      _exitHandler(0);
    }

    return true;
  }

  Future<bool> _installPortable(
    String archive, {
    required bool autoExit,
  }) async {
    final directory = portableInstallDirectory;
    final executable = portableExecutableName;
    if (directory == null ||
        executable == null ||
        !p.windows.isAbsolute(directory) ||
        p.windows.basename(executable) != executable ||
        !executable.toLowerCase().endsWith('.exe') ||
        p.windows.normalize(directory) == p.windows.rootPrefix(directory)) {
      throw StateError(
        'Configure an absolute portableInstallDirectory and executable filename',
      );
    }
    if (!autoExit) throw StateError('Portable replacement requires autoExit');
    if (!await File(archive).exists()) {
      throw StateError('Local ZIP does not exist');
    }
    // The helper lives outside the directory that will be replaced.
    final helper = File(
      p.join(
        File(archive).parent.path,
        'everup-portable-${DateTime.now().microsecondsSinceEpoch}.ps1',
      ),
    );
    String quote(String value) => "'${value.replaceAll("'", "''")}'";
    final script = r'''
$ErrorActionPreference = 'Stop'
$stage = "$directory.everup-next"
$backup = "$directory.everup-backup"
$ownsStage = $false
try {
  if (Test-Path -LiteralPath $stage) { throw 'Unfinished update staging directory exists' }
  if (Test-Path -LiteralPath $backup) { throw 'Unconfirmed update backup exists; recover it first' }
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $zip = [IO.Compression.ZipFile]::OpenRead($archive)
  try {
    $root = [IO.Path]::GetFullPath($stage) + [IO.Path]::DirectorySeparatorChar
    [long]$total = 0
    foreach ($entry in $zip.Entries) {
      $path = [IO.Path]::GetFullPath([IO.Path]::Combine($stage, $entry.FullName))
      if (-not $path.StartsWith($root, [StringComparison]::OrdinalIgnoreCase) -or $entry.FullName.Contains(':')) { throw 'Unsafe ZIP entry' }
      if ((($entry.ExternalAttributes -shr 16) -band 0xF000) -eq 0xA000) { throw 'ZIP links are unsupported' }
      $total += $entry.Length
      if ($total -gt 2147483648) { throw 'ZIP expands beyond 2 GiB' }
    }
  } finally { $zip.Dispose() }
  $ownsStage = $true
  Expand-Archive -LiteralPath $archive -DestinationPath $stage
  if (-not (Test-Path -LiteralPath (Join-Path $stage $executable) -PathType Leaf)) { throw 'Executable missing from ZIP root' }
  if (Get-Process -Id $parentPid -ErrorAction SilentlyContinue) { Wait-Process -Id $parentPid -Timeout 60 -ErrorAction Stop }
  Move-Item -LiteralPath $directory -Destination $backup
  try {
    Move-Item -LiteralPath $stage -Destination $directory
    Start-Process -FilePath (Join-Path $directory $executable) -WorkingDirectory $directory
  } catch {
    if (Test-Path -LiteralPath $directory) { Remove-Item -LiteralPath $directory -Recurse -Force }
    Move-Item -LiteralPath $backup -Destination $directory
    throw
  }
} catch {
  $_ | Out-String | Set-Content -LiteralPath "$archive.install-error.txt"
  if ($ownsStage -and (Test-Path -LiteralPath $stage)) { Remove-Item -LiteralPath $stage -Recurse -Force }
  exit 1
} finally { Remove-Item -LiteralPath $PSCommandPath -Force }
''';
    await helper.writeAsString(
      '\$directory = ${quote(directory)}\n\$archive = ${quote(archive)}\n\$executable = ${quote(executable)}\n\$parentPid = $pid\n$script',
    );
    await _processLauncher('powershell.exe', [
      '-NoProfile',
      '-NonInteractive',
      '-ExecutionPolicy',
      'Bypass',
      '-File',
      helper.path,
    ], mode: ProcessStartMode.detached);
    _exitHandler(0);
    return true;
  }
}
