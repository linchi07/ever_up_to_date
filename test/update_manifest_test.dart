import 'package:flutter_test/flutter_test.dart';
import 'package:ever_up_to_date/src/model/package_type.dart';
import 'package:ever_up_to_date/src/model/target_platform_type.dart';
import 'package:ever_up_to_date/src/model/update_manifest.dart';

void main() {
  group('UpdateManifest Tests', () {
    final sampleJson = {
      'version': 1,
      'app_id': 'com.example.app',
      'channels': {
        'stable': {
          'version': '1.0.1',
          'build_number': 101,
          'mandatory': false,
          'pub_date': '2026-10-13T12:00:00Z',
          'release_notes': {
            'zh-CN': '修复已知问题',
            'en-US': 'Bug fixes',
            'default': 'Maintenance release',
          },
          'platforms': {
            'android': {
              'type': 'direct_apk',
              'url': 'https://oss.example.com/app-v1.0.1.apk',
              'sha256': 'a1b2c3d4e5f6',
              'signature_ed25519': 'sig123',
              'file_size': 15000000,
            },
            'windows': {
              'type': 'inno_setup',
              'url': 'https://oss.example.com/app-setup-v1.0.1.exe',
              'installer_args': ['/VERYSILENT', '/SUPPRESSMSGBOXES'],
            },
            'ios': {
              'type': 'testflight',
              'url': 'https://testflight.apple.com/join/demo123',
            },
          },
        },
        'beta': {
          'version': '1.1.0-beta.1',
          'build_number': 110,
          'mandatory': true,
          'release_notes': 'Beta preview notes',
          'platforms': {
            'android': {
              'type': 'direct_apk',
              'url': 'https://oss.example.com/app-v1.1.0-beta.apk',
            },
          },
        },
      },
    };

    test('parses channels and metadata correctly', () {
      final manifest = UpdateManifest.fromJson(sampleJson);
      expect(manifest.schemaVersion, equals(1));
      expect(manifest.appId, equals('com.example.app'));

      final stable = manifest.getChannel('stable');
      expect(stable, isNotNull);
      expect(stable!.version, equals('1.0.1'));
      expect(stable.buildNumber, equals(101));
      expect(stable.mandatory, isFalse);

      final androidTarget = stable.getTarget(TargetPlatformType.android);
      expect(androidTarget, isNotNull);
      expect(androidTarget!.type, equals(PackageType.directApk));
      expect(androidTarget.url, equals('https://oss.example.com/app-v1.0.1.apk'));
      expect(androidTarget.sha256, equals('a1b2c3d4e5f6'));
      expect(androidTarget.signatureEd25519, equals('sig123'));
      expect(androidTarget.fileSize, equals(15000000));

      final windowsTarget = stable.getTarget(TargetPlatformType.windows);
      expect(windowsTarget, isNotNull);
      expect(windowsTarget!.type, equals(PackageType.innoSetup));
      expect(
        windowsTarget.installerArgs,
        equals(['/VERYSILENT', '/SUPPRESSMSGBOXES']),
      );

      final iosTarget = stable.getTarget(TargetPlatformType.ios);
      expect(iosTarget, isNotNull);
      expect(iosTarget!.type, equals(PackageType.testflight));
      expect(iosTarget.type.isExternalStore, isTrue);
    });

    test('resolves localized release notes accurately', () {
      final manifest = UpdateManifest.fromJson(sampleJson);
      final stable = manifest.getChannel('stable')!;

      expect(stable.getLocalizedReleaseNotes('zh-CN'), equals('修复已知问题'));
      expect(stable.getLocalizedReleaseNotes('zh'), equals('修复已知问题'));
      expect(stable.getLocalizedReleaseNotes('en-US'), equals('Bug fixes'));
      expect(stable.getLocalizedReleaseNotes('fr-FR'), equals('Maintenance release'));

      final beta = manifest.getChannel('beta')!;
      expect(beta.getLocalizedReleaseNotes('zh-CN'), equals('Beta preview notes'));
    });
  });
}
