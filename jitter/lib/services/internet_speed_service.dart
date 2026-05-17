import 'dart:async';
import 'package:http/http.dart' as http;

class InternetSpeedService {
  static const String _downloadUrl = 'https://speed.hetzner.de/100MB.bin';
  static const String _uploadUrl   = 'https://httpbin.org/post';
  static const Duration _timeout   = Duration(seconds: 15);

  Future<int> testPing() async {
    final stopwatch = Stopwatch()..start();
    try {
      final response = await http.head(Uri.parse(_downloadUrl)).timeout(const Duration(seconds: 5));
      stopwatch.stop();
      if (response.statusCode == 200) {
        return stopwatch.elapsedMilliseconds;
      }
      return 999;
    } catch (_) {
      stopwatch.stop();
      return 999;
    }
  }

  Stream<double> testDownloadSpeed() async* {
    final stopwatch = Stopwatch()..start();
    final client = http.Client();
    try {
      final request = http.Request('GET', Uri.parse(_downloadUrl));
      final response = await client.send(request).timeout(_timeout);
      int receivedBytes = 0;
      await for (final chunk in response.stream) {
        receivedBytes += chunk.length;
        final double seconds = stopwatch.elapsedMilliseconds / 1000.0;
        if (seconds > 0) {
          yield (receivedBytes / seconds / (1024 * 1024)) * 8;
        }
      }
    } catch (_) {
      rethrow;
    } finally {
      client.close();
    }
  }

  Future<double> testUploadSpeed() async {
    final stopwatch = Stopwatch();
    final client = http.Client();
    try {
      final List<int> dummyData = List<int>.generate(2 * 1024 * 1024, (i) => i % 256);
      stopwatch.start();
      final request = http.MultipartRequest('POST', Uri.parse(_uploadUrl))
        ..files.add(http.MultipartFile.fromBytes('file', dummyData, filename: 'upload.bin'));
      final response = await client.send(request).timeout(_timeout);
      stopwatch.stop();
      if (response.statusCode == 200) {
        final double seconds = stopwatch.elapsedMilliseconds / 1000.0;
        return ((2 * 1024 * 1024) / seconds / (1024 * 1024)) * 8;
      }
      return 0.0;
    } catch (_) {
      return 0.0;
    } finally {
      client.close();
    }
  }
}