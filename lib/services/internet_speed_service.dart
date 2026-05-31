import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

class SpeedServer {
  final String name;
  final String location;
  final String provider;
  final String flag;
  final String downloadUrl;
  // true = works on Flutter Web (server has CORS headers)
  final bool corsCompatible;

  const SpeedServer({
    required this.name,
    required this.location,
    required this.provider,
    required this.flag,
    required this.downloadUrl,
    this.corsCompatible = false,
  });

  String get pingUrl      => downloadUrl;
  String get displayLine  => '$flag  $name — $provider';
  String get subtitle     => location;
}

class InternetSpeedService {
  static const List<SpeedServer> servers = [
    // ── CORS-compatible servers (web + native) ─────────────────────────────
    SpeedServer(
      name: 'Cloudflare Global',
      location: 'Anycast, Global',
      provider: 'Cloudflare',
      flag: '🌐',
      downloadUrl: 'https://speed.cloudflare.com/__down?bytes=104857600',
      corsCompatible: true,
    ),
    SpeedServer(
      name: 'Cloudflare 10 MB',
      location: 'Anycast, Global',
      provider: 'Cloudflare',
      flag: '🌐',
      downloadUrl: 'https://speed.cloudflare.com/__down?bytes=10485760',
      corsCompatible: true,
    ),

    // ── Native-only servers (no CORS) ──────────────────────────────────────
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

  // Only show CORS-compatible servers when running in a browser
  static List<SpeedServer> get availableServers =>
      kIsWeb ? servers.where((s) => s.corsCompatible).toList() : servers;

  // If on web, fall back to the first CORS-compatible server
  static int resolveServerIndex(int index) {
    if (!kIsWeb) return index.clamp(0, servers.length - 1);
    final available = availableServers;
    if (available.isEmpty) return 0;
    final server = servers[index.clamp(0, servers.length - 1)];
    if (server.corsCompatible) return index;
    return servers.indexOf(available.first);
  }

  static const List<String> _uploadUrls = [
    'https://speed.cloudflare.com/__up',
    'https://httpbin.org/post',
    'https://postman-echo.com/post',
  ];

  static const Duration _connectTimeout = Duration(seconds: 10);
  static const Duration _streamTimeout  = Duration(seconds: 90);

  // ── Auto-detect location and ISP from the device's public IP ─────────────
  // Uses ipapi.co — free, HTTPS, no key needed, 1000 req/day limit
  static Future<({String location, String isp})> getLocationAndIsp() async {
    try {
      final resp = await http
          .get(Uri.parse('https://ipapi.co/json/'))
          .timeout(const Duration(seconds: 8));
      if (resp.statusCode == 200) {
        final data     = json.decode(resp.body) as Map<String, dynamic>;
        final city     = data['city']         as String? ?? '';
        final country  = data['country_code'] as String? ?? '';
        final org      = data['org']          as String? ?? '';
        // "org" comes as "AS12345 Free SAS" — strip the AS number
        final isp      = org.replaceAll(RegExp(r'^AS\d+\s*'), '');
        final location = [city, country].where((s) => s.isNotEmpty).join(', ');
        return (location: location, isp: isp);
      }
    } catch (_) {
      // If request fails, just return empty strings — caller handles it
    }
    return (location: '', isp: '');
  }

  // ── Single ping — returns ms, or 999 if it fails ─────────────────────────
  Future<int> testPing(int serverIndex) async {
    final resolvedIndex = resolveServerIndex(serverIndex);
    final server = servers[resolvedIndex];
    final client = http.Client();
    final sw = Stopwatch()..start();
    try {
      final request = http.Request('GET', Uri.parse(server.pingUrl));
      // On web we skip Range header to avoid CORS preflight issues
      if (!kIsWeb) request.headers['Range'] = 'bytes=0-0';
      final response = await client.send(request).timeout(_connectTimeout);
      sw.stop();
      await response.stream.drain<void>();
      if (response.statusCode == 200 || response.statusCode == 206) {
        return sw.elapsedMilliseconds;
      }
      return 999;
    } on TimeoutException {
      sw.stop();
      return 999;
    } catch (_) {
      sw.stop();
      return 999;
    } finally {
      client.close();
    }
  }

  // ── Ping 5 times and compute average + jitter ─────────────────────────────
  // Jitter = standard deviation of the ping samples (how much ping varies)
  // This is what gives the app its name!
  Future<({int ping, int jitter})> testPingWithJitter(int serverIndex) async {
    const count  = 5;
    final pings  = <int>[];

    for (int i = 0; i < count; i++) {
      pings.add(await testPing(serverIndex));
      // Small gap between pings
      if (i < count - 1) {
        await Future.delayed(const Duration(milliseconds: 250));
      }
    }

    // Remove failed pings before calculating
    final valid = pings.where((p) => p < 999).toList();
    if (valid.isEmpty) return (ping: 999, jitter: 0);

    final avg      = valid.reduce((a, b) => a + b) / valid.length;
    final variance = valid
        .map((p) => (p - avg) * (p - avg))
        .reduce((a, b) => a + b) / valid.length;

    return (
      ping:   avg.round(),
      jitter: sqrt(variance).round(),
    );
  }

  // ── Download — runs for durationSecs seconds then stops ───────────────────
  Stream<double> testDownloadSpeed({
    required int serverIndex,
    required int durationSecs,
  }) {
    final resolvedIndex = resolveServerIndex(serverIndex);
    final controller    = StreamController<double>();
    _downloadInternal(
      serverIndex:  resolvedIndex,
      durationSecs: durationSecs,
      controller:   controller,
    );
    return controller.stream;
  }

  Future<void> _downloadInternal({
    required int serverIndex,
    required int durationSecs,
    required StreamController<double> controller,
  }) async {
    final server   = servers[serverIndex];
    final client   = http.Client();
    final sw       = Stopwatch()..start();
    Timer? watchdog;
    final maxMs    = durationSecs * 1000;   // stop after this many ms
    const maxBytes = 2 * 1024 * 1024 * 1024; // 2 GB safety cap

    // Watchdog resets each time we receive data; fires if network goes silent
    void resetWatchdog() {
      watchdog?.cancel();
      watchdog = Timer(const Duration(seconds: 10), () {
        if (!controller.isClosed) {
          controller.addError(
            TimeoutException('No data received for 10s — check network'),
          );
          controller.close();
          client.close();
        }
      });
    }

    try {
      final request  = http.Request('GET', Uri.parse(server.downloadUrl));
      final response = await client.send(request).timeout(_connectTimeout);

      if (response.statusCode >= 400) {
        throw Exception('Server ${server.name}: HTTP ${response.statusCode}');
      }

      int received = 0;
      resetWatchdog();

      await for (final chunk in response.stream.timeout(
        _streamTimeout,
        onTimeout: (sink) {
          sink.addError(TimeoutException('Stream timeout ($_streamTimeout)'));
          sink.close();
        },
      )) {
        resetWatchdog();
        received += chunk.length;

        // Emit speed reading after 0.5s warmup
        final secs = sw.elapsedMilliseconds / 1000.0;
        if (secs > 0.5) {
          controller.add((received * 8) / secs / (1024 * 1024));
        }

        // Stop when the configured time is up or safety cap reached
        if (sw.elapsedMilliseconds >= maxMs || received >= maxBytes) break;
      }

      watchdog?.cancel();
      if (!controller.isClosed) controller.close();
    } on TimeoutException catch (e) {
      watchdog?.cancel();
      if (!controller.isClosed) {
        controller.addError(e);
        controller.close();
      }
    } catch (e) {
      watchdog?.cancel();
      if (!controller.isClosed) {
        controller.addError(e);
        controller.close();
      }
    } finally {
      client.close();
    }
  }

  // ── Upload — tries each URL until one works ────────────────────────────────
  Future<double> testUploadSpeed({int sizeMB = 2}) async {
    final payload = List<int>.generate(sizeMB * 1024 * 1024, (i) => i & 0xFF);
    for (final url in _uploadUrls) {
      final result = await _tryUpload(url: url, payload: payload);
      if (result > 0) return result;
    }
    return 0.0;
  }

  Future<double> _tryUpload({
    required String url,
    required List<int> payload,
  }) async {
    final client = http.Client();
    try {
      final sw      = Stopwatch()..start();
      final request = http.MultipartRequest('POST', Uri.parse(url))
        ..files.add(http.MultipartFile.fromBytes(
          'file', payload,
          filename: 'upload.bin',
        ));
      final response = await client.send(request).timeout(_streamTimeout);
      sw.stop();
      await response.stream.drain<void>();
      if (response.statusCode == 200 || response.statusCode == 204) {
        final secs = sw.elapsedMilliseconds / 1000.0;
        if (secs > 0) return (payload.length * 8) / secs / (1024 * 1024);
      }
      return 0.0;
    } catch (_) {
      return 0.0;
    } finally {
      client.close();
    }
  }
}