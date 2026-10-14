import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;

/// Token used to cancel an active download operation.
class CancelToken {
  bool _isCancelled = false;
  String? _reason;
  final Completer<void> _cancelled = Completer<void>();

  bool get isCancelled => _isCancelled;
  String? get reason => _reason;
  Future<void> get whenCancelled => _cancelled.future;

  /// Cancels the download operation with an optional reason.
  void cancel([String? reason]) {
    if (_isCancelled) return;
    _isCancelled = true;
    _reason = reason;
    _cancelled.complete();
  }
}

/// Progress callback receiving received bytes, total bytes and ratio (0.0-1.0).
typedef DownloadProgressCallback =
    void Function(int receivedBytes, int totalBytes, double progress);

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
    int maxRetries = 2,
    Duration retryDelay = const Duration(milliseconds: 300),
  }) async {
    if (timeout <= Duration.zero || maxRetries < 0) {
      throw ArgumentError('Timeout must be positive and retries non-negative.');
    }
    final watch = Stopwatch()..start();
    for (var attempt = 0; ; attempt++) {
      _checkCancelled(cancelToken);
      final remaining = timeout - watch.elapsed;
      if (remaining <= Duration.zero) {
        throw TimeoutException('Download timed out', timeout);
      }
      try {
        return await _downloadAttempt(
          url: url,
          destinationFile: destinationFile,
          headers: headers,
          timeout: remaining,
          onProgress: onProgress,
          cancelToken: cancelToken,
        );
      } catch (error) {
        final retryable =
            error is SocketException ||
            error is http.ClientException ||
            (error is DownloadHttpException &&
                (error.statusCode == 429 || error.statusCode >= 500));
        if (!retryable || attempt >= maxRetries) rethrow;
        final delay = retryDelay * (1 << attempt);
        if (watch.elapsed + delay >= timeout) {
          throw TimeoutException('Download timed out', timeout);
        }
        await Future.any<void>([
          Future<void>.delayed(delay),
          if (cancelToken != null) cancelToken.whenCancelled,
        ]);
      }
    }
  }

  Future<File> _downloadAttempt({
    required String url,
    required File destinationFile,
    required Duration timeout,
    Map<String, String>? headers,
    DownloadProgressCallback? onProgress,
    CancelToken? cancelToken,
  }) async {
    final uri = Uri.parse(url);
    final abort = Completer<void>();
    final stopped = Completer<void>();
    void stop(Object error) {
      if (!abort.isCompleted) abort.complete();
      if (!stopped.isCompleted) stopped.completeError(error);
    }

    final timer = Timer(
      timeout,
      () => stop(TimeoutException('Download timed out', timeout)),
    );
    if (cancelToken != null) {
      unawaited(
        cancelToken.whenCancelled.then((_) {
          if (timer.isActive) {
            stop(
              CancellationException(cancelToken.reason ?? 'Download cancelled'),
            );
          }
        }),
      );
    }
    final request = http.AbortableRequest(
      'GET',
      uri,
      abortTrigger: abort.future,
    );
    if (headers != null) {
      request.headers.addAll(headers);
    }
    IOSink? sink;
    StreamIterator<List<int>>? iterator;
    var succeeded = false;
    try {
      final streamedResponse = await Future.any<http.StreamedResponse>([
        _client.send(request),
        stopped.future.then<http.StreamedResponse>(
          (_) => throw StateError('Stopped'),
        ),
      ]);
      if (streamedResponse.statusCode < 200 ||
          streamedResponse.statusCode >= 300) {
        await streamedResponse.stream.listen((_) {}).cancel();
        throw DownloadHttpException(streamedResponse.statusCode, uri);
      }
      await destinationFile.parent.create(recursive: true);
      final totalBytes = streamedResponse.contentLength ?? 0;
      var receivedBytes = 0;
      sink = destinationFile.openWrite();
      // Observe disk errors immediately, including errors while the network stalls.
      unawaited(
        sink.done.catchError((Object error) {
          stop(error);
        }),
      );
      iterator = StreamIterator(streamedResponse.stream);
      while (await Future.any<bool>([
        iterator.moveNext(),
        stopped.future.then<bool>((_) => false),
      ])) {
        _checkCancelled(cancelToken);
        final chunk = iterator.current;
        sink.add(chunk);
        receivedBytes += chunk.length;
        final progress = totalBytes > 0
            ? (receivedBytes / totalBytes).clamp(0.0, 1.0)
            : 0.0;
        onProgress?.call(receivedBytes, totalBytes, progress);
      }
      if (totalBytes > 0 && receivedBytes != totalBytes) {
        throw http.ClientException(
          'Incomplete download: $receivedBytes/$totalBytes bytes',
          uri,
        );
      }
      await Future.any<void>([sink.flush(), stopped.future]);
      await Future.any<void>([sink.close(), stopped.future]);
      succeeded = true;
      return destinationFile;
    } finally {
      timer.cancel();
      if (!abort.isCompleted) abort.complete();
      await iterator?.cancel();
      try {
        await sink?.close();
      } catch (_) {
        /* Preserve the original failure. */
      }
      if (!succeeded && await destinationFile.exists()) {
        await destinationFile.delete();
      }
    }
  }

  void _checkCancelled(CancelToken? token) {
    if (token?.isCancelled ?? false) {
      throw CancellationException(token!.reason ?? 'Download cancelled');
    }
  }

  /// Closes the internal HTTP client.
  void close() {
    _client.close();
  }
}

class DownloadHttpException extends HttpException {
  final int statusCode;
  DownloadHttpException(this.statusCode, Uri uri)
    : super('Download failed with HTTP $statusCode', uri: uri);
}

/// Exception thrown when a download is cancelled.
class CancellationException implements Exception {
  final String message;

  const CancellationException(this.message);

  @override
  String toString() => 'CancellationException: $message';
}
