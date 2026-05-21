import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

class SpeedServer {
  final String name;
  final String location;
  final String provider;
  final String flag;
  final String downloadUrl;
  /// true = fonctionne sur Flutter Web (header CORS présent)
  final bool corsCompatible;

  const SpeedServer({
    required this.name,
    required this.location,
    required this.provider,
    required this.flag,
    required this.downloadUrl,
    this.corsCompatible = false,
  });

  String get pingUrl => downloadUrl;
  String get displayLine => '$flag  $name — $provider';
  String get subtitle => location;
}

class InternetSpeedService {
  static const List<SpeedServer> servers = [
    // ── Serveurs CORS-compatibles (web + natif) ────────────────────────────
    // Cloudflare speed.cloudflare.com envoie Access-Control-Allow-Origin: *
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

    // ── Serveurs natifs uniquement (pas de CORS) ──────────────────────────
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

  /// Retourne uniquement les serveurs disponibles sur la plateforme courante.
  static List<SpeedServer> get availableServers =>
      kIsWeb ? servers.where((s) => s.corsCompatible).toList() : servers;

  /// Vérifie si le serveur sélectionné est compatible avec la plateforme.
  /// Retourne l'index corrigé si nécessaire.
  static int resolveServerIndex(int index) {
    if (!kIsWeb) return index.clamp(0, servers.length - 1);
    final available = availableServers;
    if (available.isEmpty) return 0;
    // Sur web, on ne peut utiliser que les serveurs CORS-compatibles
    final server = servers[index.clamp(0, servers.length - 1)];
    if (server.corsCompatible) return index;
    // Fallback vers le premier serveur CORS-compatible
    return servers.indexOf(available.first);
  }

  static const List<String> _uploadUrls = [
    // Cloudflare upload endpoint — CORS-compatible
    'https://speed.cloudflare.com/__up',
    'https://httpbin.org/post',
    'https://postman-echo.com/post',
  ];

  static const Duration _connectTimeout = Duration(seconds: 10);
  static const Duration _streamTimeout  = Duration(seconds: 45);

  // ── Ping ──────────────────────────────────────────────────────────────────
  Future<int> testPing(int serverIndex) async {
    final resolvedIndex = resolveServerIndex(serverIndex);
    final server = servers[resolvedIndex];
    final client = http.Client();
    final sw = Stopwatch()..start();
    try {
      final request = http.Request('GET', Uri.parse(server.pingUrl));
      // Sur web : pas de Range header (peut causer des CORS preflight)
      if (!kIsWeb) request.headers['Range'] = 'bytes=0-0';
      final response =
          await client.send(request).timeout(_connectTimeout);
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

  // ── Download ──────────────────────────────────────────────────────────────
  Stream<double> testDownloadSpeed({
    required int serverIndex,
    required int maxMB,
  }) {
    final resolvedIndex = resolveServerIndex(serverIndex);
    final controller = StreamController<double>();
    _downloadInternal(
      serverIndex: resolvedIndex,
      maxMB: maxMB,
      controller: controller,
    );
    return controller.stream;
  }

  Future<void> _downloadInternal({
    required int serverIndex,
    required int maxMB,
    required StreamController<double> controller,
  }) async {
    final server = servers[serverIndex];
    final client = http.Client();
    final sw = Stopwatch()..start();
    Timer? watchdog;

    void resetWatchdog() {
      watchdog?.cancel();
      watchdog = Timer(const Duration(seconds: 10), () {
        if (!controller.isClosed) {
          controller.addError(
            TimeoutException(
                'Aucune donnée reçue depuis 10 s — vérifiez le réseau'),
          );
          controller.close();
          client.close();
        }
      });
    }

    try {
      final request = http.Request('GET', Uri.parse(server.downloadUrl));
      final response =
          await client.send(request).timeout(_connectTimeout);

      if (response.statusCode >= 400) {
        throw Exception(
            'Serveur ${server.name} : HTTP ${response.statusCode}');
      }

      int received = 0;
      final maxBytes = maxMB * 1024 * 1024;
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
        final secs = sw.elapsedMilliseconds / 1000.0;
        if (secs > 0.5) {
          controller.add((received * 8) / secs / (1024 * 1024));
        }
        if (received >= maxBytes) break;
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

  // ── Upload ────────────────────────────────────────────────────────────────
  Future<double> testUploadSpeed({int sizeMB = 2}) async {
    final payload =
        List<int>.generate(sizeMB * 1024 * 1024, (i) => i & 0xFF);
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
      final sw = Stopwatch()..start();
      final request = http.MultipartRequest('POST', Uri.parse(url))
        ..files.add(http.MultipartFile.fromBytes(
          'file', payload,
          filename: 'upload.bin',
        ));
      final response =
          await client.send(request).timeout(_streamTimeout);
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
