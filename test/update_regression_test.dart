import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ever_up_to_date/ever_up_to_date.dart';
import 'package:ever_up_to_date/src/core/ever_up_to_date_engine.dart';
import 'package:ever_up_to_date/src/downloader/chunk_downloader.dart';
import 'package:ever_up_to_date/src/installer/app_installer.dart';
import 'package:ever_up_to_date/src/security/checksum_verifier.dart';
import 'package:ever_up_to_date/src/version/version_comparator.dart';

class RecordingInstaller implements AppInstaller {
  String? path;
  bool succeeds = true;
  @override
  Future<bool> install({
    required String filePath,
    required PlatformTarget target,
    List<String>? customArgs,
    bool autoExit = true,
  }) async {
    path = filePath;
    return succeeds;
  }
}

void main() {
  late Directory directory;
  late RecordingInstaller installer;
  late EverUpToDateEngine engine;
  late Map<String, dynamic> release;
  final payload = utf8.encode('signed installer payload');
  Map<String, dynamic> manifest(String version, {bool target = true}) => {
    'version': 1,
    'app_id': 'com.example.app',
    'channels': {
      'stable': {
        'version': version,
        'build_number': 20,
        'platforms': target
            ? {
                'windows': {
                  'type': 'inno_setup',
                  'url': 'https://example.com/package.exe',
                  'sha256': ChecksumVerifier.computeSha256(payload),
                  'file_size': payload.length,
                },
              }
            : <String, dynamic>{},
      },
    },
  };
  UpdateOptions options({
    String? key,
    List<String> extraKeys = const [],
    String version = '1.0.0',
  }) => UpdateOptions(
    manifestUrl: 'https://example.com/appcast.json',
    currentVersion: version,
    currentBuildNumber: 20,
    publicKeyEd25519: key,
    trustedPublicKeysEd25519: extraKeys,
  );
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('everup-regression');
    installer = RecordingInstaller();
    release = manifest('2.0.0');
    final client = MockClient(
      (request) async => request.url.path.endsWith('.json')
          ? http.Response(jsonEncode(release), 200)
          : http.Response.bytes(payload, 200),
    );
    engine = EverUpToDateEngine(
      httpClient: client,
      platformOverride: TargetPlatformType.windows,
      tempDirResolver: () async => directory,
      supportDirResolver: () async => directory,
      installerResolver: (_, _) => installer,
    );
    engine.initialize(options());
  });
  tearDown(() async {
    engine.dispose();
    await directory.delete(recursive: true);
  });

  test('configured key rejects missing signature before downloading', () async {
    engine.initialize(options(key: base64Encode(List.filled(32, 0))));
    await engine.checkForUpdate();
    expect(await engine.downloadUpdate(), isNull);
    expect(engine.currentState, isA<UpdateErrorState>());
    expect(
      (engine.currentState as UpdateErrorState).message,
      contains('signed update is required'),
    );
    expect(directory.listSync(), isEmpty);
  });
  test(
    'key rotation accepts trusted new key and rejects a wrong signature',
    () async {
      final keyPair = await Ed25519().newKeyPair();
      final public = await keyPair.extractPublicKey();
      final signature = await Ed25519().sign(payload, keyPair: keyPair);
      final target = release['channels']['stable']['platforms']['windows'];
      target['signature_ed25519'] = base64Encode(signature.bytes);
      engine.initialize(
        options(
          key: base64Encode(List.filled(32, 0)),
          extraKeys: [base64Encode(public.bytes)],
        ),
      );
      await engine.checkForUpdate();
      expect(await engine.downloadUpdate(), isNotNull);
      target['signature_ed25519'] = base64Encode(List.filled(64, 0));
      await engine.checkForUpdate();
      expect(await engine.downloadUpdate(), isNull);
      expect(engine.currentState, isA<UpdateErrorState>());
    },
  );
  test('new version cannot install previously downloaded file', () async {
    await engine.checkForUpdate();
    expect(await engine.downloadUpdate(), isNotNull);
    release = manifest('3.0.0');
    await engine.checkForUpdate();
    expect(await engine.installUpdate(autoExit: false), isFalse);
    expect(installer.path, isNull);
  });
  test(
    'missing target clears stale update and initialization clears cache binding',
    () async {
      await engine.checkForUpdate();
      await engine.downloadUpdate();
      release = manifest('2.0.0', target: false);
      expect(await engine.checkForUpdate(), isNull);
      expect(engine.currentUpdateInfo, isNull);
      engine.initialize(options());
      expect(engine.currentState, isA<UpdateIdleState>());
      expect(engine.currentUpdateInfo, isNull);
    },
  );
  test('modified cached package is rejected before installation', () async {
    await engine.checkForUpdate();
    final file = await engine.downloadUpdate();
    await file!.writeAsString('tampered');
    expect(await engine.installUpdate(autoExit: false), isFalse);
    expect(installer.path, isNull);
  });
  test(
    'installer failure removes receipt and restart confirms expected version',
    () async {
      await engine.checkForUpdate();
      await engine.downloadUpdate();
      installer.succeeds = false;
      expect(await engine.installUpdate(autoExit: false), isFalse);
      expect(await engine.confirmInstalledUpdate(), isNull);
      installer.succeeds = true;
      expect(await engine.installUpdate(autoExit: false), isTrue);
      expect((await engine.confirmInstalledUpdate())!.confirmed, isFalse);
      engine.initialize(options(version: '2.0.0'));
      expect((await engine.confirmInstalledUpdate())!.confirmed, isTrue);
      expect(engine.currentState, isA<UpdateInstalledState>());
      expect(await engine.confirmInstalledUpdate(), isNull);
    },
  );
  test('unsupported schema and wrong application ID are rejected', () async {
    release['version'] = 2;
    expect(await engine.checkForUpdate(), isNull);
    expect(engine.currentState, isA<UpdateErrorState>());
    release = manifest('2.0.0');
    engine.initialize(
      const UpdateOptions(
        manifestUrl: 'https://example.com/appcast.json',
        currentVersion: '1.0.0',
        expectedAppId: 'com.other.app',
      ),
    );
    expect(await engine.checkForUpdate(), isNull);
    expect(engine.currentState, isA<UpdateErrorState>());
  });
  test(
    'architecture selection does not fall back to an incompatible binary',
    () async {
      final targets = release['channels']['stable']['platforms'];
      final original = targets['windows'];
      targets['windows'] = {
        'architectures': {'x64': original},
      };
      engine.initialize(
        const UpdateOptions(
          manifestUrl: 'https://example.com/appcast.json',
          currentVersion: '1.0.0',
          architecture: 'arm64',
        ),
      );
      expect(await engine.checkForUpdate(), isNull);
      expect(engine.currentUpdateInfo, isNull);
      targets['windows']['architectures']['arm64'] = original;
      expect(await engine.checkForUpdate(), isNotNull);
    },
  );
  test('package JSON round trips all protocol distribution types', () {
    for (final kind in PackageType.values) {
      final target = PlatformTarget(
        type: kind,
        url: 'https://example.com/file',
      );
      expect(PlatformTarget.fromJson(target.toJson()).type, kind);
    }
  });
  test('withdrawal and rollout exclude installs deterministically', () async {
    release['channels']['stable']['withdrawn'] = true;
    expect(await engine.checkForUpdate(), isNull);
    expect(engine.currentState, isA<UpdateDeferredState>());
    release['channels']['stable']['withdrawn'] = false;
    release['channels']['stable']['rollout_percentage'] = 0;
    engine.initialize(
      const UpdateOptions(
        manifestUrl: 'https://example.com/appcast.json',
        currentVersion: '1.0.0',
        rolloutIdentifier: 'installation-a',
      ),
    );
    expect(await engine.checkForUpdate(), isNull);
    expect(await engine.checkForUpdate(), isNull);
    expect(engine.currentState, isA<UpdateDeferredState>());
    release['channels']['stable']['rollout_percentage'] = 50;
    expect(
      await engine.checkForUpdate(),
      isNotNull,
    ); // installation-a is in the first half.
    expect(await engine.checkForUpdate(), isNotNull);
    engine.initialize(
      const UpdateOptions(
        manifestUrl: 'https://example.com/appcast.json',
        currentVersion: '1.0.0',
        rolloutIdentifier: 'installation-b',
      ),
    );
    expect(
      await engine.checkForUpdate(),
      isNull,
    ); // installation-b is outside the first half.
    expect(await engine.checkForUpdate(), isNull);
    release['channels']['stable']['rollout_percentage'] = 100;
    expect(await engine.checkForUpdate(), isNotNull);
    release['channels']['stable']['rollout_percentage'] = 101;
    expect(await engine.checkForUpdate(), isNull);
    expect(engine.currentState, isA<UpdateErrorState>());
  });
  test('minimum OS blocks incompatible release', () async {
    release['channels']['stable']['min_os_version'] = '12.0';
    engine.initialize(
      const UpdateOptions(
        manifestUrl: 'https://example.com/appcast.json',
        currentVersion: '1.0.0',
        currentOsVersion: '11.9',
      ),
    );
    expect(await engine.checkForUpdate(), isNull);
    expect(engine.currentState, isA<UpdateErrorState>());
  });
  test('concurrent checks and reinitialization are rejected', () async {
    engine.dispose();
    final response = Completer<http.Response>();
    engine = EverUpToDateEngine(
      httpClient: MockClient((_) => response.future),
      platformOverride: TargetPlatformType.windows,
    );
    engine.initialize(options());
    final first = engine.checkForUpdate();
    await expectLater(engine.checkForUpdate(), throwsStateError);
    expect(() => engine.initialize(options()), throwsStateError);
    response.complete(http.Response(jsonEncode(release), 200));
    await first;
  });
  test('Git tags normalize correctly and invalid versions are rejected', () {
    expect(VersionComparator.compareSemVer('v1.0.0', '1.0.0'), 0);
    expect(
      VersionComparator.isNewer(
        currentVersion: '1.0.0',
        targetVersion: 'v1.1.0',
      ),
      isTrue,
    );
    expect(
      () => VersionComparator.compareSemVer('bad.1.0', '1.0.0'),
      throwsFormatException,
    );
    expect(
      () => VersionComparator.compareSemVer('1.0.0-beta.01', '1.0.0'),
      throwsFormatException,
    );
  });
  test(
    'body timeout and stalled cancellation finish and delete partial files',
    () async {
      for (final cancel in [false, true]) {
        final body = StreamController<List<int>>();
        final client = MockClient.streaming(
          (_, _) async => http.StreamedResponse(body.stream, 200),
        );
        final downloader = ChunkDownloader(client: client);
        final token = CancelToken();
        final file = File('${directory.path}/partial.bin');
        final future = downloader.downloadFile(
          url: 'https://example.com/file',
          destinationFile: file,
          timeout: const Duration(milliseconds: 40),
          cancelToken: token,
        );
        final expectation = expectLater(
          future,
          cancel
              ? throwsA(isA<CancellationException>())
              : throwsA(isA<TimeoutException>()),
        );
        if (cancel) {
          Timer(const Duration(milliseconds: 10), () => token.cancel());
        }
        await expectation;
        expect(await file.exists(), isFalse);
        await body.close();
        downloader.close();
      }
    },
  );
  test('retry transient failures and stop retrying permanent errors', () async {
    for (final code in [503, 404]) {
      var calls = 0;
      final downloader = ChunkDownloader(
        client: MockClient((_) async {
          calls++;
          return calls == 1
              ? http.Response('error', code)
              : http.Response.bytes(Uint8List.fromList([1, 2, 3]), 200);
        }),
      );
      final future = downloader.downloadFile(
        url: 'https://example.com/file',
        destinationFile: File('${directory.path}/retry.bin'),
        retryDelay: Duration.zero,
      );
      if (code == 503) {
        expect(await future, isA<File>());
        expect(calls, 2);
      } else {
        await expectLater(future, throwsA(isA<HttpException>()));
        expect(calls, 1);
      }
      downloader.close();
    }
  });
}
