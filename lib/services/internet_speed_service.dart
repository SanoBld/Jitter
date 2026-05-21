import 'dart:async';
import 'package:http/http.dart' as http;

class SpeedServer {
  final String name;
  final String location;
  final String provider;
  final String flag;
  final String downloadUrl;

  const SpeedServer({
    required this.name,
    required this.location,
    required this.provider,
    required this.flag,
    required this.downloadUrl,
  });

  String get pingUrl => downloadUrl;
  String get displayLine => '$flag  $name — $provider';
  String get subtitle => location;
}

class InternetSpeedService {
  static const List<SpeedServer> servers = [
    SpeedServer(
      name: 'Paris',
      location: 'Paris, FR',
      provider: 'Hetzner',
      flag: '🇫🇷',
      downloadUrl: 'https://speed.hetzner.de/100MB.bin',
    ),
    SpeedServer(
      name: 'Falkenstein',
      location: 'Falkenstein, DE',
      provider: 'Hetzner',
      flag: '🇩🇪',
      downloadUrl: 'https://fsn1-speed.hetzner.com/100MB.bin',
    ),
    SpeedServer(
      name: 'Nuremberg',
      location: 'Nuremberg, DE',
      provider: 'Hetzner',
      flag: '🇩🇪',
      downloadUrl: 'https://nbg1-speed.hetzner.com/100MB.bin',
    ),
    SpeedServer(
      name: 'Helsinki',
      location: 'Helsinki, FI',
      provider: 'Hetzner',
      flag: '🇫🇮',
      downloadUrl: 'https://hel1-speed.hetzner.com/100MB.bin',
    ),
    SpeedServer(
      name: 'Ashburn',
      location: 'Ashburn, US',
      provider: 'Hetzner',
      flag: '🇺🇸',
      downloadUrl: 'https://ash-speed.hetzner.com/100MB.bin',
    ),
    SpeedServer(
      name: 'Hillsboro',
      location: 'Hillsboro, US',
      provider: 'Hetzner',
      flag: '🇺🇸',
      downloadUrl: 'https://hil-speed.hetzner.com/100MB.bin',
    ),
    SpeedServer(
      name: 'Singapore',
      location: 'Singapore, SG',
      provider: 'Hetzner',
      flag: '🇸🇬',
      downloadUrl: 'https://sin-speed.hetzner.com/100MB.bin',
    ),
    SpeedServer(
      name: 'Paris',
      location: 'Paris, FR',
      provider: 'OVH',
      flag: '🇫🇷',
      downloadUrl: 'https://proof.ovh.net/files/100Mb.dat',
    ),
  ];

  static const String _uploadUrl = 'https://httpbin.org/post';
  static const Duration _timeout = Duration(seconds: 30);

  // Ping: GET with Range header so we download only 1 byte.
  // This avoids 405 errors from CDN servers that reject HEAD requests.
  Future<int> testPing(int serverIndex) async {
    final server = _server(serverIndex);
    final client = http.Client();
    final sw = Stopwatch()..start();
    try {
      final request = http.Request('GET', Uri.parse(server.pingUrl));
      request.headers['Range'] = 'bytes=0-0';
      final response = await client.send(request).timeout(const Duration(seconds: 5));
      sw.stop();
      // 206 = Partial Content (Range supported), 200 = Range ignored but alive
      if (response.statusCode == 200 || response.statusCode == 206) {
        return sw.elapsedMilliseconds;
      }
      return 999;
    } catch (_) {
      sw.stop();
      return 999;
    } finally {
      client.close(); // also cancels any pending stream
    }
  }

  // Download: streams Mbps readings as data arrives.
  // Stops after maxMB megabytes.
  Stream<double> testDownloadSpeed({
    required int serverIndex,
    required int maxMB,
  }) async* {
    final server = _server(serverIndex);
    final client = http.Client();
    final sw = Stopwatch()..start();
    try {
      final request = http.Request('GET', Uri.parse(server.downloadUrl));
      final response = await client.send(request).timeout(_timeout);

      if (response.statusCode >= 400) {
        throw Exception('Server returned ${response.statusCode}');
      }

      int received = 0;
      final maxBytes = maxMB * 1024 * 1024;

      await for (final chunk in response.stream) {
        received += chunk.length;
        final secs = sw.elapsedMilliseconds / 1000.0;
        // Skip the first 0.3s to let the connection warm up
        if (secs > 0.3) {
          // bytes → bits → megabits per second
          yield (received * 8) / secs / (1024 * 1024);
        }
        if (received >= maxBytes) break;
      }
    } finally {
      client.close();
    }
  }

  // Upload: sends a buffer and measures throughput.
  Future<double> testUploadSpeed({int sizeMB = 4}) async {
    final client = http.Client();
    try {
      final payload = List<int>.generate(sizeMB * 1024 * 1024, (i) => i & 0xFF);
      final sw = Stopwatch()..start();
      final request = http.MultipartRequest('POST', Uri.parse(_uploadUrl))
        ..files.add(
          http.MultipartFile.fromBytes('file', payload, filename: 'upload.bin'),
        );
      final response = await client.send(request).timeout(_timeout);
      sw.stop();
      if (response.statusCode == 200) {
        final secs = sw.elapsedMilliseconds / 1000.0;
        return (payload.length * 8) / secs / (1024 * 1024);
      }
      return 0.0;
    } catch (_) {
      return 0.0;
    } finally {
      client.close();
    }
  }

  SpeedServer _server(int index) =>
      servers[index.clamp(0, servers.length - 1)];
}