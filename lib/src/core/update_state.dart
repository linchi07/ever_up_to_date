import '../model/platform_target.dart';
import '../model/target_platform_type.dart';

/// Detailed information about an available update.
class UpdateInfo {
  final String channel;
  final String targetVersion;
  final int? targetBuildNumber;
  final String currentVersion;
  final int? currentBuildNumber;
  final String releaseNotes;
  final bool mandatory;
  final DateTime? pubDate;
  final PlatformTarget platformTarget;
  final TargetPlatformType platformType;

  const UpdateInfo({
    required this.channel,
    required this.targetVersion,
    this.targetBuildNumber,
    required this.currentVersion,
    this.currentBuildNumber,
    required this.releaseNotes,
    required this.mandatory,
    this.pubDate,
    required this.platformTarget,
    required this.platformType,
  });
}

/// Base sealed/abstract class for update lifecycle states.
abstract class UpdateState {
  const UpdateState();
}

/// Initial or idle state.
class UpdateIdleState extends UpdateState {
  const UpdateIdleState();

  @override
  String toString() => 'UpdateIdleState';
}

/// A release exists but is withdrawn or outside this installation's rollout cohort.
class UpdateDeferredState extends UpdateState {
  final String reason;
  const UpdateDeferredState(this.reason);
}

/// Manifest is currently being fetched and evaluated.
class UpdateCheckingState extends UpdateState {
  const UpdateCheckingState();

  @override
  String toString() => 'UpdateCheckingState';
}

/// Application is currently on the latest version.
class UpdateUpToDateState extends UpdateState {
  final String currentVersion;
  final String channel;

  const UpdateUpToDateState({
    required this.currentVersion,
    required this.channel,
  });

  @override
  String toString() =>
      'UpdateUpToDateState(version: $currentVersion, channel: $channel)';
}

/// A newer version is available.
class UpdateAvailableState extends UpdateState {
  final UpdateInfo updateInfo;

  const UpdateAvailableState(this.updateInfo);

  @override
  String toString() =>
      'UpdateAvailableState(targetVersion: ${updateInfo.targetVersion}, mandatory: ${updateInfo.mandatory})';
}

/// Binary package is currently downloading.
class UpdateDownloadingState extends UpdateState {
  final int receivedBytes;
  final int totalBytes;
  final double progress; // 0.0 to 1.0

  const UpdateDownloadingState({
    required this.receivedBytes,
    required this.totalBytes,
    required this.progress,
  });

  @override
  String toString() =>
      'UpdateDownloadingState(progress: ${(progress * 100).toStringAsFixed(1)}%)';
}

/// Downloaded package is undergoing hash/signature verification.
class UpdateVerifyingState extends UpdateState {
  const UpdateVerifyingState();

  @override
  String toString() => 'UpdateVerifyingState';
}

/// Download and integrity verification succeeded, ready to install.
class UpdateReadyToInstallState extends UpdateState {
  final String localFilePath;
  final UpdateInfo updateInfo;

  const UpdateReadyToInstallState({
    required this.localFilePath,
    required this.updateInfo,
  });

  @override
  String toString() =>
      'UpdateReadyToInstallState(file: $localFilePath, version: ${updateInfo.targetVersion})';
}

/// Installation process has been initiated.
class UpdateInstallingState extends UpdateState {
  final String localFilePath;

  const UpdateInstallingState({required this.localFilePath});

  @override
  String toString() => 'UpdateInstallingState(file: $localFilePath)';
}

/// An error occurred during check, download, verification or install.
class UpdateErrorState extends UpdateState {
  final String message;
  final dynamic error;
  final StackTrace? stackTrace;

  const UpdateErrorState({required this.message, this.error, this.stackTrace});

  @override
  String toString() => 'UpdateErrorState(message: $message, error: $error)';
}

/// The running application's version has confirmed a previously launched update.
class UpdateInstalledState extends UpdateState {
  final String version;
  const UpdateInstalledState(this.version);
}

/// Returned at startup after launching an installer on a previous run.
class UpdateInstallationResult {
  final String expectedVersion;
  final int? expectedBuildNumber;
  final String currentVersion;

  /// False means the expected release is not running yet; the caller can offer retry.
  final bool confirmed;
  const UpdateInstallationResult({
    required this.expectedVersion,
    this.expectedBuildNumber,
    required this.currentVersion,
    required this.confirmed,
  });
}
