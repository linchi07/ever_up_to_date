import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;

/// Token used to cancel an active download operation.
class CancelToken {
  bool _isCancelled = false;
  String? _reason;

  bool get isCancelled => _isCancelled;
  String? get reason => _reason;

  /// Cancels the download operation with an optional reason.
  void cancel([String? reason]) {
    _isCancelled = true;
    _reason = reason;
  }
}

/// Progress callback receiving received bytes, total bytes and ratio (0.0-1.0).
typedef DownloadProgressCallback = void Function(
  int receivedBytes,
  int totalBytes,
  double progress,
);

/// Streamed HTTP downloader with progress reporting and cancellation support.
class ChunkDownloader {
  final http.Client _client;

  ChunkDownloader({http.Client? client}) : _client = client ?? http.Client();

  /// Downloads a remote file at [url] to [destinationFile].
  Future<File> downloadFile({
    required String url,
    required File destinationFile,
    Map<String, String>? headers,
    Duration timeout = const Duration(minutes: 10),
    DownloadProgressCallback? onProgress,
    CancelToken? cancelToken,
  }) async {
    final uri = Uri.parse(url);
    final request = http.Request('GET', uri);
    if (headers != null) {
      request.headers.addAll(headers);
    }

    final streamedResponse = await _client.send(request).timeout(timeout);

    if (streamedResponse.statusCode < 200 ||
        streamedResponse.statusCode >= 300) {
      throw HttpException(
        'Download failed with HTTP ${streamedResponse.statusCode}: $url',
        uri: uri,
      );
    }

    // Ensure parent directory exists
    final parentDir = destinationFile.parent;
    if (!await parentDir.exists()) {
      await parentDir.create(recursive: true);
    }

    // If destination file already exists, delete it first
    if (await destinationFile.exists()) {
      await destinationFile.delete();
    }

    final totalBytes = streamedResponse.contentLength ?? 0;
    var receivedBytes = 0;

    final sink = destinationFile.openWrite();

    try {
      await for (final chunk in streamedResponse.stream) {
        if (cancelToken != null && cancelToken.isCancelled) {
          await sink.close();
          if (await destinationFile.exists()) {
            await destinationFile.delete();
          }
          throw CancellationException(
            cancelToken.reason ?? 'Download cancelled by user',
          );
        }

        sink.add(chunk);
        receivedBytes += chunk.length;

        final progress =
            totalBytes > 0 ? (receivedBytes / totalBytes).clamp(0.0, 1.0) : 0.0;
        onProgress?.call(receivedBytes, totalBytes, progress);
      }

      await sink.flush();
      await sink.close();
      return destinationFile;
    } catch (e) {
      await sink.close();
      if (await destinationFile.exists()) {
        await destinationFile.delete();
      }
      rethrow;
    }
  }

  /// Closes the internal HTTP client.
  void close() {
    _client.close();
  }
}

/// Exception thrown when a download is cancelled.
class CancellationException implements Exception {
  final String message;

  const CancellationException(this.message);

  @override
  String toString() => 'CancellationException: $message';
}
