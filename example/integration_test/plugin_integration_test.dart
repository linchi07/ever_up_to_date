import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:cryptography/cryptography.dart';
import 'package:ever_up_to_date/ever_up_to_date.dart';
import 'package:ever_up_to_date/src/core/ever_up_to_date_engine.dart';
import 'package:ever_up_to_date/src/installer/app_installer.dart';
import 'package:ever_up_to_date/src/security/checksum_verifier.dart';

class _Installer implements AppInstaller {
  String? installedPath;
  @override
  Future<bool> install({
    required String filePath,
    required PlatformTarget target,
    List<String>? customArgs,
    bool autoExit = true,
  }) async {
    installedPath = filePath;
    return true;
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'signed local release completes download, handoff and restart confirmation',
    (tester) async {
      final directory = await Directory.systemTemp.createTemp(
        'everup-integration',
      );
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final data = utf8.encode('integration installer fixture');
      final pair = await Ed25519().newKeyPair();
      final public = await pair.extractPublicKey();
      final signature = await Ed25519().sign(data, keyPair: pair);
      final base = 'http://127.0.0.1:${server.port}';
      final manifest = jsonEncode({
        'version': 1,
        'app_id': 'com.example.test',
        'channels': {
          'stable': {
            'version': '2.0.0',
            'build_number': 20,
            'platforms': {
              'windows': {
                'type': 'inno_setup',
                'url': '$base/setup.exe',
                'file_size': data.length,
                'sha256': ChecksumVerifier.computeSha256(data),
                'signature_ed25519': base64Encode(signature.bytes),
              },
            },
          },
        },
      });
      final subscription = server.listen((request) async {
        if (request.uri.path == '/appcast.json') {
          request.response.headers.contentType = ContentType.json;
          request.response.write(manifest);
        } else {
          request.response.contentLength = data.length;
          request.response.add(data);
        }
        await request.response.close();
      });
      final installer = _Installer();
      final engine = EverUpToDateEngine(
        platformOverride: TargetPlatformType.windows,
        tempDirResolver: () async => directory,
        supportDirResolver: () async => directory,
        installerResolver: (_, _) => installer,
      );
      UpdateOptions options(String current) => UpdateOptions(
        manifestUrl: '$base/appcast.json',
        currentVersion: current,
        currentBuildNumber: 20,
        expectedAppId: 'com.example.test',
        publicKeyEd25519: base64Encode(public.bytes),
      );
      try {
        engine.initialize(options('1.0.0'));
        expect((await engine.checkForUpdate())!.targetVersion, '2.0.0');
        final file = await engine.downloadUpdate();
        expect(await file!.readAsBytes(), data);
        expect(await engine.installUpdate(autoExit: false), isTrue);
        expect(installer.installedPath, file.path);
        engine.initialize(options('2.0.0'));
        expect((await engine.confirmInstalledUpdate())!.confirmed, isTrue);
        expect(engine.currentState, isA<UpdateInstalledState>());
      } finally {
        engine.dispose();
        await server.close(force: true);
        await subscription.cancel();
        await directory.delete(recursive: true);
      }
    },
  );
}
