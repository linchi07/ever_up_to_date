import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ever_up_to_date/src/security/signature_verifier.dart';

void main() {
  group('SignatureVerifier Tests', () {
    test('verifyEd25519 validates legitimate signature', () async {
      final algorithm = Ed25519();
      final keyPair = await algorithm.newKeyPair();
      final publicKey = await keyPair.extractPublicKey();

      final data = Uint8List.fromList(utf8.encode('update-package-binary-data'));
      final signature = await algorithm.sign(data, keyPair: keyPair);

      final pubKeyBase64 = base64Encode(publicKey.bytes);
      final sigBase64 = base64Encode(signature.bytes);

      final isValid = await SignatureVerifier.verifyEd25519(
        dataBytes: data,
        signatureString: sigBase64,
        publicKeyString: pubKeyBase64,
      );

      expect(isValid, isTrue);

      // Verify tampered data fails
      final tamperedData =
          Uint8List.fromList(utf8.encode('tampered-binary-data'));
      final isTamperedValid = await SignatureVerifier.verifyEd25519(
        dataBytes: tamperedData,
        signatureString: sigBase64,
        publicKeyString: pubKeyBase64,
      );

      expect(isTamperedValid, isFalse);
    });

    test('verifyFileEd25519 validates file content', () async {
      final algorithm = Ed25519();
      final keyPair = await algorithm.newKeyPair();
      final publicKey = await keyPair.extractPublicKey();

      final tempDir = await Directory.systemTemp.createTemp('sig_test');
      final testFile = File('${tempDir.path}/app.apk');
      final bytes = Uint8List.fromList(utf8.encode('sample apk content'));
      await testFile.writeAsBytes(bytes);

      final signature = await algorithm.sign(bytes, keyPair: keyPair);

      final pubKeyBase64 = base64Encode(publicKey.bytes);
      final sigBase64 = base64Encode(signature.bytes);

      final isValid = await SignatureVerifier.verifyFileEd25519(
        file: testFile,
        signatureString: sigBase64,
        publicKeyString: pubKeyBase64,
      );

      expect(isValid, isTrue);

      await tempDir.delete(recursive: true);
    });
  });
}
