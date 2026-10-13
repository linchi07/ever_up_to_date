import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ever_up_to_date/src/downloader/chunk_downloader.dart';

void main() {
  group('ChunkDownloader Tests', () {
    test('downloads file and reports progress', () async {
      final mockData = List.generate(1000, (i) => i % 256);
      final mockClient = MockClient((request) async {
        return http.Response.bytes(
          mockData,
          200,
          headers: {'content-length': '${mockData.length}'},
        );
      });

      final downloader = ChunkDownloader(client: mockClient);
      final tempDir = await Directory.systemTemp.createTemp('dl_test');
      final targetFile = File('${tempDir.path}/out.bin');

      final progressEvents = <double>[];

      final downloaded = await downloader.downloadFile(
        url: 'https://example.com/file.bin',
        destinationFile: targetFile,
        onProgress: (received, total, progress) {
          progressEvents.add(progress);
        },
      );

      expect(await downloaded.exists(), isTrue);
      expect(await downloaded.readAsBytes(), equals(mockData));
      expect(progressEvents, isNotEmpty);
      expect(progressEvents.last, equals(1.0));

      await tempDir.delete(recursive: true);
    });

    test('throws HttpException on HTTP 404', () async {
      final mockClient = MockClient((request) async {
        return http.Response('Not Found', 404);
      });

      final downloader = ChunkDownloader(client: mockClient);
      final tempDir = await Directory.systemTemp.createTemp('dl_test');
      final targetFile = File('${tempDir.path}/out.bin');

      expect(
        () => downloader.downloadFile(
          url: 'https://example.com/notfound.bin',
          destinationFile: targetFile,
        ),
        throwsA(isA<HttpException>()),
      );

      await tempDir.delete(recursive: true);
    });

    test('cancels download when CancelToken is triggered', () async {
      final mockData = List.generate(50000, (i) => i % 256);
      final cancelToken = CancelToken();

      final mockClient = MockClient.streaming((request, bodyStream) async {
        final stream = Stream<List<int>>.periodic(
          const Duration(milliseconds: 10),
          (count) => mockData.sublist(count * 1000, (count + 1) * 1000),
        ).take(50);

        return http.StreamedResponse(
          stream,
          200,
          contentLength: mockData.length,
        );
      });

      final downloader = ChunkDownloader(client: mockClient);
      final tempDir = await Directory.systemTemp.createTemp('dl_cancel');
      final targetFile = File('${tempDir.path}/out.bin');

      // Cancel after small delay
      Future.delayed(const Duration(milliseconds: 25), () {
        cancelToken.cancel('User aborted');
      });

      expect(
        () => downloader.downloadFile(
          url: 'https://example.com/slow.bin',
          destinationFile: targetFile,
          cancelToken: cancelToken,
        ),
        throwsA(isA<CancellationException>()),
      );

      // Verify destination file was cleaned up
      await Future.delayed(const Duration(milliseconds: 50));
      expect(await targetFile.exists(), isFalse);

      await tempDir.delete(recursive: true);
    });
  });
}
