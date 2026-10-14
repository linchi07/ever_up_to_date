import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';

/// Ed25519 digital signature verifier.
class SignatureVerifier {
  static final Ed25519 ED25519_ALGORITHM = Ed25519();

  static bool isValidPublicKey(String value) {
    try {
      return _decodeString(value.trim()).length == 32;
    } catch (_) {
      return false;
    }
  }

  /// Verifies [dataBytes] with [signatureString] and [publicKeyString].
  ///
  /// Supports Base64 or Hex encoded signatures and public keys.
  static Future<bool> verifyEd25519({
    required Uint8List dataBytes,
    required String signatureString,
    required String publicKeyString,
  }) async {
    try {
      final sigBytes = _decodeString(signatureString.trim());
      final keyBytes = _decodeString(publicKeyString.trim());
      if (sigBytes.length != 64 || keyBytes.length != 32) return false;

      final simplePublicKey = SimplePublicKey(
        keyBytes,
        type: KeyPairType.ed25519,
      );

      final signature = Signature(sigBytes, publicKey: simplePublicKey);

      return await ED25519_ALGORITHM.verify(dataBytes, signature: signature);
    } catch (_) {
      return false;
    }
  }

  /// Verifies the binary content of [file] against Ed25519 signature.
  static Future<bool> verifyFileEd25519({
    required File file,
    required String signatureString,
    required String publicKeyString,
  }) async {
    if (!await file.exists()) {
      return false;
    }
    final bytes = await file.readAsBytes();
    return verifyEd25519(
      dataBytes: bytes,
      signatureString: signatureString,
      publicKeyString: publicKeyString,
    );
  }

  static Uint8List _decodeString(String input) {
    final clean = input.replaceAll(RegExp(r'\s+'), '');
    // Try hex first if string looks like hex and length matches typical 32/64 byte hex
    final isHex = RegExp(r'^[0-9a-fA-F]+$').hasMatch(clean);
    if (isHex && (clean.length == 64 || clean.length == 128)) {
      final result = Uint8List(clean.length ~/ 2);
      for (var i = 0; i < clean.length; i += 2) {
        result[i ~/ 2] = int.parse(clean.substring(i, i + 2), radix: 16);
      }
      return result;
    }

    // Default to Base64
    return base64Decode(clean);
  }
}
