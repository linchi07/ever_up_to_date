import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../downloader/chunk_downloader.dart';
import '../installer/android_installer.dart';
import '../installer/app_installer.dart';
import '../installer/url_launcher_installer.dart';
import '../installer/windows_installer.dart';
import '../model/package_type.dart';
import '../model/platform_target.dart';
import '../model/target_platform_type.dart';
import '../model/update_manifest.dart';
import '../security/checksum_verifier.dart';
import '../security/signature_verifier.dart';
import '../version/version_comparator.dart';
import 'update_options.dart';
import 'update_state.dart';

typedef TempDirResolver = Future<Directory> Function();

/// Core state machine and execution engine for EverUpToDate.
class EverUpToDateEngine {
  UpdateOptions? _options;
  UpdateInfo? _currentUpdateInfo;
  File? _downloadedFile;

  final http.Client _httpClient;
  final ChunkDownloader _downloader;
  final TempDirResolver? _tempDirResolver;
  final TargetPlatformType? _platformOverride;

  final ValueNotifier<UpdateState> _stateNotifier =
      ValueNotifier<UpdateState>(const UpdateIdleState());
  final StreamController<UpdateState> _stateController =
      StreamController<UpdateState>.broadcast();

  EverUpToDateEngine({
    http.Client? httpClient,
    ChunkDownloader? downloader,
    TempDirResolver? tempDirResolver,
    TargetPlatformType? platformOverride,
  })  : _httpClient = httpClient ?? http.Client(),
        _downloader = downloader ?? ChunkDownloader(client: httpClient),
        _tempDirResolver = tempDirResolver,
        _platformOverride = platformOverride;

  /// Current update state.
  UpdateState get currentState => _stateNotifier.value;

  /// ValueListenable for observing state changes in Flutter widgets.
  ValueListenable<UpdateState> get stateNotifier => _stateNotifier;

  /// Stream of update states.
  Stream<UpdateState> get stateStream => _stateController.stream;

  /// Active options, if initialized.
  UpdateOptions? get options => _options;

  /// Active update info, if an update is available or downloaded.
  UpdateInfo? get currentUpdateInfo => _currentUpdateInfo;

  /// Initializes the engine with [options].
  void initialize(UpdateOptions options) {
    _options = options;
  }

  /// Sets state and notifies both ValueNotifier and Stream listeners.
  void _emitState(UpdateState newState) {
    _stateNotifier.value = newState;
    _stateController.add(newState);
  }

  /// Checks the remote JSON manifest for available updates.
  Future<UpdateInfo?> checkForUpdate({bool force = false}) async {
    final opts = _options;
    if (opts == null) {
      throw StateError(
        'EverUpToDate has not been initialized. Call initialize() first.',
      );
    }

    _emitState(const UpdateCheckingState());

    try {
      final manifestUri = Uri.parse(opts.manifestUrl);
      final response = await _httpClient
          .get(manifestUri, headers: opts.httpHeaders)
          .timeout(opts.checkTimeout);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'Failed to fetch update manifest: HTTP ${response.statusCode}',
          uri: manifestUri,
        );
      }

      final jsonMap =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final manifest = UpdateManifest.fromJson(jsonMap);

      final channelInfo = manifest.getChannel(opts.channel);
      if (channelInfo == null) {
        throw StateError(
          'Channel "${opts.channel}" not found in update manifest',
        );
      }

      final currentPlatform = _resolveCurrentPlatform();
      final target = channelInfo.getTarget(currentPlatform);
      if (target == null) {
        // No distribution configured for this platform
        _emitState(
          UpdateUpToDateState(
            currentVersion: opts.currentVersion ?? '0.0.0',
            channel: opts.channel,
          ),
        );
        return null;
      }

      // Resolve current application version
      String currentVersion;
      int? currentBuildNumber;

      if (opts.currentVersion != null) {
        currentVersion = opts.currentVersion!;
        currentBuildNumber = opts.currentBuildNumber;
      } else {
        final packageInfo = await PackageInfo.fromPlatform();
        currentVersion = packageInfo.version;
        currentBuildNumber = int.tryParse(packageInfo.buildNumber);
      }

      final hasUpdate = force ||
          VersionComparator.isNewer(
            currentVersion: currentVersion,
            currentBuild: currentBuildNumber,
            targetVersion: channelInfo.version,
            targetBuild: channelInfo.buildNumber,
          );

      if (!hasUpdate) {
        _currentUpdateInfo = null;
        _emitState(
          UpdateUpToDateState(
            currentVersion: currentVersion,
            channel: opts.channel,
          ),
        );
        return null;
      }

      final releaseNotes =
          channelInfo.getLocalizedReleaseNotes(opts.preferredLocale);

      final info = UpdateInfo(
        channel: opts.channel,
        targetVersion: channelInfo.version,
        targetBuildNumber: channelInfo.buildNumber,
        currentVersion: currentVersion,
        currentBuildNumber: currentBuildNumber,
        releaseNotes: releaseNotes,
        mandatory: channelInfo.mandatory,
        pubDate: channelInfo.pubDate,
        platformTarget: target,
        platformType: currentPlatform,
      );

      _currentUpdateInfo = info;
      _emitState(UpdateAvailableState(info));
      return info;
    } catch (e, st) {
      final errorState = UpdateErrorState(
        message: 'Failed to check for updates: $e',
        error: e,
        stackTrace: st,
      );
      _emitState(errorState);
      return null;
    }
  }

  /// Downloads the update package and validates its cryptographic integrity.
  Future<File?> downloadUpdate({CancelToken? cancelToken}) async {
    final opts = _options;
    final info = _currentUpdateInfo;

    if (opts == null || info == null) {
      throw StateError(
        'No update available to download. Call checkForUpdate() first.',
      );
    }

    final target = info.platformTarget;

    // For external store links (App Store, TestFlight, Google Play), no download is needed
    if (target.type.isExternalStore) {
      _emitState(
        UpdateReadyToInstallState(
          localFilePath: '',
          updateInfo: info,
        ),
      );
      return null;
    }

    try {
      final tempDir = await _getCacheDirectory();
      final extension = _resolveFileExtension(target);
      final filename =
          'update_${info.targetVersion}_${DateTime.now().millisecondsSinceEpoch}$extension';
      final destFile = File(p.join(tempDir.path, filename));

      _emitState(
        const UpdateDownloadingState(
          receivedBytes: 0,
          totalBytes: 0,
          progress: 0.0,
        ),
      );

      await _downloader.downloadFile(
        url: target.url,
        destinationFile: destFile,
        headers: opts.httpHeaders,
        timeout: opts.downloadTimeout,
        cancelToken: cancelToken,
        onProgress: (received, total, progress) {
          _emitState(
            UpdateDownloadingState(
              receivedBytes: received,
              totalBytes: total,
              progress: progress,
            ),
          );
        },
      );

      // Verifying integrity
      _emitState(const UpdateVerifyingState());

      // 1. SHA-256 Checksum Verification
      if (target.sha256 != null && target.sha256!.isNotEmpty) {
        final hashMatches = await ChecksumVerifier.verifyFile(
          file: destFile,
          expectedSha256: target.sha256!,
        );
        if (!hashMatches) {
          await destFile.delete();
          throw StateError(
            'SHA-256 checksum mismatch for downloaded package.',
          );
        }
      }

      // 2. Ed25519 Cryptographic Signature Verification
      if (opts.publicKeyEd25519 != null &&
          target.signatureEd25519 != null &&
          target.signatureEd25519!.isNotEmpty) {
        final sigMatches = await SignatureVerifier.verifyFileEd25519(
          file: destFile,
          signatureString: target.signatureEd25519!,
          publicKeyString: opts.publicKeyEd25519!,
        );
        if (!sigMatches) {
          await destFile.delete();
          throw StateError(
            'Ed25519 signature verification failed for downloaded package.',
          );
        }
      }

      _downloadedFile = destFile;
      _emitState(
        UpdateReadyToInstallState(
          localFilePath: destFile.path,
          updateInfo: info,
        ),
      );
      return destFile;
    } on CancellationException catch (_) {
      // Revert to available state on user cancellation
      _emitState(UpdateAvailableState(info));
      return null;
    } catch (e, st) {
      _emitState(
        UpdateErrorState(
          message: 'Failed to download update: $e',
          error: e,
          stackTrace: st,
        ),
      );
      return null;
    }
  }

  /// Installs the package or navigates to the external store page.
  Future<bool> installUpdate({
    List<String>? customArgs,
    bool? autoExit,
  }) async {
    final opts = _options;
    final info = _currentUpdateInfo;

    if (opts == null || info == null) {
      throw StateError('No update ready for installation.');
    }

    final target = info.platformTarget;

    try {
      if (target.type.isExternalStore) {
        final installer = UrlLauncherInstaller();
        return await installer.install(
          filePath: '',
          target: target,
        );
      }

      final file = _downloadedFile;
      if (file == null || !await file.exists()) {
        throw StateError(
          'Downloaded package file not found. Please download again.',
        );
      }

      _emitState(UpdateInstallingState(localFilePath: file.path));

      final installer = _resolveInstaller(info.platformType, target.type);
      final success = await installer.install(
        filePath: file.path,
        target: target,
        customArgs: customArgs ?? opts.customInstallerArgs,
        autoExit: autoExit ?? opts.autoExitOnInstall,
      );

      return success;
    } catch (e, st) {
      _emitState(
        UpdateErrorState(
          message: 'Failed to install update: $e',
          error: e,
          stackTrace: st,
        ),
      );
      return false;
    }
  }

  AppInstaller _resolveInstaller(
    TargetPlatformType platform,
    PackageType packageType,
  ) {
    if (packageType.isExternalStore) {
      return UrlLauncherInstaller();
    }

    switch (platform) {
      case TargetPlatformType.android:
        return AndroidInstaller();
      case TargetPlatformType.windows:
        return WindowsInstaller();
      default:
        return UrlLauncherInstaller();
    }
  }

  Future<Directory> _getCacheDirectory() async {
    if (_tempDirResolver != null) {
      return _tempDirResolver();
    }
    try {
      final cacheDir = await getTemporaryDirectory();
      return cacheDir;
    } catch (_) {
      return Directory.systemTemp;
    }
  }

  String _resolveFileExtension(PlatformTarget target) {
    switch (target.type) {
      case PackageType.directApk:
        return '.apk';
      case PackageType.innoSetup:
      case PackageType.genericInstaller:
        return '.exe';
      case PackageType.portableArchive:
        return '.zip';
      case PackageType.dmg:
        return '.dmg';
      case PackageType.pkg:
        return '.pkg';
      case PackageType.appImage:
        return '.AppImage';
      default:
        // Try extracting from URL
        final urlPath = Uri.tryParse(target.url)?.path ?? '';
        final ext = p.extension(urlPath);
        return ext.isNotEmpty ? ext : '.bin';
    }
  }

  TargetPlatformType _resolveCurrentPlatform() {
    if (_platformOverride != null) {
      return _platformOverride;
    }
    if (kIsWeb) {
      return TargetPlatformType.web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return TargetPlatformType.android;
      case TargetPlatform.windows:
        return TargetPlatformType.windows;
      case TargetPlatform.iOS:
        return TargetPlatformType.ios;
      case TargetPlatform.macOS:
        return TargetPlatformType.macos;
      case TargetPlatform.linux:
        return TargetPlatformType.linux;
      default:
        return TargetPlatformType.unknown;
    }
  }

  /// Disposes internal resources.
  void dispose() {
    _downloader.close();
    _httpClient.close();
    _stateController.close();
    _stateNotifier.dispose();
  }
}
