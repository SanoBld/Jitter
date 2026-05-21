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

  // ── Upload: serveurs alternatifs plus fiables que httpbin ─────────────────
  // httpbin.org est souvent lent ou down. On essaie plusieurs endpoints.
  static const List<String> _uploadUrls = [
    'https://www.cloudflare.com/cdn-cgi/trace', // léger, juste pour mesure
    'https://httpbin.org/post',
    'https://postman-echo.com/post',
  ];

  static const Duration _connectTimeout = Duration(seconds: 10);
  // FIX: timeout global couvrant AUSSI la lecture du stream
  static const Duration _streamTimeout  = Duration(seconds: 45);

  // ── Ping ──────────────────────────────────────────────────────────────────
  // GET avec Range: bytes=0-0 → on ne télécharge qu'1 octet.
  // Évite les 405 des CDN qui rejettent HEAD.
  Future<int> testPing(int serverIndex) async {
    final server = _server(serverIndex);
    final client = http.Client();
    final sw = Stopwatch()..start();
    try {
      final request = http.Request('GET', Uri.parse(server.pingUrl));
      request.headers['Range'] = 'bytes=0-0';
      final response = await client
          .send(request)
          .timeout(_connectTimeout);
      sw.stop();
      await response.stream.drain<void>(); // libère proprement la connexion
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
  // FIX principal : le timeout couvre maintenant TOUTE la durée du stream
  // via un StreamController avec timer de garde, et non plus juste le
  // client.send() initial (qui réussissait même sur APK sans permission).
  Stream<double> testDownloadSpeed({
    required int serverIndex,
    required int maxMB,
  }) {
    final controller = StreamController<double>();
    _downloadInternal(
      serverIndex: serverIndex,
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
    final server = _server(serverIndex);
    final client = http.Client();
    final sw = Stopwatch()..start();

    // Watchdog : si aucun chunk n'arrive pendant 10 s → erreur réseau
    Timer? watchdog;

    void resetWatchdog() {
      watchdog?.cancel();
      watchdog = Timer(const Duration(seconds: 10), () {
        if (!controller.isClosed) {
          controller.addError(
            TimeoutException('No data received for 10 seconds — check network'),
          );
          controller.close();
          client.close();
        }
      });
    }

    try {
      final request = http.Request('GET', Uri.parse(server.downloadUrl));
      // FIX: timeout uniquement sur la connexion initiale
      final response = await client.send(request).timeout(_connectTimeout);

      if (response.statusCode >= 400) {
        throw Exception(
          'Server ${server.name} returned HTTP ${response.statusCode}',
        );
      }

      int received = 0;
      final maxBytes = maxMB * 1024 * 1024;

      resetWatchdog();

      await for (final chunk in response.stream
          .timeout(_streamTimeout, onTimeout: (sink) {
        sink.addError(TimeoutException('Stream global timeout ($_streamTimeout)'));
        sink.close();
      })) {
        resetWatchdog();
        received += chunk.length;
        final secs = sw.elapsedMilliseconds / 1000.0;

        // Ignore les 0.5 premières secondes (warmup TCP)
        if (secs > 0.5) {
          // octets → bits → mégabits/seconde
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
  // FIX: essaie plusieurs endpoints upload, retourne la première réponse
  // valide. Taille réduite à 2 MB par défaut (plus rapide, assez précis).
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
        ..files.add(
          http.MultipartFile.fromBytes(
            'file',
            payload,
            filename: 'upload.bin',
          ),
        );
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

  SpeedServer _server(int index) =>
      servers[index.clamp(0, servers.length - 1)];
}
