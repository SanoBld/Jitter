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

  String get pingUrl     => downloadUrl;
  String get displayLine => '$flag  $name — $provider';
  String get subtitle    => location;
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

  static const Duration _connectTimeout = Duration(seconds: 10);
  static const Duration _streamTimeout  = Duration(seconds: 90);

  // ── Auto-detect location and ISP from the device's public IP ──────────────
  // Tries three providers in order; returns the first successful result.
  static Future<({String location, String isp})> getLocationAndIsp() async {
    // 1. ip-api.com — most reliable free option (45 req/min, no key)
    try {
      final resp = await http
          .get(Uri.parse(
              'https://ip-api.com/json/?fields=status,city,countryCode,isp'))
          .timeout(const Duration(seconds: 8));
      if (resp.statusCode == 200) {
        final data = json.decode(resp.body) as Map<String, dynamic>;
        if (data['status'] == 'success') {
          final city    = data['city']        as String? ?? '';
          final country = data['countryCode'] as String? ?? '';
          final isp     = data['isp']         as String? ?? '';
          final loc = [city, country].where((s) => s.isNotEmpty).join(', ');
          if (loc.isNotEmpty) return (location: loc, isp: isp);
        }
      }
    } catch (_) {}

    // 2. ipapi.co — fallback (1000 req/day, no key)
    try {
      final resp = await http
          .get(Uri.parse('https://ipapi.co/json/'))
          .timeout(const Duration(seconds: 8));
      if (resp.statusCode == 200) {
        final data    = json.decode(resp.body) as Map<String, dynamic>;
        final city    = data['city']         as String? ?? '';
        final country = data['country_code'] as String? ?? '';
        final org     = data['org']          as String? ?? '';
        final isp     = org.replaceAll(RegExp(r'^AS\d+\s*'), '');
        final loc = [city, country].where((s) => s.isNotEmpty).join(', ');
        if (loc.isNotEmpty) return (location: loc, isp: isp);
      }
    } catch (_) {}

    // 3. ipinfo.io — last resort (50k req/month, no key)
    try {
      final resp = await http
          .get(Uri.parse('https://ipinfo.io/json'))
          .timeout(const Duration(seconds: 8));
      if (resp.statusCode == 200) {
        final data    = json.decode(resp.body) as Map<String, dynamic>;
        final city    = data['city']    as String? ?? '';
        final country = data['country'] as String? ?? '';
        final org     = data['org']     as String? ?? '';
        final isp     = org.replaceAll(RegExp(r'^AS\d+\s*'), '');
        final loc = [city, country].where((s) => s.isNotEmpty).join(', ');
        return (location: loc, isp: isp);
      }
    } catch (_) {}

    return (location: '', isp: '');
  }

  // ── Single ping — returns ms, or 999 if it fails ──────────────────────────
  Future<int> testPing(int serverIndex) async {
    final resolvedIndex = resolveServerIndex(serverIndex);
    final server = servers[resolvedIndex];
    final client = http.Client();
    final sw = Stopwatch()..start();
    try {
      final request = http.Request('GET', Uri.parse(server.pingUrl));
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

  // ── Ping 5 times — returns average ping + jitter (std dev) ────────────────
  Future<({int ping, int jitter})> testPingWithJitter(int serverIndex) async {
    const count = 5;
    final pings = <int>[];

    for (int i = 0; i < count; i++) {
      pings.add(await testPing(serverIndex));
      if (i < count - 1) {
        await Future.delayed(const Duration(milliseconds: 250));
      }
    }

    final valid = pings.where((p) => p < 999).toList();
    if (valid.isEmpty) return (ping: 999, jitter: 0);

    final avg      = valid.reduce((a, b) => a + b) / valid.length;
    final variance = valid
            .map((p) => (p - avg) * (p - avg))
            .reduce((a, b) => a + b) /
        valid.length;

    return (
      ping:   avg.round(),
      jitter: sqrt(variance).round(),
    );
  }

  // ── Download — streams speed readings for durationSecs seconds ────────────
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
    final maxMs    = durationSecs * 1000;
    const maxBytes = 2 * 1024 * 1024 * 1024; // 2 GB safety cap

    void resetWatchdog() {
      watchdog?.cancel();
      watchdog = Timer(const Duration(seconds: 10), () {
        if (!controller.isClosed) {
          controller.addError(
            TimeoutException('No data received for 10 s — check network'),
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

        // Emit speed after 0.5 s warmup
        final secs = sw.elapsedMilliseconds / 1000.0;
        if (secs > 0.5) {
          controller.add((received * 8) / secs / (1024 * 1024));
        }

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

  // ── Upload — streams speed readings for durationSecs seconds ──────────────
  // Uses Cloudflare's __up endpoint with adaptive payload sizing.
  // Emits the cumulative average upload speed (Mb/s) after each request.
  Stream<double> testUploadSpeed({required int durationSecs}) async* {
    const uploadUrl = 'https://speed.cloudflare.com/__up';
    final sw  = Stopwatch()..start();
    final maxMs = durationSecs * 1000;
    int totalSent   = 0;
    int payloadSize = 1 * 1024 * 1024; // start with 1 MB, adapt over time

    while (sw.elapsedMilliseconds < maxMs) {
      if (maxMs - sw.elapsedMilliseconds < 200) break;

      final payload = List<int>.generate(payloadSize, (i) => i & 0xFF);
      final t0 = sw.elapsedMilliseconds;

      try {
        final resp = await http
            .post(
              Uri.parse(uploadUrl),
              body: payload,
              headers: {'Content-Type': 'application/octet-stream'},
            )
            .timeout(_streamTimeout);

        final elapsed = sw.elapsedMilliseconds - t0;
        if (elapsed <= 0) break;
        if (resp.statusCode != 200 && resp.statusCode != 204) break;

        totalSent += payloadSize;
        final totalSecs = sw.elapsedMilliseconds / 1000.0;
        if (totalSecs > 0.3) {
          yield (totalSent * 8) / totalSecs / (1024 * 1024);
        }

        // Adapt payload size to target ~1.5 s per request
        final bytesPerMs = payloadSize / elapsed;
        payloadSize = (bytesPerMs * 1500)
            .round()
            .clamp(256 * 1024, 32 * 1024 * 1024);
      } catch (_) {
        break;
      }
    }
  }
}