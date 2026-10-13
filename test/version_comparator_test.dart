import 'package:flutter_test/flutter_test.dart';
import 'package:ever_up_to_date/src/version/version_comparator.dart';

void main() {
  group('VersionComparator Tests', () {
    test('standard SemVer comparisons', () {
      expect(
        VersionComparator.isNewer(
          currentVersion: '1.0.0',
          targetVersion: '1.0.1',
        ),
        isTrue,
      );

      expect(
        VersionComparator.isNewer(
          currentVersion: '1.0.0',
          targetVersion: '1.1.0',
        ),
        isTrue,
      );

      expect(
        VersionComparator.isNewer(
          currentVersion: '1.0.0',
          targetVersion: '2.0.0',
        ),
        isTrue,
      );

      expect(
        VersionComparator.isNewer(
          currentVersion: '1.2.3',
          targetVersion: '1.2.3',
        ),
        isFalse,
      );

      expect(
        VersionComparator.isNewer(
          currentVersion: '2.0.0',
          targetVersion: '1.9.9',
        ),
        isFalse,
      );
    });

    test('pre-release comparisons', () {
      // Release is newer than pre-release
      expect(
        VersionComparator.isNewer(
          currentVersion: '1.0.0-beta.1',
          targetVersion: '1.0.0',
        ),
        isTrue,
      );

      // Beta is newer than alpha
      expect(
        VersionComparator.isNewer(
          currentVersion: '1.0.0-alpha.1',
          targetVersion: '1.0.0-beta.1',
        ),
        isTrue,
      );

      // Pre-release tag increment
      expect(
        VersionComparator.isNewer(
          currentVersion: '1.0.0-beta.1',
          targetVersion: '1.0.0-beta.2',
        ),
        isTrue,
      );

      expect(
        VersionComparator.isNewer(
          currentVersion: '1.0.0',
          targetVersion: '1.0.0-beta.1',
        ),
        isFalse,
      );
    });

    test('build number comparisons when semver is equal', () {
      expect(
        VersionComparator.isNewer(
          currentVersion: '1.0.0',
          currentBuild: 100,
          targetVersion: '1.0.0',
          targetBuild: 101,
        ),
        isTrue,
      );

      expect(
        VersionComparator.isNewer(
          currentVersion: '1.0.0',
          currentBuild: 105,
          targetVersion: '1.0.0',
          targetBuild: 105,
        ),
        isFalse,
      );

      expect(
        VersionComparator.isNewer(
          currentVersion: '1.0.0',
          currentBuild: 200,
          targetVersion: '1.0.0',
          targetBuild: 150,
        ),
        isFalse,
      );
    });
  });
}
