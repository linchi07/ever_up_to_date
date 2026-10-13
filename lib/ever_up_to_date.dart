import 'dart:io';
import 'package:flutter/foundation.dart';

import 'ever_up_to_date_platform_interface.dart';
import 'src/core/ever_up_to_date_engine.dart';
import 'src/core/update_options.dart';
import 'src/core/update_state.dart';
import 'src/downloader/chunk_downloader.dart';

export 'src/core/update_options.dart';
export 'src/core/update_state.dart';
export 'src/downloader/chunk_downloader.dart' show CancelToken;
export 'src/model/channel_info.dart';
export 'src/model/package_type.dart';
export 'src/model/platform_target.dart';
export 'src/model/target_platform_type.dart';
export 'src/model/update_manifest.dart';

/// Unified cross-platform auto-update facade.
///
/// Provides headless, singleton-based APIs to check, download, verify,
/// and install updates based on JSON appcast manifests.
class EverUpToDate {
  static final EverUpToDate _INSTANCE = EverUpToDate._internal();

  /// The global singleton instance of [EverUpToDate].
  static EverUpToDate get instance => _INSTANCE;

  late final EverUpToDateEngine _engine;

  EverUpToDate._internal() : _engine = EverUpToDateEngine();

  @visibleForTesting
  EverUpToDate.withEngine(EverUpToDateEngine engine) : _engine = engine;

  /// Current update lifecycle state.
  UpdateState get currentState => _engine.currentState;

  /// ValueListenable of [UpdateState] for reactive Flutter UI binding.
  ValueListenable<UpdateState> get stateNotifier => _engine.stateNotifier;

  /// Stream of [UpdateState] events.
  Stream<UpdateState> get stateStream => _engine.stateStream;

  /// The currently discovered update info, if any.
  UpdateInfo? get currentUpdateInfo => _engine.currentUpdateInfo;

  /// Initializes the updater with configuration [options].
  void initialize(UpdateOptions options) {
    _engine.initialize(options);
  }

  /// Checks the remote manifest for available updates.
  ///
  /// Set [force] to `true` to disregard version numbers and treat the remote
  /// version as an update anyway (e.g. for developer testing).
  Future<UpdateInfo?> checkForUpdate({bool force = false}) {
    return _engine.checkForUpdate(force: force);
  }

  /// Downloads the available update package with real-time progress.
  ///
  /// Supports cancellation via [cancelToken].
  Future<File?> downloadUpdate({CancelToken? cancelToken}) {
    return _engine.downloadUpdate(cancelToken: cancelToken);
  }

  /// Installs the downloaded update or opens the external store link.
  ///
  /// On Android, launches the system package installer.
  /// On Windows, executes the installer and optionally terminates the current process.
  /// On iOS/Store, opens TestFlight or App Store URL.
  Future<bool> installUpdate({
    List<String>? customArgs,
    bool? autoExit,
  }) {
    return _engine.installUpdate(
      customArgs: customArgs,
      autoExit: autoExit,
    );
  }

  /// Checks if the application currently has permission to install unknown apps on Android.
  Future<bool> canRequestPackageInstalls() {
    return EverUpToDatePlatform.instance.canRequestPackageInstalls();
  }

  /// Directs the user to Android system settings to grant unknown apps installation permission.
  Future<bool> openInstallPermissionSettings() {
    return EverUpToDatePlatform.instance.openInstallPermissionSettings();
  }
}
