import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ever_up_to_date/ever_up_to_date.dart';
import 'package:ever_up_to_date/src/core/ever_up_to_date_engine.dart';
import 'package:ever_up_to_date/src/security/checksum_verifier.dart';

void main() {
  group('EverUpToDateEngine Tests', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('engine_test');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    final sampleManifest = jsonEncode({
      'version': 1,
      'channels': {
        'stable': {
          'version': '2.0.0',
          'build_number': 200,
          'mandatory': false,
          'release_notes': {
            'zh-CN': '2.0 重大更新',
            'en-US': 'Version 2.0 release',
          },
          'platforms': {
            'windows': {
              'type': 'inno_setup',
              'url': 'https://example.com/app-v2.0.0.exe',
            },
            'android': {
              'type': 'direct_apk',
              'url': 'https://example.com/app-v2.0.0.apk',
            },
            'ios': {
              'type': 'testflight',
              'url': 'https://testflight.apple.com/join/demo',
            },
          },
        },
      },
    });

    test('checkForUpdate detects available newer version', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path.endsWith('appcast.json')) {
          return http.Response.bytes(
            utf8.encode(sampleManifest),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        return http.Response('Not found', 404);
      });

      final engine = EverUpToDateEngine(
        httpClient: mockClient,
        platformOverride: TargetPlatformType.windows,
        tempDirResolver: () async => tempDir,
      );

      final states = <UpdateState>[];
      engine.stateNotifier.addListener(() {
        states.add(engine.currentState);
      });

      engine.initialize(
        const UpdateOptions(
          manifestUrl: 'https://example.com/appcast.json',
          currentVersion: '1.0.0',
          currentBuildNumber: 100,
          channel: 'stable',
          preferredLocale: 'zh-CN',
        ),
      );

      final update = await engine.checkForUpdate();

      expect(update, isNotNull);
      expect(update!.targetVersion, equals('2.0.0'));
      expect(update.releaseNotes, equals('2.0 重大更新'));
      expect(engine.currentState, isA<UpdateAvailableState>());
      expect(states.any((s) => s is UpdateCheckingState), isTrue);
      expect(states.any((s) => s is UpdateAvailableState), isTrue);
    });

    test('checkForUpdate detects up-to-date state', () async {
      final mockClient = MockClient((request) async {
        return http.Response.bytes(
          utf8.encode(sampleManifest),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      final engine = EverUpToDateEngine(
        httpClient: mockClient,
        platformOverride: TargetPlatformType.windows,
        tempDirResolver: () async => tempDir,
      );

      engine.initialize(
        const UpdateOptions(
          manifestUrl: 'https://example.com/appcast.json',
          currentVersion: '2.0.0',
          currentBuildNumber: 200,
        ),
      );

      final update = await engine.checkForUpdate();

      expect(update, isNull);
      expect(engine.currentState, isA<UpdateUpToDateState>());
    });

    test('downloadUpdate and verify SHA256 checksum', () async {
      final binaryBytes = utf8.encode('installer-binary-payload');
      final validSha256 = ChecksumVerifier.computeSha256(binaryBytes);

      final manifestWithHash = jsonEncode({
        'version': 1,
        'channels': {
          'stable': {
            'version': '2.0.0',
            'platforms': {
              'windows': {
                'type': 'inno_setup',
                'url': 'https://example.com/setup.exe',
                'sha256': validSha256,
              },
            },
          },
        },
      });

      final mockClient = MockClient((request) async {
        if (request.url.path.endsWith('appcast.json')) {
          return http.Response.bytes(
            utf8.encode(manifestWithHash),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        if (request.url.path.endsWith('setup.exe')) {
          return http.Response.bytes(
            binaryBytes,
            200,
            headers: {'content-length': '${binaryBytes.length}'},
          );
        }
        return http.Response('Not found', 404);
      });

      final engine = EverUpToDateEngine(
        httpClient: mockClient,
        platformOverride: TargetPlatformType.windows,
        tempDirResolver: () async => tempDir,
      );

      engine.initialize(
        const UpdateOptions(
          manifestUrl: 'https://example.com/appcast.json',
          currentVersion: '1.0.0',
        ),
      );

      await engine.checkForUpdate();
      final downloaded = await engine.downloadUpdate();

      expect(downloaded, isNotNull);
      expect(await downloaded!.exists(), isTrue);
      expect(engine.currentState, isA<UpdateReadyToInstallState>());
    });

    test('downloadUpdate skips download for external store packages', () async {
      final mockClient = MockClient((request) async {
        return http.Response.bytes(
          utf8.encode(sampleManifest),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      final engine = EverUpToDateEngine(
        httpClient: mockClient,
        platformOverride: TargetPlatformType.ios,
        tempDirResolver: () async => tempDir,
      );

      engine.initialize(
        const UpdateOptions(
          manifestUrl: 'https://example.com/appcast.json',
          currentVersion: '1.0.0',
        ),
      );

      await engine.checkForUpdate();
      final downloaded = await engine.downloadUpdate();

      expect(downloaded, isNull);
      expect(engine.currentState, isA<UpdateReadyToInstallState>());
    });
  });
}
