import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ffi';
import 'dart:math';
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
import '../installer/desktop_installer.dart';
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
typedef InstallerResolver =
    AppInstaller Function(TargetPlatformType platform, PackageType type);

/// Core state machine and execution engine for EverUpToDate.
class EverUpToDateEngine {
  UpdateOptions? _options;
  UpdateInfo? _currentUpdateInfo;
  File? _downloadedFile;
  UpdateInfo? _downloadedUpdateInfo;
  bool _busy = false;
  bool _disposed = false;

  final http.Client _httpClient;
  final ChunkDownloader _downloader;
  final TempDirResolver? _tempDirResolver;
  final TargetPlatformType? _platformOverride;
  final InstallerResolver? _installerResolver;
  final TempDirResolver? _supportDirResolver;

  final ValueNotifier<UpdateState> _stateNotifier = ValueNotifier<UpdateState>(
    const UpdateIdleState(),
  );
  final StreamController<UpdateState> _stateController =
      StreamController<UpdateState>.broadcast();

  EverUpToDateEngine({
    http.Client? httpClient,
    ChunkDownloader? downloader,
    TempDirResolver? tempDirResolver,
    TargetPlatformType? platformOverride,
    InstallerResolver? installerResolver,
    TempDirResolver? supportDirResolver,
  }) : _httpClient = httpClient ?? http.Client(),
       _downloader = downloader ?? ChunkDownloader(client: httpClient),
       _tempDirResolver = tempDirResolver,
       _platformOverride = platformOverride,
       _installerResolver = installerResolver,
       _supportDirResolver = supportDirResolver;

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
    _ensureIdle();
    final uri = Uri.tryParse(options.manifestUrl);
    if (uri == null ||
        !['https', 'http'].contains(uri.scheme) ||
        uri.host.isEmpty) {
      throw ArgumentError('manifestUrl must be an HTTP(S) URL');
    }
    if (options.channel.isEmpty ||
        options.maxDownloadRetries < 0 ||
        options.cacheMaxAge <= Duration.zero ||
        options.checkTimeout <= Duration.zero ||
        options.downloadTimeout <= Duration.zero) {
      throw ArgumentError('Invalid channel, retry count or cache lifetime');
    }
    if (_trustedKeys(
      options,
    ).any((key) => !SignatureVerifier.isValidPublicKey(key))) {
      throw ArgumentError('Trusted Ed25519 keys must contain 32 bytes');
    }
    _options = options;
    _currentUpdateInfo = null;
    _downloadedFile = null;
    _downloadedUpdateInfo = null;
    _emitState(const UpdateIdleState());
  }

  void _ensureIdle() {
    if (_disposed) throw StateError('Updater has been disposed');
    if (_busy) throw StateError('An update operation is already in progress');
  }

  void _startOperation() {
    _ensureIdle();
    _busy = true;
  }

  /// Sets state and notifies both ValueNotifier and Stream listeners.
  void _emitState(UpdateState newState) {
    _stateNotifier.value = newState;
    _stateController.add(newState);
  }

  /// Checks the remote JSON manifest for available updates.
  Future<UpdateInfo?> checkForUpdate({bool force = false}) async {
    _ensureIdle();
    final opts = _options;
    if (opts == null) {
      throw StateError(
        'EverUpToDate has not been initialized. Call initialize() first.',
      );
    }

    _startOperation();
    _currentUpdateInfo = null;
    _downloadedFile = null;
    _downloadedUpdateInfo = null;
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
      if (opts.expectedAppId != null && manifest.appId != opts.expectedAppId) {
        throw const FormatException(
          'Appcast app_id does not match this application',
        );
      }

      final channelInfo = manifest.getChannel(opts.channel);
      if (channelInfo == null) {
        throw StateError(
          'Channel "${opts.channel}" not found in update manifest',
        );
      }
      if (channelInfo.withdrawn) {
        _emitState(const UpdateDeferredState('Release has been withdrawn'));
        return null;
      }

      VersionComparator.compareSemVer(channelInfo.version, channelInfo.version);
      final currentPlatform = _resolveCurrentPlatform();
      final target = channelInfo.getTarget(
        currentPlatform,
        opts.architecture ?? Abi.current().toString().split('_').last,
      );
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
      _validateTarget(currentPlatform, target);
      if (channelInfo.minOsVersion != null) {
        final osVersion = opts.currentOsVersion;
        if (osVersion == null) {
          throw StateError('Provide currentOsVersion to check min_os_version');
        }
        if (_compareOsVersions(osVersion, channelInfo.minOsVersion!) < 0) {
          throw StateError(
            'Update requires OS ${channelInfo.minOsVersion} or newer',
          );
        }
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

      final hasUpdate =
          force ||
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
      if (!force && channelInfo.rolloutPercentage < 100) {
        final identifier = opts.rolloutIdentifier ?? await _rolloutIdentifier();
        final digest = ChecksumVerifier.computeSha256(
          utf8.encode(
            '${channelInfo.rolloutSeed ?? channelInfo.version}:$identifier',
          ),
        );
        final cohort =
            int.parse(digest.substring(0, 8), radix: 16) / 0x100000000 * 100;
        if (cohort >= channelInfo.rolloutPercentage) {
          _emitState(
            const UpdateDeferredState(
              'Release is outside this installation\'s rollout cohort',
            ),
          );
          return null;
        }
      }

      final releaseNotes = channelInfo.getLocalizedReleaseNotes(
        opts.preferredLocale,
      );

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
    } finally {
      _busy = false;
    }
  }

  /// Downloads the update package and validates its cryptographic integrity.
  Future<File?> downloadUpdate({CancelToken? cancelToken}) async {
    _ensureIdle();
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
        UpdateReadyToInstallState(localFilePath: '', updateInfo: info),
      );
      return null;
    }
    _startOperation();
    File? destFile;
    _downloadedFile = null;
    _downloadedUpdateInfo = null;
    try {
      if ((cancelToken?.isCancelled ?? false)) {
        throw const CancellationException('Download cancelled');
      }
      _validateSecurity(opts, target);
      final tempDir = await _getCacheDirectory();
      await _cleanCache(tempDir, opts.cacheMaxAge);
      final extension = _resolveFileExtension(target);
      final filename =
          'update_${info.targetVersion}_${DateTime.now().microsecondsSinceEpoch}_${Random.secure().nextInt(0x7fffffff)}$extension';
      destFile = File(p.join(tempDir.path, filename));

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
        maxRetries: opts.maxDownloadRetries,
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
      if (target.fileSize != null &&
          await destFile.length() != target.fileSize) {
        throw StateError('Downloaded package size does not match the manifest');
      }

      // 1. SHA-256 Checksum Verification
      if (target.sha256 != null && target.sha256!.isNotEmpty) {
        final hashMatches = await ChecksumVerifier.verifyFile(
          file: destFile,
          expectedSha256: target.sha256!,
        );
        if (!hashMatches) {
          await destFile.delete();
          throw StateError('SHA-256 checksum mismatch for downloaded package.');
        }
      }

      // 2. Ed25519 Cryptographic Signature Verification
      final keys = _trustedKeys(opts);
      if (keys.isNotEmpty) {
        var sigMatches = false;
        for (final key in keys) {
          if (await SignatureVerifier.verifyFileEd25519(
            file: destFile,
            signatureString: target.signatureEd25519!,
            publicKeyString: key,
          )) {
            sigMatches = true;
            break;
          }
        }
        if (!sigMatches) {
          await destFile.delete();
          throw StateError(
            'Ed25519 signature verification failed for downloaded package.',
          );
        }
      }

      if (cancelToken?.isCancelled ?? false) {
        throw CancellationException(
          cancelToken?.reason ?? 'Download cancelled',
        );
      }
      _downloadedFile = destFile;
      _downloadedUpdateInfo = info;
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
    } finally {
      _busy = false;
      if (destFile != null &&
          !identical(_downloadedFile, destFile) &&
          await destFile.exists()) {
        await destFile.delete();
      }
    }
  }

  /// Installs the package or navigates to the external store page.
  Future<bool> installUpdate({List<String>? customArgs, bool? autoExit}) async {
    _ensureIdle();
    final opts = _options;
    final info = _currentUpdateInfo;

    if (opts == null || info == null) {
      throw StateError('No update ready for installation.');
    }

    final target = info.platformTarget;
    _startOperation();
    File? receipt;
    try {
      final installer =
          _installerResolver?.call(info.platformType, target.type) ??
          _resolveInstaller(info.platformType, target.type);
      if (target.type.isExternalStore) {
        receipt = await _writeInstallationReceipt(info);
        if (!await installer.install(filePath: '', target: target)) {
          throw StateError('Store could not be opened');
        }
        return true;
      }

      final file = _downloadedFile;
      if (file == null ||
          !identical(_downloadedUpdateInfo, info) ||
          !await file.exists()) {
        throw StateError(
          'Downloaded package file not found. Please download again.',
        );
      }
      // Revalidate the cached file immediately before handing it to an installer.
      if (target.sha256 != null &&
          !await ChecksumVerifier.verifyFile(
            file: file,
            expectedSha256: target.sha256!,
          )) {
        throw StateError('Cached installer was modified; download again');
      }

      _emitState(UpdateInstallingState(localFilePath: file.path));
      receipt = await _writeInstallationReceipt(info);

      final success = await installer.install(
        filePath: file.path,
        target: target,
        customArgs: customArgs ?? opts.customInstallerArgs,
        autoExit: autoExit ?? opts.autoExitOnInstall,
      );

      if (!success) throw StateError('Installer could not be started');
      return true;
    } catch (e, st) {
      if (receipt != null && await receipt.exists()) await receipt.delete();
      _emitState(
        UpdateErrorState(
          message: 'Failed to install update: $e',
          error: e,
          stackTrace: st,
        ),
      );
      return false;
    } finally {
      _busy = false;
    }
  }

  Future<File> _receiptFile() async {
    final opts = _options;
    if (opts == null) throw StateError('Initialize the updater first');
    final directory = _supportDirResolver != null
        ? await _supportDirResolver()
        : await getApplicationSupportDirectory();
    final appKey = ChecksumVerifier.computeSha256(
      utf8.encode(opts.expectedAppId ?? opts.manifestUrl),
    );
    await directory.create(recursive: true);
    return File(p.join(directory.path, 'everup-install-$appKey.json'));
  }

  Future<String> _rolloutIdentifier() async {
    final receipt = await _receiptFile();
    final file = File('${receipt.path}.cohort');
    if (await file.exists()) return file.readAsString();
    final random = Random.secure();
    final identifier = base64UrlEncode(
      List.generate(24, (_) => random.nextInt(256)),
    );
    await file.writeAsString(identifier, flush: true);
    return identifier;
  }

  Future<File> _writeInstallationReceipt(UpdateInfo info) async {
    final file = await _receiptFile();
    final stage = File('${file.path}.tmp');
    await stage.writeAsString(
      jsonEncode({
        'version': info.targetVersion,
        'build_number': info.targetBuildNumber,
        'platform': info.platformType.name,
        'package_type': info.platformTarget.type.name,
      }),
      flush: true,
    );
    if (await file.exists()) await file.delete();
    await stage.rename(file.path);
    return file;
  }

  /// Call once at startup after restarting the app. Launching an installer is not confirmation.
  Future<UpdateInstallationResult?> confirmInstalledUpdate() async {
    _startOperation();
    try {
      final file = await _receiptFile();
      if (!await file.exists()) return null;
      final receipt =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final opts = _options!;
      final packageInfo = opts.currentVersion == null
          ? await PackageInfo.fromPlatform()
          : null;
      final current = opts.currentVersion ?? packageInfo!.version;
      final build =
          opts.currentBuildNumber ??
          int.tryParse(packageInfo?.buildNumber ?? '');
      final expected = receipt['version'] as String;
      final expectedBuild = receipt['build_number'] as int?;
      final order = VersionComparator.compareSemVer(current, expected);
      final confirmed =
          order > 0 ||
          (order == 0 &&
              (expectedBuild == null ||
                  (build != null && build >= expectedBuild)));
      if (confirmed) {
        if (receipt['package_type'] == PackageType.appImage.name &&
            _resolveCurrentPlatform() == TargetPlatformType.linux) {
          final current = opts.appImagePath ?? Platform.environment['APPIMAGE'];
          if (current != null) {
            final backup = '$current.everup-backup';
            if (await FileSystemEntity.type(backup, followLinks: false) ==
                FileSystemEntityType.file) {
              await File(backup).delete();
            }
          }
        }
        if (receipt['package_type'] == PackageType.portableArchive.name &&
            _resolveCurrentPlatform() == TargetPlatformType.windows &&
            opts.portableInstallDirectory != null) {
          final backup = '${opts.portableInstallDirectory}.everup-backup';
          if (await FileSystemEntity.type(backup, followLinks: false) ==
              FileSystemEntityType.directory) {
            await Directory(backup).delete(recursive: true);
          }
        }
        await file.delete();
        _emitState(UpdateInstalledState(current));
      }
      return UpdateInstallationResult(
        expectedVersion: expected,
        expectedBuildNumber: expectedBuild,
        currentVersion: current,
        confirmed: confirmed,
      );
    } finally {
      _busy = false;
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
        return WindowsInstaller(
          portableInstallDirectory: _options?.portableInstallDirectory,
          portableExecutableName: _options?.portableExecutableName,
        );
      case TargetPlatformType.macos:
        return MacOSInstaller();
      case TargetPlatformType.linux:
        return LinuxInstaller(appImagePath: _options?.appImagePath);
      default:
        throw UnsupportedError('Unsupported installation platform: $platform');
    }
  }

  Future<Directory> _getCacheDirectory() async {
    if (_tempDirResolver != null) {
      return _tempDirResolver();
    }
    try {
      final cacheDir = await getTemporaryDirectory();
      return Directory(p.join(cacheDir.path, 'ever_up_to_date'))
        ..createSync(recursive: true);
    } catch (_) {
      return Directory(p.join(Directory.systemTemp.path, 'ever_up_to_date'))
        ..createSync(recursive: true);
    }
  }

  List<String> _trustedKeys(UpdateOptions opts) => [
    if (opts.publicKeyEd25519 != null) opts.publicKeyEd25519!,
    ...opts.trustedPublicKeysEd25519,
  ];

  void _validateSecurity(UpdateOptions opts, PlatformTarget target) {
    if ((opts.requireChecksum || _trustedKeys(opts).isNotEmpty) &&
        (target.sha256 == null ||
            !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(target.sha256!))) {
      throw StateError('Binary updates require a SHA-256 checksum');
    }
    if (_trustedKeys(opts).isNotEmpty &&
        (target.signatureEd25519?.trim().isEmpty ?? true)) {
      throw StateError(
        'A signed update is required when a trusted public key is configured',
      );
    }
  }

  void _validateTarget(TargetPlatformType platform, PlatformTarget target) {
    final uri = Uri.tryParse(target.url);
    if (uri == null ||
        !['https', 'http'].contains(uri.scheme) ||
        uri.host.isEmpty) {
      throw const FormatException('Invalid update URL');
    }
    final supported = switch (platform) {
      TargetPlatformType.android => {
        PackageType.directApk,
        PackageType.googlePlay,
      },
      TargetPlatformType.windows => {
        PackageType.innoSetup,
        PackageType.genericInstaller,
        PackageType.portableArchive,
      },
      TargetPlatformType.ios => {PackageType.appStore, PackageType.testflight},
      TargetPlatformType.macos => {PackageType.dmg, PackageType.pkg},
      TargetPlatformType.linux => {PackageType.appImage},
      _ => <PackageType>{},
    };
    if (!supported.contains(target.type)) {
      throw UnsupportedError(
        'Unsupported package ${target.type} for $platform',
      );
    }
  }

  int _compareOsVersions(String current, String minimum) {
    List<int> parse(String value) {
      if (!RegExp(r'^\d+(\.\d+)*$').hasMatch(value)) {
        throw FormatException('Invalid OS release version', value);
      }
      return value.split('.').map(int.parse).toList();
    }

    final a = parse(current), b = parse(minimum);
    for (var i = 0; i < (a.length > b.length ? a.length : b.length); i++) {
      final diff = (i < a.length ? a[i] : 0) - (i < b.length ? b[i] : 0);
      if (diff != 0) return diff;
    }
    return 0;
  }

  Future<void> _cleanCache(Directory dir, Duration maxAge) async {
    await dir.create(recursive: true);
    final cutoff = DateTime.now().subtract(maxAge);
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is File &&
          p.basename(entity.path).startsWith('update_') &&
          (await entity.stat()).modified.isBefore(cutoff)) {
        await entity.delete();
      }
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
    _ensureIdle();
    _disposed = true;
    _downloader.close();
    _httpClient.close();
    _stateController.close();
    _stateNotifier.dispose();
  }
}
