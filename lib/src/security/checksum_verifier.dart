import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

/// File and byte array checksum verifier.
class ChecksumVerifier {
  /// Computes the SHA-256 hash string of [bytes].
  static String computeSha256(List<int> bytes) {
    return sha256.convert(bytes).toString();
  }

  /// Computes the SHA-256 hash string of the file at [file].
  static Future<String> computeFileSha256(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  }

  /// Verifies if [file] matches [expectedSha256].
  static Future<bool> verifyFile({
    required File file,
    required String expectedSha256,
  }) async {
    if (!await file.exists()) {
      return false;
    }
    final actualHash = await computeFileSha256(file);
    return actualHash.toLowerCase() == expectedSha256.trim().toLowerCase();
  }

  /// Verifies if [bytes] matches [expectedSha256].
  static bool verifyBytes({
    required Uint8List bytes,
    required String expectedSha256,
  }) {
    final actualHash = computeSha256(bytes);
    return actualHash.toLowerCase() == expectedSha256.trim().toLowerCase();
  }
}
