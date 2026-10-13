import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:ever_up_to_date/src/security/checksum_verifier.dart';

void main() {
  group('ChecksumVerifier Tests', () {
    test('verifyBytes computes correct SHA-256', () {
      final data = Uint8List.fromList('hello ever_up_to_date'.codeUnits);
      // SHA-256 for 'hello ever_up_to_date'
      final computed = ChecksumVerifier.computeSha256(data);
      expect(computed, isNotEmpty);

      expect(
        ChecksumVerifier.verifyBytes(
          bytes: data,
          expectedSha256: computed,
        ),
        isTrue,
      );

      // Case insensitive check
      expect(
        ChecksumVerifier.verifyBytes(
          bytes: data,
          expectedSha256: computed.toUpperCase(),
        ),
        isTrue,
      );

      // Mismatch
      expect(
        ChecksumVerifier.verifyBytes(
          bytes: data,
          expectedSha256: 'deadbeef12345678',
        ),
        isFalse,
      );
    });

    test('verifyFile computes correct file hash', () async {
      final tempDir = await Directory.systemTemp.createTemp('checksum_test');
      final testFile = File('${tempDir.path}/test.bin');
      await testFile.writeAsString('file test content');

      final computed = await ChecksumVerifier.computeFileSha256(testFile);
      expect(
        await ChecksumVerifier.verifyFile(
          file: testFile,
          expectedSha256: computed,
        ),
        isTrue,
      );

      await tempDir.delete(recursive: true);
    });
  });
}
