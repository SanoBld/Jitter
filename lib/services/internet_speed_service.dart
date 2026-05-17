import 'dart:async';
import 'package:http/http.dart' as http;

// ── Model ──────────────────────────────────────────────────────────────────
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

// ── Service ────────────────────────────────────────────────────────────────
class InternetSpeedService {
  static const List<SpeedServer> servers = [
    // Hetzner Europe
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
    // Hetzner Americas
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
    // Hetzner Asia
    SpeedServer(
      name: 'Singapore',
      location: 'Singapore, SG',
      provider: 'Hetzner',
      flag: '🇸🇬',
      downloadUrl: 'https://sin-speed.hetzner.com/100MB.bin',
    ),
    // Other providers
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

  // ── Ping ────────────────────────────────────────────────────────────────
  /// Returns latency in ms (999 on failure).
  Future<int> testPing(int serverIndex) async {
    final server = _server(serverIndex);
    final sw = Stopwatch()..start();
    try {
      final r = await http.head(Uri.parse(server.pingUrl))
          .timeout(const Duration(seconds: 5));
      sw.stop();
      return r.statusCode < 400 ? sw.elapsedMilliseconds : 999;
    } catch (_) {
      sw.stop();
      return 999;
    }
  }

  // ── Download ─────────────────────────────────────────────────────────────
  /// Yields Mbps readings as bytes arrive.
  /// Stops after [maxMB] megabytes (no need to download the whole file).
  Stream<double> testDownloadSpeed({
    required int serverIndex,
    required int maxMB,
  }) async* {
    final server = _server(serverIndex);
    final sw = Stopwatch()..start();
    final client = http.Client();
    try {
      final req = http.Request('GET', Uri.parse(server.downloadUrl));
      final res = await client.send(req).timeout(_timeout);

      int received = 0;
      final maxBytes = maxMB * 1024 * 1024;

      await for (final chunk in res.stream) {
        received += chunk.length;
        final secs = sw.elapsedMilliseconds / 1000.0;
        // Only start yielding after a short warmup (0.3s) for accuracy
        if (secs > 0.3) {
          yield (received / secs / (1024 * 1024)) * 8; // bits/s → Mbps
        }
        if (received >= maxBytes) break;
      }
    } catch (e) {
      rethrow;
    } finally {
      client.close();
    }
  }

  // ── Upload ───────────────────────────────────────────────────────────────
  /// Returns Mbps result (0.0 on failure).
  Future<double> testUploadSpeed({int sizeMB = 4}) async {
    final client = http.Client();
    try {
      final sw = Stopwatch();
      final payload = List<int>.generate(sizeMB * 1024 * 1024, (i) => i % 256);
      sw.start();
      final req = http.MultipartRequest('POST', Uri.parse(_uploadUrl))
        ..files.add(
          http.MultipartFile.fromBytes('file', payload, filename: 'upload.bin'),
        );
      final res = await client.send(req).timeout(_timeout);
      sw.stop();
      if (res.statusCode == 200) {
        final secs = sw.elapsedMilliseconds / 1000.0;
        return ((sizeMB * 1024 * 1024) / secs / (1024 * 1024)) * 8;
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
