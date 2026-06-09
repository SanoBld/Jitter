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
  final bool   corsCompatible;
  /// Minimum parallel connections recommended to saturate this server.
  final int    minConnections;
  /// Human-readable file size note shown in the server picker.
  final String fileSize;

  const SpeedServer({
    required this.name,
    required this.location,
    required this.provider,
    required this.flag,
    required this.downloadUrl,
    this.corsCompatible  = false,
    this.minConnections  = 4,
    this.fileSize        = '100 MB',
  });

  String get pingUrl     => downloadUrl;
  String get displayLine => '$flag  $name — $provider';
  String get subtitle    => location;
}

class InternetSpeedService {
  static const List<SpeedServer> servers = [

    // ── CORS-compatible — work in browser AND native ───────────────────────
    SpeedServer(
      name:            'Cloudflare 1 GB',
      location:        'Anycast, Global',
      provider:        'Cloudflare',
      flag:            '🌐',
      downloadUrl:     'https://speed.cloudflare.com/__down?bytes=1073741824',
      corsCompatible:  true,
      minConnections:  8,
      fileSize:        '1 GB',
    ),
    SpeedServer(
      name:            'Cloudflare 100 MB',
      location:        'Anycast, Global',
      provider:        'Cloudflare',
      flag:            '🌐',
      downloadUrl:     'https://speed.cloudflare.com/__down?bytes=104857600',
      corsCompatible:  true,
      minConnections:  4,
      fileSize:        '100 MB',
    ),

    // ── OVH — excellent for French users (Mulhouse is near Strasbourg) ────
    SpeedServer(
      name:           'Strasbourg 10 GB',
      location:       'Strasbourg, FR',
      provider:       'OVH',
      flag:           '🇫🇷',
      downloadUrl:    'https://proof.ovh.net/files/10Gb.dat',
      minConnections: 16,
      fileSize:       '10 GB ⚡ recommended for Gbps fiber',
    ),
    SpeedServer(
      name:           'Strasbourg 1 GB',
      location:       'Strasbourg, FR',
      provider:       'OVH',
      flag:           '🇫🇷',
      downloadUrl:    'https://proof.ovh.net/files/1Gb.dat',
      minConnections: 8,
      fileSize:       '1 GB',
    ),
    SpeedServer(
      name:           'Paris 100 MB',
      location:       'Paris, FR',
      provider:       'OVH',
      flag:           '🇫🇷',
      downloadUrl:    'https://proof.ovh.net/files/100Mb.dat',
      minConnections: 4,
      fileSize:       '100 MB',
    ),

    // ── Hetzner — fast European servers with 1 GB and 10 GB files ─────────
    SpeedServer(
      name:           'Falkenstein 10 GB',
      location:       'Falkenstein, DE',
      provider:       'Hetzner',
      flag:           '🇩🇪',
      downloadUrl:    'https://fsn1-speed.hetzner.com/10GB.bin',
      minConnections: 16,
      fileSize:       '10 GB ⚡',
    ),
    SpeedServer(
      name:           'Falkenstein 1 GB',
      location:       'Falkenstein, DE',
      provider:       'Hetzner',
      flag:           '🇩🇪',
      downloadUrl:    'https://fsn1-speed.hetzner.com/1GB.bin',
      minConnections: 8,
      fileSize:       '1 GB',
    ),
    SpeedServer(
      name:           'Falkenstein 100 MB',
      location:       'Falkenstein, DE',
      provider:       'Hetzner',
      flag:           '🇩🇪',
      downloadUrl:    'https://fsn1-speed.hetzner.com/100MB.bin',
      minConnections: 4,
      fileSize:       '100 MB',
    ),
    SpeedServer(
      name:           'Nuremberg 10 GB',
      location:       'Nuremberg, DE',
      provider:       'Hetzner',
      flag:           '🇩🇪',
      downloadUrl:    'https://nbg1-speed.hetzner.com/10GB.bin',
      minConnections: 16,
      fileSize:       '10 GB ⚡',
    ),
    SpeedServer(
      name:           'Nuremberg 1 GB',
      location:       'Nuremberg, DE',
      provider:       'Hetzner',
      flag:           '🇩🇪',
      downloadUrl:    'https://nbg1-speed.hetzner.com/1GB.bin',
      minConnections: 8,
      fileSize:       '1 GB',
    ),
    SpeedServer(
      name:           'Helsinki 1 GB',
      location:       'Helsinki, FI',
      provider:       'Hetzner',
      flag:           '🇫🇮',
      downloadUrl:    'https://hel1-speed.hetzner.com/1GB.bin',
      minConnections: 8,
      fileSize:       '1 GB',
    ),
    SpeedServer(
      name:           'Paris',
      location:       'Paris, FR',
      provider:       'Hetzner',
      flag:           '🇫🇷',
      downloadUrl:    'https://speed.hetzner.de/100MB.bin',
      minConnections: 4,
      fileSize:       '100 MB',
    ),
    SpeedServer(
      name:           'Ashburn 1 GB',
      location:       'Ashburn, US',
      provider:       'Hetzner',
      flag:           '🇺🇸',
      downloadUrl:    'https://ash-speed.hetzner.com/1GB.bin',
      minConnections: 8,
      fileSize:       '1 GB',
    ),

    // ── Leaseweb ──────────────────────────────────────────────────────────
    SpeedServer(
      name:           'Amsterdam',
      location:       'Amsterdam, NL',
      provider:       'Leaseweb',
      flag:           '🇳🇱',
      downloadUrl:    'https://mirror.nl.leaseweb.net/speedtest/1000mb.bin',
      minConnections: 8,
      fileSize:       '1 GB',
    ),
    SpeedServer(
      name:           'Frankfurt',
      location:       'Frankfurt, DE',
      provider:       'Leaseweb',
      flag:           '🇩🇪',
      downloadUrl:    'https://mirror.de.leaseweb.net/speedtest/1000mb.bin',
      minConnections: 8,
      fileSize:       '1 GB',
    ),
    SpeedServer(
      name:           'Ashburn',
      location:       'Ashburn, US',
      provider:       'Leaseweb',
      flag:           '🇺🇸',
      downloadUrl:    'https://mirror.us.leaseweb.net/speedtest/100mb.bin',
      minConnections: 4,
      fileSize:       '100 MB',
    ),
    SpeedServer(
      name:           'Singapore',
      location:       'Singapore, SG',
      provider:       'Leaseweb',
      flag:           '🇸🇬',
      downloadUrl:    'https://mirror.sg.leaseweb.net/speedtest/100mb.bin',
      minConnections: 4,
      fileSize:       '100 MB',
    ),

    // ── Clouvider ─────────────────────────────────────────────────────────
    SpeedServer(
      name:           'London',
      location:       'London, UK',
      provider:       'Clouvider',
      flag:           '🇬🇧',
      downloadUrl:    'https://lon.speedtest.clouvider.net/1000MB.test',
      minConnections: 8,
      fileSize:       '1 GB',
    ),
    SpeedServer(
      name:           'Frankfurt',
      location:       'Frankfurt, DE',
      provider:       'Clouvider',
      flag:           '🇩🇪',
      downloadUrl:    'https://fra.speedtest.clouvider.net/1000MB.test',
      minConnections: 8,
      fileSize:       '1 GB',
    ),
    SpeedServer(
      name:           'Amsterdam',
      location:       'Amsterdam, NL',
      provider:       'Clouvider',
      flag:           '🇳🇱',
      downloadUrl:    'https://ams.speedtest.clouvider.net/1000MB.test',
      minConnections: 8,
      fileSize:       '1 GB',
    ),
    SpeedServer(
      name:           'New York',
      location:       'New York, US',
      provider:       'Clouvider',
      flag:           '🇺🇸',
      downloadUrl:    'https://nyc.speedtest.clouvider.net/100MB.test',
      minConnections: 4,
      fileSize:       '100 MB',
    ),
    SpeedServer(
      name:           'Los Angeles',
      location:       'Los Angeles, US',
      provider:       'Clouvider',
      flag:           '🇺🇸',
      downloadUrl:    'https://la.speedtest.clouvider.net/100MB.test',
      minConnections: 4,
      fileSize:       '100 MB',
    ),
  ];

  static List<SpeedServer> get availableServers =>
      kIsWeb ? servers.where((s) => s.corsCompatible).toList() : servers;

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

  // ── IP-based location + ISP ────────────────────────────────────────────────
  static Future<({String location, String isp})> getLocationAndIsp() async {
    try {
      final resp = await http
          .get(Uri.parse('https://ip-api.com/json/?fields=status,city,countryCode,isp'))
          .timeout(const Duration(seconds: 8));
      if (resp.statusCode == 200) {
        final data = json.decode(resp.body) as Map<String, dynamic>;
        if (data['status'] == 'success') {
          final city    = data['city']        as String? ?? '';
          final country = data['countryCode'] as String? ?? '';
          final isp     = data['isp']         as String? ?? '';
          final loc     = [city, country].where((s) => s.isNotEmpty).join(', ');
          if (loc.isNotEmpty) return (location: loc, isp: isp);
        }
      }
    } catch (_) {}
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
        final loc     = [city, country].where((s) => s.isNotEmpty).join(', ');
        if (loc.isNotEmpty) return (location: loc, isp: isp);
      }
    } catch (_) {}
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
        final loc     = [city, country].where((s) => s.isNotEmpty).join(', ');
        return (location: loc, isp: isp);
      }
    } catch (_) {}
    return (location: '', isp: '');
  }

  // ── Quick reachability ─────────────────────────────────────────────────────
  Future<bool> quickReachable(int serverIndex) async {
    final idx    = resolveServerIndex(serverIndex);
    final server = servers[idx];
    final client = http.Client();
    try {
      final req = http.Request('GET', Uri.parse(server.pingUrl));
      if (!kIsWeb) req.headers['Range'] = 'bytes=0-0';
      final resp = await client.send(req).timeout(const Duration(seconds: 3));
      await resp.stream.drain<void>();
      return resp.statusCode == 200 || resp.statusCode == 206;
    } catch (_) {
      return false;
    } finally {
      client.close();
    }
  }

  // ── Single ping ────────────────────────────────────────────────────────────
  Future<int> testPing(int serverIndex) async {
    final idx    = resolveServerIndex(serverIndex);
    final server = servers[idx];
    final client = http.Client();
    final sw     = Stopwatch()..start();
    try {
      final req = http.Request('GET', Uri.parse(server.pingUrl));
      if (!kIsWeb) req.headers['Range'] = 'bytes=0-0';
      final resp = await client.send(req).timeout(_connectTimeout);
      sw.stop();
      await resp.stream.drain<void>();
      return (resp.statusCode == 200 || resp.statusCode == 206)
          ? sw.elapsedMilliseconds
          : 999;
    } catch (_) {
      sw.stop();
      return 999;
    } finally {
      client.close();
    }
  }

  // ── 5-ping burst ──────────────────────────────────────────────────────────
  Future<({int ping, int jitter})> testPingWithJitter(int serverIndex) async {
    const count = 5;
    final pings = <int>[];
    for (int i = 0; i < count; i++) {
      pings.add(await testPing(serverIndex));
      if (i < count - 1) await Future.delayed(const Duration(milliseconds: 200));
    }
    final valid = pings.where((p) => p < 999).toList();
    if (valid.isEmpty) return (ping: 999, jitter: 0);
    final avg      = valid.reduce((a, b) => a + b) / valid.length;
    final variance = valid
            .map((p) => (p - avg) * (p - avg))
            .reduce((a, b) => a + b) /
        valid.length;
    return (ping: avg.round(), jitter: sqrt(variance).round());
  }

  // ── Download — PARALLEL connections ───────────────────────────────────────
  //
  // Why parallel?
  //   A single TCP stream is limited to ~100–200 Mb/s by congestion-window
  //   dynamics and RTT. To saturate a 1 Gbps+ link you need multiple
  //   simultaneous HTTP connections that together fill the pipe.
  //
  //   Rule of thumb:
  //     100 Mb/s  → 1–2 connections
  //     500 Mb/s  → 4 connections
  //     1 Gbps    → 8 connections
  //     2.5 Gbps+ → 16 connections
  //     9 Gbps    → 16+ connections + a 10 GB file (OVH Strasbourg or Hetzner)
  //
  // Each connection loops the download so it never stalls while the timer runs.
  // Speeds from all connections are summed every 250 ms to produce one Mb/s value.
  Stream<double> testDownloadSpeed({
    required int serverIndex,
    required int durationSecs,
    int parallelConnections = 4,
  }) {
    final resolved   = resolveServerIndex(serverIndex);
    final controller = StreamController<double>();
    _parallelDownload(
      serverIndex:  resolved,
      durationSecs: durationSecs == 0 ? 600 : durationSecs,
      connections:  parallelConnections.clamp(1, 32),
      controller:   controller,
    );
    return controller.stream;
  }

  Future<void> _parallelDownload({
    required int serverIndex,
    required int durationSecs,
    required int connections,
    required StreamController<double> controller,
  }) async {
    final server  = servers[serverIndex];
    final maxMs   = durationSecs * 1000;
    final sw      = Stopwatch()..start();
    final bytes   = List<int>.filled(connections, 0);
    bool  stopped = false;

    // Emit aggregated speed every 250 ms
    final ticker = Timer.periodic(const Duration(milliseconds: 250), (_) {
      final secs = sw.elapsedMilliseconds / 1000.0;
      if (secs > 0.4 && !controller.isClosed) {
        final total = bytes.fold(0, (a, b) => a + b);
        controller.add((total * 8) / secs / 1048576.0);
      }
      if (sw.elapsedMilliseconds >= maxMs) stopped = true;
    });

    // N parallel streaming connections, each loops if file ends before timer
    await Future.wait(
      List.generate(connections, (i) => _singleDownloadLoop(
        url:     server.downloadUrl,
        bytes:   bytes,
        index:   i,
        maxMs:   maxMs,
        sw:      sw,
        stopped: () => stopped,
      )),
    );

    ticker.cancel();
    if (!controller.isClosed) controller.close();
  }

  Future<void> _singleDownloadLoop({
    required String      url,
    required List<int>   bytes,
    required int         index,
    required int         maxMs,
    required Stopwatch   sw,
    required bool Function() stopped,
  }) async {
    final client = http.Client();
    try {
      // Loop: when the file completes before the timer, restart immediately.
      while (!stopped() && sw.elapsedMilliseconds < maxMs) {
        try {
          final req  = http.Request('GET', Uri.parse(url));
          final resp = await client.send(req).timeout(_connectTimeout);
          if (resp.statusCode >= 400) break;

          await for (final chunk in resp.stream.timeout(_streamTimeout,
              onTimeout: (s) { s.addError(TimeoutException('stream')); s.close(); })) {
            bytes[index] += chunk.length;
            if (stopped() || sw.elapsedMilliseconds >= maxMs) break;
          }
        } catch (_) {
          // Transient error — wait briefly then retry
          await Future.delayed(const Duration(milliseconds: 200));
        }
      }
    } finally {
      client.close();
    }
  }

  // ── Upload — PARALLEL connections ─────────────────────────────────────────
  Stream<double> testUploadSpeed({
    required int durationSecs,
    int parallelConnections = 4,
  }) {
    final controller = StreamController<double>();
    _parallelUpload(
      durationSecs: durationSecs == 0 ? 600 : durationSecs,
      connections:  parallelConnections.clamp(1, 32),
      controller:   controller,
    );
    return controller.stream;
  }

  Future<void> _parallelUpload({
    required int durationSecs,
    required int connections,
    required StreamController<double> controller,
  }) async {
    const uploadUrl  = 'https://speed.cloudflare.com/__up';
    final maxMs      = durationSecs * 1000;
    final sw         = Stopwatch()..start();
    final bytesSent  = List<int>.filled(connections, 0);
    bool  stopped    = false;

    final ticker = Timer.periodic(const Duration(milliseconds: 250), (_) {
      final secs = sw.elapsedMilliseconds / 1000.0;
      if (secs > 0.4 && !controller.isClosed) {
        final total = bytesSent.fold(0, (a, b) => a + b);
        controller.add((total * 8) / secs / 1048576.0);
      }
      if (sw.elapsedMilliseconds >= maxMs) stopped = true;
    });

    await Future.wait(
      List.generate(connections, (i) => _singleUploadLoop(
        url:       uploadUrl,
        bytesSent: bytesSent,
        index:     i,
        maxMs:     maxMs,
        sw:        sw,
        stopped:   () => stopped,
      )),
    );

    ticker.cancel();
    if (!controller.isClosed) controller.close();
  }

  Future<void> _singleUploadLoop({
    required String      url,
    required List<int>   bytesSent,
    required int         index,
    required int         maxMs,
    required Stopwatch   sw,
    required bool Function() stopped,
  }) async {
    // Each connection adapts its payload to fill ~1.5 s per round
    int payloadSize = 2 * 1024 * 1024; // start at 2 MB

    while (!stopped() && sw.elapsedMilliseconds < maxMs) {
      if (maxMs - sw.elapsedMilliseconds < 200) break;
      final payload = List<int>.generate(payloadSize, (j) => j & 0xFF);
      final t0      = sw.elapsedMilliseconds;
      try {
        final resp = await http
            .post(Uri.parse(url),
                body:    payload,
                headers: {'Content-Type': 'application/octet-stream'})
            .timeout(_streamTimeout);
        final elapsed = sw.elapsedMilliseconds - t0;
        if (resp.statusCode != 200 && resp.statusCode != 204) break;
        bytesSent[index] += payloadSize;
        if (elapsed > 0) {
          payloadSize = ((payloadSize / elapsed) * 1500)
              .round()
              .clamp(512 * 1024, 64 * 1024 * 1024);
        }
      } catch (_) {
        await Future.delayed(const Duration(milliseconds: 200));
      }
    }
  }
}