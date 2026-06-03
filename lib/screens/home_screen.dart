import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../app_state.dart';
import '../services/internet_speed_service.dart';
import '../services/location_service.dart';
import 'settings_screen.dart';

// ── Performance grade based on download speed ──────────────────────────────
enum _Grade { excellent, veryGood, good, fair, slow, poor }

extension _GradeX on _Grade {
  String get label {
    switch (this) {
      case _Grade.excellent: return 'EXCELLENT';
      case _Grade.veryGood:  return 'VERY GOOD';
      case _Grade.good:      return 'GOOD';
      case _Grade.fair:      return 'FAIR';
      case _Grade.slow:      return 'SLOW';
      case _Grade.poor:      return 'VERY SLOW';
    }
  }
  Color get color {
    switch (this) {
      case _Grade.excellent: return const Color(0xFF1B5E20);
      case _Grade.veryGood:  return const Color(0xFF2E7D32);
      case _Grade.good:      return const Color(0xFF1565C0);
      case _Grade.fair:      return const Color(0xFFE65100);
      case _Grade.slow:      return const Color(0xFFBF360C);
      case _Grade.poor:      return const Color(0xFFC62828);
    }
  }
  IconData get icon {
    switch (this) {
      case _Grade.excellent: return Icons.rocket_launch_rounded;
      case _Grade.veryGood:  return Icons.speed_rounded;
      case _Grade.good:      return Icons.check_circle_outline_rounded;
      case _Grade.fair:      return Icons.remove_circle_outline_rounded;
      case _Grade.slow:      return Icons.hourglass_bottom_rounded;
      case _Grade.poor:      return Icons.signal_cellular_off_rounded;
    }
  }
}

_Grade _gradeFor(double mbps) {
  if (mbps >= 500) return _Grade.excellent;
  if (mbps >= 200) return _Grade.veryGood;
  if (mbps >= 100) return _Grade.good;
  if (mbps >= 30)  return _Grade.fair;
  if (mbps >= 10)  return _Grade.slow;
  return _Grade.poor;
}

Color _pingColor(int ms, BuildContext ctx) {
  if (ms == 0)   return Theme.of(ctx).colorScheme.onSurface.withValues(alpha: 0.25);
  if (ms <= 30)  return const Color(0xFF2E7D32);
  if (ms <= 80)  return const Color(0xFF1565C0);
  if (ms <= 150) return const Color(0xFFE65100);
  return Theme.of(ctx).colorScheme.error;
}

Color _jitterColor(int ms, BuildContext ctx) {
  if (ms == 0)  return Theme.of(ctx).colorScheme.onSurface.withValues(alpha: 0.25);
  if (ms <= 10) return const Color(0xFF2E7D32);
  if (ms <= 30) return const Color(0xFF1565C0);
  if (ms <= 60) return const Color(0xFFE65100);
  return Theme.of(ctx).colorScheme.error;
}

// ── History entry ──────────────────────────────────────────────────────────
class _Entry {
  final String timestamp, flag, server, provider, serverLoc, userLoc, unit;
  final double dl, ul;
  final int    ping, jitter;
  const _Entry({
    required this.timestamp, required this.flag,  required this.server,
    required this.provider,  required this.serverLoc, required this.userLoc,
    required this.dl,        required this.ul,    required this.ping,
    required this.jitter,    required this.unit,
  });
  Map<String, dynamic> toJson() => {
    'ts': timestamp, 'flag': flag, 'server': server,
    'provider': provider, 'location': serverLoc, 'userLocation': userLoc,
    'dl': dl, 'ul': ul, 'ping': ping, 'jitter': jitter, 'unit': unit,
  };
  factory _Entry.fromJson(Map<String, dynamic> j) => _Entry(
    timestamp: j['ts'] as String,
    flag:      j['flag'] as String,
    server:    j['server'] as String,
    provider:  j['provider'] as String? ?? '',
    serverLoc: j['location'] as String? ?? '',
    userLoc:   j['userLocation'] as String? ?? '',
    dl:        (j['dl'] as num).toDouble(),
    ul:        (j['ul'] as num).toDouble(),
    ping:      j['ping'] as int,
    jitter:    j['jitter'] as int? ?? 0,
    unit:      j['unit'] as String,
  );
}

// Duration steps in seconds; 0 = infinite
const _kSteps = [5, 10, 15, 30, 60, 0];

String _stepLabel(int s) {
  if (s == 0)  return '∞';
  if (s == 60) return '1 min';
  return '${s}s';
}

// Per-phase duration: half of total, min 3 s. 0 stays 0 (infinite).
int _phaseDur(int total) =>
    total == 0 ? 0 : max(total ~/ 2, 3);

// Elapsed / duration display  →  "00:08"
String _fmt(int secs) {
  final m = secs ~/ 60, s = secs % 60;
  return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}

// ══════════════════════════════════════════════════════════════════════════════
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {

  final _svc = InternetSpeedService();
  int _tab   = 0;

  // Live values
  final _speedNf    = ValueNotifier<double>(0);
  final _dlNf       = ValueNotifier<double>(0);
  final _ulNf       = ValueNotifier<double>(0);
  final _pingNf     = ValueNotifier<int>(0);
  final _jitterNf   = ValueNotifier<int>(0);
  final _testingNf  = ValueNotifier<bool>(false);
  final _phaseNf    = ValueNotifier<String>('READY');
  final _progressNf = ValueNotifier<double>(0);   // 0–1 overall
  final _dlProgNf   = ValueNotifier<double>(0);   // 0–1 within DL phase
  final _ulProgNf   = ValueNotifier<double>(0);   // 0–1 within UL phase
  final _pointsNf   = ValueNotifier<List<double>>([]);
  final _pingHist   = ValueNotifier<List<int>>([]);  // continuous ping history
  final _elapsedNf  = ValueNotifier<int>(0);      // seconds into current phase
  final _errorNf    = ValueNotifier<String?>(null);

  bool    _stopRequested = false;
  Timer?  _bgPingTimer;
  Timer?  _elapsedTimer;

  late AnimationController _pulse;
  List<_Entry> _history = [];

  // ── Init / dispose ─────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _loadHistory();
    _pulse = AnimationController(
      vsync:    this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _refreshLocations();
  }

  @override
  void dispose() {
    _pulse.dispose();
    _bgPingTimer?.cancel();
    _elapsedTimer?.cancel();
    for (final n in [
      _speedNf, _dlNf, _ulNf, _pingNf, _jitterNf, _testingNf,
      _phaseNf, _progressNf, _dlProgNf, _ulProgNf,
      _pointsNf, _pingHist, _elapsedNf, _errorNf,
    ]) { n.dispose(); }
    super.dispose();
  }

  // ── Location helpers ───────────────────────────────────────────────────────
  Future<void> _refreshLocations() async {
    // Run IP and GPS in parallel
    await Future.wait([_fetchIpLocation(), _fetchGpsLocation()]);
  }

  Future<void> _fetchIpLocation() async {
    locationFetchingNotifier.value = true;
    try {
      final info = await InternetSpeedService.getLocationAndIsp();
      if (info.location.isNotEmpty) await setIpLocation(info.location);
      if (info.isp.isNotEmpty)      await setIspName(info.isp);
    } finally {
      locationFetchingNotifier.value = false;
    }
  }

  Future<void> _fetchGpsLocation() async {
    if (!useGpsLocationNotifier.value) return;
    gpsFetchingNotifier.value = true;
    try {
      final result = await LocationService.getGpsLocation();
      if (result.city.isNotEmpty) {
        await setGpsLocation(result.city, result.lat, result.lng);
      }
    } finally {
      gpsFetchingNotifier.value = false;
    }
  }

  // ── History persistence ────────────────────────────────────────────────────
  Future<void> _loadHistory() async {
    final p   = await SharedPreferences.getInstance();
    final raw = p.getStringList('speed_history') ?? [];
    final out = <_Entry>[];
    for (final s in raw) {
      try { out.add(_Entry.fromJson(json.decode(s))); } catch (_) {}
    }
    if (mounted) setState(() => _history = out);
  }

  Future<void> _saveHistory() async {
    final p = await SharedPreferences.getInstance();
    await p.setStringList(
        'speed_history',
        _history.map((e) => json.encode(e.toJson())).toList());
  }

  Future<void> _deleteEntry(int i) async {
    setState(() => _history.removeAt(i));
    await _saveHistory();
  }

  Future<void> _clearHistory() async {
    setState(() => _history = []);
    (await SharedPreferences.getInstance()).remove('speed_history');
  }

  // ── Background ping (runs during DL + UL phases) ───────────────────────────
  void _startBgPing(int serverIdx) {
    _bgPingTimer?.cancel();
    _bgPingTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (!_testingNf.value) { _stopBgPing(); return; }
      final ms = await _svc.testPing(serverIdx);
      if (ms < 999 && _testingNf.value) {
        _pingNf.value = ms;
        final hist = List<int>.from(_pingHist.value)..add(ms);
        if (hist.length > 20) hist.removeAt(0);
        _pingHist.value = hist;
        // Recalculate jitter from recent ping history
        if (hist.length >= 3) {
          final avg  = hist.fold(0.0, (a, b) => a + b) / hist.length;
          final vari = hist.fold(0.0, (a, b) => a + pow(b - avg, 2)) / hist.length;
          _jitterNf.value = sqrt(vari).round();
        }
      }
    });
  }

  void _stopBgPing() {
    _bgPingTimer?.cancel();
    _bgPingTimer = null;
  }

  // ── Per-phase elapsed timer ────────────────────────────────────────────────
  void _startElapsed() {
    _elapsedNf.value = 0;
    _elapsedTimer?.cancel();
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_testingNf.value) { _stopElapsed(); return; }
      _elapsedNf.value++;
    });
  }

  void _stopElapsed() {
    _elapsedTimer?.cancel();
    _elapsedTimer = null;
  }

  // ── Main test runner ───────────────────────────────────────────────────────
  Future<void> _runTest() async {
    _stopRequested    = false;
    _testingNf.value  = true;
    _errorNf.value    = null;
    _speedNf.value    = 0;
    _dlNf.value       = 0;
    _ulNf.value       = 0;
    _pingNf.value     = 0;
    _jitterNf.value   = 0;
    _pingHist.value   = [];
    _pointsNf.value   = [];
    _progressNf.value = 0;
    _dlProgNf.value   = 0;
    _ulProgNf.value   = 0;
    _phaseNf.value    = 'LOCATING';

    try {
      _fetchIpLocation(); // fire and forget — don't block the test
      _progressNf.value = 0.04;
      if (_stopRequested) { _finish('STOPPED'); return; }

      // Build ordered server list for fallback
      final rawIdx   = selectedServerNotifier.value;
      final startSrv = InternetSpeedService.resolveServerIndex(rawIdx);
      final total    = InternetSpeedService.servers.length;
      final order    = List.generate(total, (i) => (startSrv + i) % total);
      final filtered = kIsWeb
          ? order.where((i) => InternetSpeedService.servers[i].corsCompatible).toList()
          : order;
      final candidates = autoFallbackNotifier.value
          ? filtered
          : [filtered.isEmpty ? startSrv : filtered.first];

      bool   ok        = false;
      String lastError = 'No server available';

      for (final srv in candidates) {
        if (_stopRequested) break;

        // Quick 3-second reachability check before committing to a full test
        if (autoFallbackNotifier.value && candidates.length > 1) {
          _phaseNf.value = 'CHECKING…';
          if (!await _svc.quickReachable(srv)) continue;
          if (_stopRequested) break;
        }

        try {
          await _runPhases(srv);
          ok = true;
          break;
        } catch (e) {
          lastError = e.toString();
          if (candidates.last != srv && !_stopRequested) {
            _phaseNf.value = 'SWITCHING…';
            await Future.delayed(const Duration(milliseconds: 400));
          }
        }
      }

      if (_stopRequested) {
        _finish('STOPPED');
      } else if (!ok) {
        _errorNf.value    = _friendlyError(lastError);
        _progressNf.value = 0;
        _phaseNf.value    = 'ERROR';
      }
    } catch (e) {
      _errorNf.value    = _friendlyError(e.toString());
      _progressNf.value = 0;
      _phaseNf.value    = 'ERROR';
    } finally {
      _stopBgPing();
      _stopElapsed();
      _testingNf.value = false;
    }
  }

  // Run the three phases (PING → DOWNLOAD → UPLOAD) for one server.
  // Throws on fatal errors so the caller can try the next server.
  Future<void> _runPhases(int srv) async {
    final total    = testDurationSecsNotifier.value; // 0 = infinite
    final phaseDur = _phaseDur(total);               // seconds per phase
    final isInf    = total == 0;

    // ── PING ──────────────────────────────────────────────────────────────
    _phaseNf.value = 'PING';
    _startElapsed();
    final pr = await _svc.testPingWithJitter(srv);
    if (_stopRequested) return;
    if (pr.ping == 999) throw Exception('Server unreachable (ping timeout)');
    _pingNf.value     = pr.ping;
    _jitterNf.value   = pr.jitter;
    _pingHist.value   = [pr.ping];
    _progressNf.value = 0.08;

    // Start continuous background ping for the DL + UL phases
    _startBgPing(srv);

    // ── DOWNLOAD ──────────────────────────────────────────────────────────
    _phaseNf.value  = 'DOWNLOAD';
    _dlProgNf.value = 0;
    _pointsNf.value = [];
    _startElapsed();

    Timer? dlTicker;
    if (!isInf) {
      final sw = Stopwatch()..start();
      dlTicker = Timer.periodic(const Duration(milliseconds: 150), (_) {
        if (_stopRequested) { dlTicker?.cancel(); return; }
        final frac = (sw.elapsedMilliseconds / (phaseDur * 1000)).clamp(0.0, 1.0);
        _dlProgNf.value   = frac;
        _progressNf.value = 0.08 + 0.46 * frac;
      });
    }

    await for (final mbps
        in _svc.testDownloadSpeed(serverIndex: srv, durationSecs: phaseDur)) {
      if (_stopRequested) break;
      _speedNf.value = mbps;
      _dlNf.value    = mbps;
      _addPoint(mbps);
    }
    dlTicker?.cancel();
    if (_stopRequested) return;
    _progressNf.value = 0.54;
    _dlProgNf.value   = 1.0;

    // ── UPLOAD ────────────────────────────────────────────────────────────
    _phaseNf.value  = 'UPLOAD';
    _ulProgNf.value = 0;
    _speedNf.value  = 0;
    _pointsNf.value = [];
    _startElapsed();

    Timer? ulTicker;
    if (!isInf) {
      final sw = Stopwatch()..start();
      ulTicker = Timer.periodic(const Duration(milliseconds: 150), (_) {
        if (_stopRequested) { ulTicker?.cancel(); return; }
        final frac = (sw.elapsedMilliseconds / (phaseDur * 1000)).clamp(0.0, 1.0);
        _ulProgNf.value   = frac;
        _progressNf.value = 0.54 + 0.46 * frac;
      });
    }

    await for (final mbps in _svc.testUploadSpeed(durationSecs: phaseDur)) {
      if (_stopRequested) break;
      _speedNf.value = mbps;
      _ulNf.value    = mbps;
      _addPoint(mbps);
    }
    ulTicker?.cancel();
    _stopBgPing();
    _stopElapsed();
    if (_stopRequested) return;

    _progressNf.value = 1.0;
    _ulProgNf.value   = 1.0;
    _speedNf.value    = _dlNf.value; // show DL speed on gauge when done
    _finish('DONE');

    // Save to history
    if (autoSaveHistoryNotifier.value) {
      final server = InternetSpeedService.servers[srv];
      final entry  = _Entry(
        timestamp: DateTime.now().toLocal().toString().substring(0, 16),
        flag:      server.flag,
        server:    server.name,
        provider:  server.provider,
        serverLoc: server.location,
        userLoc:   activeLocation,
        dl:        _dlNf.value,
        ul:        _ulNf.value,
        ping:      _pingNf.value,
        jitter:    _jitterNf.value,
        unit:      speedUnitMbpsNotifier.value ? 'Mb/s' : 'MB/s',
      );
      setState(() => _history.insert(0, entry));
      await _saveHistory();
    }
  }

  void _finish(String phase) {
    _phaseNf.value = phase;
    if (phase != 'DONE') _progressNf.value = 0;
  }

  void _addPoint(double mbps) {
    final pts = List<double>.from(_pointsNf.value)..add(mbps);
    if (pts.length > 80) pts.removeAt(0);
    _pointsNf.value = pts;
  }

  String _friendlyError(String raw) {
    if (raw.contains('Failed to fetch') || raw.contains('CORS')) {
      return 'CORS error — use Cloudflare server or the native app.';
    }
    if (raw.contains('SocketException') || raw.contains('No address')) {
      return 'No internet connection.';
    }
    if (raw.contains('timeout') || raw.contains('Timeout')) {
      return 'Timeout — server not responding.\nTry a different server or enable auto-fallback.';
    }
    if (raw.contains('unreachable')) {
      return 'Server unreachable. Enable auto-fallback or pick another server.';
    }
    if (raw.contains('HandshakeException')) {
      return 'SSL error — check your device date/time.';
    }
    return 'Error: $raw';
  }

  // ═══════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      backgroundColor: t.colorScheme.surface,
      body: SafeArea(
        child: IndexedStack(
          index: _tab,
          children: [
            _buildDash(t),
            _buildHistory(t),
            const SettingsScreen(),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex:          _tab,
        onDestinationSelected:  (i) => setState(() => _tab = i),
        backgroundColor:        t.colorScheme.surface,
        indicatorColor:         t.colorScheme.primaryContainer.withValues(alpha: 0.5),
        destinations: const [
          NavigationDestination(
            icon:         Icon(Icons.speed_outlined),
            selectedIcon: Icon(Icons.speed),
            label:        'Test',
          ),
          NavigationDestination(
            icon:         Icon(Icons.bar_chart_outlined),
            selectedIcon: Icon(Icons.bar_chart),
            label:        'Logs',
          ),
          NavigationDestination(
            icon:         Icon(Icons.tune_outlined),
            selectedIcon: Icon(Icons.tune),
            label:        'Settings',
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // DASHBOARD
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildDash(ThemeData t) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _topBar(t),
          if (kIsWeb) ...[const SizedBox(height: 6), _webBanner(t)],
          _errorBanner(t),
          Expanded(child: _gauge(t)),
          _phaseBar(t),
          const SizedBox(height: 8),
          _chart(t),
          const SizedBox(height: 10),
          _statsRow(t),
          const SizedBox(height: 10),
          _durationRow(t),
          const SizedBox(height: 8),
          _quickOptions(t),
          const SizedBox(height: 10),
          _startBtn(t),
          const SizedBox(height: 2),
        ],
      ),
    );
  }

  // ── Top bar ────────────────────────────────────────────────────────────────
  Widget _topBar(ThemeData t) {
    return Row(children: [
      // App name
      Text('JITTER', style: t.textTheme.titleSmall?.copyWith(
        fontWeight:    FontWeight.w900,
        letterSpacing: 3.5,
        color:         t.colorScheme.primary,
      )),
      const SizedBox(width: 8),
      // GPS indicator (only when GPS is active and available)
      _gpsChip(t),
      const Spacer(),
      // IP location chip
      _locationChip(t),
      const SizedBox(width: 8),
      // Status badge
      _statusBadge(t),
    ]);
  }

  Widget _gpsChip(ThemeData t) {
    return ValueListenableBuilder<bool>(
      valueListenable: useGpsLocationNotifier,
      builder: (_, useGps, __) {
        if (!useGps) return const SizedBox.shrink();
        return ValueListenableBuilder<String>(
          valueListenable: gpsLocationNotifier,
          builder: (_, gpsLoc, __) {
            if (gpsLoc.isEmpty) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color:        t.colorScheme.tertiaryContainer.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: t.colorScheme.tertiary.withValues(alpha: 0.3)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.gps_fixed_rounded, size: 10,
                      color: t.colorScheme.tertiary),
                  const SizedBox(width: 4),
                  Text(gpsLoc,
                      style: t.textTheme.labelSmall?.copyWith(
                        fontSize:   9,
                        color:      t.colorScheme.onTertiaryContainer,
                        fontWeight: FontWeight.w600,
                      )),
                ]),
              ),
            );
          },
        );
      },
    );
  }

  Widget _locationChip(ThemeData t) {
    return ValueListenableBuilder<bool>(
      valueListenable: locationFetchingNotifier,
      builder: (_, fetching, __) => ValueListenableBuilder<String>(
        valueListenable: ipLocationNotifier,
        builder: (_, loc, __) => ValueListenableBuilder<String>(
          valueListenable: ispNameNotifier,
          builder: (_, isp, __) => GestureDetector(
            onTap: fetching ? null : _refreshLocations,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                color:        t.colorScheme.secondaryContainer.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: t.colorScheme.secondary.withValues(alpha: 0.2)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                SizedBox(
                  width: 11, height: 11,
                  child: fetching
                      ? CircularProgressIndicator(
                          strokeWidth: 1.5,
                          color: t.colorScheme.secondary)
                      : Icon(Icons.language_rounded, size: 11,
                          color: t.colorScheme.secondary),
                ),
                const SizedBox(width: 4),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    fetching ? 'Detecting…' : loc.isEmpty ? 'Unknown' : loc,
                    style: t.textTheme.labelSmall?.copyWith(
                      fontSize:   10,
                      fontWeight: FontWeight.w600,
                      color:      fetching || loc.isEmpty
                          ? t.colorScheme.onSurface.withValues(alpha: 0.4)
                          : t.colorScheme.onSecondaryContainer,
                    ),
                  ),
                  if (isp.isNotEmpty && !fetching)
                    Text(isp,
                        style: t.textTheme.labelSmall?.copyWith(
                            fontSize: 8,
                            color: t.colorScheme.onSurface.withValues(alpha: 0.38))),
                ]),
                if (!fetching) ...[
                  const SizedBox(width: 3),
                  Icon(Icons.refresh_rounded, size: 9,
                      color: t.colorScheme.onSurface.withValues(alpha: 0.25)),
                ],
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _statusBadge(ThemeData t) {
    return ValueListenableBuilder<bool>(
      valueListenable: _testingNf,
      builder: (_, testing, __) => ValueListenableBuilder<String>(
        valueListenable: _phaseNf,
        builder: (_, phase, __) => AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: testing
                ? t.colorScheme.errorContainer.withValues(alpha: 0.18)
                : phase == 'DONE'
                    ? t.colorScheme.primaryContainer.withValues(alpha: 0.25)
                    : t.colorScheme.onSurface.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            AnimatedBuilder(
              animation: _pulse,
              builder: (_, __) => Container(
                width: 6, height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: testing
                      ? t.colorScheme.error
                          .withValues(alpha: 0.4 + _pulse.value * 0.6)
                      : phase == 'DONE'
                          ? t.colorScheme.primary
                              .withValues(alpha: 0.4 + _pulse.value * 0.3)
                          : t.colorScheme.onSurface.withValues(alpha: 0.2),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Text(phase == 'READY' ? 'READY'
                : phase == 'DONE' ? 'DONE'
                : phase,
                style: t.textTheme.labelSmall?.copyWith(
                    fontWeight:    FontWeight.bold,
                    letterSpacing: 0.6,
                    fontSize:      10)),
          ]),
        ),
      ),
    );
  }

  // ── Gauge ──────────────────────────────────────────────────────────────────
  Widget _gauge(ThemeData t) {
    return Center(
      child: LayoutBuilder(builder: (_, box) {
        final size = min(box.maxWidth * 0.88, box.maxHeight).clamp(150.0, 260.0);
        return ValueListenableBuilder<double>(
          valueListenable: _speedNf,
          builder: (_, mbps, __) => ValueListenableBuilder<bool>(
            valueListenable: speedUnitMbpsNotifier,
            builder: (_, isMbps, __) {
              final display = isMbps ? mbps : mbps / 8;
              return SizedBox(
                width: size, height: size,
                child: Stack(alignment: Alignment.center, children: [
                  // Arc
                  TweenAnimationBuilder<double>(
                    tween:    Tween(begin: 0.0, end: mbps),
                    duration: const Duration(milliseconds: 350),
                    curve:    Curves.easeOut,
                    builder: (_, v, __) => CustomPaint(
                      size: Size(size, size),
                      painter: _ArcPainter(
                        speedMbps:  v,
                        maxMbps:    1000,
                        trackColor: t.colorScheme.onSurface.withValues(alpha: 0.07),
                        primary:    t.colorScheme.primary,
                      ),
                    ),
                  ),
                  // Center content
                  Column(mainAxisSize: MainAxisSize.min, children: [
                    TweenAnimationBuilder<double>(
                      tween:    Tween(begin: 0.0, end: display),
                      duration: const Duration(milliseconds: 250),
                      curve:    Curves.easeOut,
                      builder: (_, v, __) => Text(
                        v >= 100
                            ? v.toStringAsFixed(0)
                            : v.toStringAsFixed(1),
                        style: t.textTheme.displayMedium?.copyWith(
                          fontWeight:   FontWeight.w900,
                          letterSpacing: -2,
                          height:        1.0,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(isMbps ? 'Mb/s' : 'MB/s',
                        style: t.textTheme.labelSmall?.copyWith(
                          color:         t.colorScheme.primary,
                          fontWeight:    FontWeight.bold,
                          letterSpacing: 1.5,
                        )),
                    const SizedBox(height: 10),
                    // Server + ISP info
                    ValueListenableBuilder<int>(
                      valueListenable: selectedServerNotifier,
                      builder: (_, si, __) {
                        final srv = InternetSpeedService.servers[
                            InternetSpeedService.resolveServerIndex(si)];
                        return Column(children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 3),
                            decoration: BoxDecoration(
                              color:        t.colorScheme.onSurface.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              '${srv.flag}  ${srv.location}  ·  ${srv.provider}',
                              style: t.textTheme.labelSmall?.copyWith(
                                color:    t.colorScheme.onSurface.withValues(alpha: 0.4),
                                fontSize: 9.5,
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          ValueListenableBuilder<String>(
                            valueListenable: ispNameNotifier,
                            builder: (_, isp, __) => isp.isEmpty
                                ? const SizedBox.shrink()
                                : Text('📶  $isp',
                                    style: t.textTheme.labelSmall?.copyWith(
                                        color: t.colorScheme.onSurface
                                            .withValues(alpha: 0.28),
                                        fontSize: 9)),
                          ),
                          const SizedBox(height: 4),
                          // Grade badge — shown only after test
                          ValueListenableBuilder<String>(
                            valueListenable: _phaseNf,
                            builder: (_, phase, __) => phase == 'DONE'
                                ? ValueListenableBuilder<double>(
                                    valueListenable: _dlNf,
                                    builder: (_, dl, __) {
                                      final g = _gradeFor(dl);
                                      return Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color:        g.color.withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(20),
                                          border: Border.all(
                                              color: g.color.withValues(alpha: 0.3)),
                                        ),
                                        child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                          Icon(g.icon,
                                              size: 11, color: g.color),
                                          const SizedBox(width: 5),
                                          Text(g.label,
                                              style: TextStyle(
                                                fontSize:      10,
                                                fontWeight:    FontWeight.w800,
                                                letterSpacing: 1,
                                                color:         g.color,
                                              )),
                                        ]),
                                      );
                                    })
                                : const SizedBox.shrink(),
                          ),
                        ]);
                      },
                    ),
                  ]),
                ]),
              );
            },
          ),
        );
      }),
    );
  }

  // ── Segmented phase progress bar ───────────────────────────────────────────
  Widget _phaseBar(ThemeData t) {
    return ValueListenableBuilder<String>(
      valueListenable: _phaseNf,
      builder: (_, phase, __) => ValueListenableBuilder<double>(
        valueListenable: _dlProgNf,
        builder: (_, dlP, __) => ValueListenableBuilder<double>(
          valueListenable: _ulProgNf,
          builder: (_, ulP, __) => ValueListenableBuilder<int>(
            valueListenable: _elapsedNf,
            builder: (_, elapsed, __) =>
                ValueListenableBuilder<bool>(
              valueListenable: _testingNf,
              builder: (_, testing, __) {
                final total = testDurationSecsNotifier.value;
                final pd    = _phaseDur(total);
                final isInf = total == 0;

                final pingDone = ['DOWNLOAD', 'UPLOAD', 'DONE', 'STOPPED']
                    .contains(phase);
                final dlActive = phase == 'DOWNLOAD';
                final dlDone   = ['UPLOAD', 'DONE', 'STOPPED'].contains(phase);
                final ulActive = phase == 'UPLOAD';
                final ulDone   = phase == 'DONE';

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Three progress segments
                    Row(children: [
                      // PING — narrow
                      Expanded(
                        flex: 1,
                        child: _SegBar(
                          progress: pingDone ? 1.0 : (phase == 'PING' ? 0.6 : 0.0),
                          active:   phase == 'PING',
                          done:     pingDone,
                          color:    t.colorScheme.tertiary,
                        ),
                      ),
                      const SizedBox(width: 4),
                      // DOWNLOAD
                      Expanded(
                        flex: 5,
                        child: _SegBar(
                          progress: dlDone ? 1.0 : (dlActive ? dlP : 0.0),
                          active:   dlActive,
                          done:     dlDone,
                          color:    t.colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 4),
                      // UPLOAD
                      Expanded(
                        flex: 5,
                        child: _SegBar(
                          progress: ulDone ? 1.0 : (ulActive ? ulP : 0.0),
                          active:   ulActive,
                          done:     ulDone,
                          color:    t.colorScheme.secondary,
                        ),
                      ),
                    ]),
                    const SizedBox(height: 7),
                    // Labels + elapsed time
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // PING label
                        Text('PING',
                            style: _segLabel(phase == 'PING', pingDone, t,
                                t.colorScheme.tertiary)),
                        // DOWNLOAD label + timer
                        Column(children: [
                          Text('↓ DOWNLOAD',
                              style: _segLabel(dlActive, dlDone, t,
                                  t.colorScheme.primary)),
                          if ((dlActive || ulActive) && testing) ...[
                            const SizedBox(height: 2),
                            Text(
                              dlActive
                                  ? (isInf
                                      ? _fmt(elapsed)
                                      : '${_fmt(elapsed)} / ${_fmt(pd)}')
                                  : _fmt(pd),
                              style: t.textTheme.labelSmall?.copyWith(
                                fontSize:     9,
                                color:        t.colorScheme.onSurface
                                    .withValues(alpha: 0.32),
                                fontFeatures: const [
                                  FontFeature.tabularFigures()
                                ],
                              ),
                            ),
                          ],
                        ]),
                        // UPLOAD label + timer
                        Column(crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                          Text('↑ UPLOAD',
                              style: _segLabel(ulActive, ulDone, t,
                                  t.colorScheme.secondary)),
                          if (ulActive && testing) ...[
                            const SizedBox(height: 2),
                            Text(
                              isInf
                                  ? _fmt(elapsed)
                                  : '${_fmt(elapsed)} / ${_fmt(pd)}',
                              style: t.textTheme.labelSmall?.copyWith(
                                fontSize:     9,
                                color:        t.colorScheme.onSurface
                                    .withValues(alpha: 0.32),
                                fontFeatures: const [
                                  FontFeature.tabularFigures()
                                ],
                              ),
                            ),
                          ],
                        ]),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  TextStyle? _segLabel(bool active, bool done, ThemeData t, Color c) =>
      t.textTheme.labelSmall?.copyWith(
        fontSize:      9.5,
        fontWeight:    active ? FontWeight.w800 : FontWeight.w400,
        letterSpacing: 0.6,
        color:         active
            ? c
            : done
                ? c.withValues(alpha: 0.5)
                : t.colorScheme.onSurface.withValues(alpha: 0.22),
      );

  // ── Live chart ─────────────────────────────────────────────────────────────
  Widget _chart(ThemeData t) {
    return SizedBox(
      height: 52,
      child: ValueListenableBuilder<List<double>>(
        valueListenable: _pointsNf,
        builder: (_, pts, __) => ValueListenableBuilder<String>(
          valueListenable: _phaseNf,
          builder: (_, phase, __) {
            final color = phase == 'UPLOAD'
                ? t.colorScheme.secondary
                : t.colorScheme.primary;
            return ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: CustomPaint(
                painter: _ChartPainter(points: pts, color: color, t: t),
              ),
            );
          },
        ),
      ),
    );
  }

  // ── Stats row (DL / UL / PING / JITTER) ───────────────────────────────────
  Widget _statsRow(ThemeData t) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color:        t.colorScheme.onSurface.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.colorScheme.onSurface.withValues(alpha: 0.07)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _statChip(
            icon:      Icons.arrow_downward_rounded,
            label:     'DOWN',
            iconColor: t.colorScheme.primary,
            valueBuilder: () => ValueListenableBuilder<double>(
              valueListenable: _dlNf,
              builder: (_, v, __) => ValueListenableBuilder<bool>(
                valueListenable: speedUnitMbpsNotifier,
                builder: (_, isMbps, __) {
                  final d = isMbps ? v : v / 8;
                  return _StatVal(
                    value: d >= 100 ? d.toStringAsFixed(0) : d.toStringAsFixed(1),
                    unit:  isMbps ? 'Mb/s' : 'MB/s',
                    color: t.colorScheme.primary, t: t,
                  );
                },
              ),
            ),
            t: t,
          ),
          _divider(t),
          _statChip(
            icon:      Icons.arrow_upward_rounded,
            label:     'UP',
            iconColor: t.colorScheme.secondary,
            valueBuilder: () => ValueListenableBuilder<double>(
              valueListenable: _ulNf,
              builder: (_, v, __) => ValueListenableBuilder<bool>(
                valueListenable: speedUnitMbpsNotifier,
                builder: (_, isMbps, __) {
                  final d = isMbps ? v : v / 8;
                  return _StatVal(
                    value: d >= 100 ? d.toStringAsFixed(0) : d.toStringAsFixed(1),
                    unit:  isMbps ? 'Mb/s' : 'MB/s',
                    color: t.colorScheme.secondary, t: t,
                  );
                },
              ),
            ),
            t: t,
          ),
          _divider(t),
          _statChip(
            icon:      Icons.network_ping_rounded,
            label:     'PING',
            iconColor: t.colorScheme.tertiary,
            valueBuilder: () => ValueListenableBuilder<int>(
              valueListenable: _pingNf,
              builder: (_, v, __) => _StatVal(
                value: '$v', unit: 'ms',
                color: _pingColor(v, context), t: t,
              ),
            ),
            t: t,
          ),
          _divider(t),
          _statChip(
            icon:      Icons.waves_rounded,
            label:     'JITTER',
            iconColor: t.colorScheme.error,
            valueBuilder: () => ValueListenableBuilder<int>(
              valueListenable: _jitterNf,
              builder: (_, v, __) => _StatVal(
                value: '$v', unit: 'ms',
                color: _jitterColor(v, context), t: t,
              ),
            ),
            t: t,
          ),
        ],
      ),
    );
  }

  Widget _statChip({
    required IconData icon,
    required String label,
    required Color iconColor,
    required Widget Function() valueBuilder,
    required ThemeData t,
  }) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 10, color: iconColor.withValues(alpha: 0.7)),
        const SizedBox(width: 3),
        Text(label,
            style: TextStyle(
              fontSize:      8.5,
              fontWeight:    FontWeight.bold,
              letterSpacing: 0.8,
              color:         iconColor.withValues(alpha: 0.65),
            )),
      ]),
      const SizedBox(height: 4),
      valueBuilder(),
    ]);
  }

  Widget _divider(ThemeData t) => Container(
    height: 28, width: 1,
    color: t.colorScheme.onSurface.withValues(alpha: 0.07),
  );

  // ── Duration chips row ─────────────────────────────────────────────────────
  Widget _durationRow(ThemeData t) {
    return ValueListenableBuilder<int>(
      valueListenable: testDurationSecsNotifier,
      builder: (_, cur, __) => ValueListenableBuilder<bool>(
        valueListenable: _testingNf,
        builder: (_, testing, __) => Row(children: [
          Text('Duration:',
              style: t.textTheme.labelSmall?.copyWith(
                color:      t.colorScheme.onSurface.withValues(alpha: 0.4),
                fontWeight: FontWeight.w500,
              )),
          const SizedBox(width: 8),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _kSteps.map((s) {
                  final sel = s == cur;
                  // Subtitle shows per-phase breakdown
                  final sub = s == 0
                      ? null
                      : '${_phaseDur(s)}s ↓ + ${_phaseDur(s)}s ↑';
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Tooltip(
                      message: sub ?? 'Runs until you press STOP',
                      child: GestureDetector(
                        onTap: testing ? null : () => setTestDuration(s),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 11, vertical: 5),
                          decoration: BoxDecoration(
                            color: sel
                                ? t.colorScheme.primary.withValues(alpha: 0.12)
                                : t.colorScheme.onSurface.withValues(alpha: 0.04),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: sel
                                  ? t.colorScheme.primary.withValues(alpha: 0.4)
                                  : t.colorScheme.onSurface.withValues(alpha: 0.08),
                            ),
                          ),
                          child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                            Text(_stepLabel(s),
                                style: t.textTheme.labelSmall?.copyWith(
                                  fontWeight: sel ? FontWeight.w800 : FontWeight.w400,
                                  color: sel
                                      ? t.colorScheme.primary
                                      : t.colorScheme.onSurface
                                          .withValues(alpha: testing ? 0.2 : 0.5),
                                )),
                            if (sub != null)
                              Text(sub,
                                  style: TextStyle(
                                    fontSize: 7.5,
                                    color:    (sel
                                            ? t.colorScheme.primary
                                            : t.colorScheme.onSurface)
                                        .withValues(alpha: testing ? 0.1 : 0.3),
                                  )),
                          ]),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  // ── Quick options: server chip + unit toggle ───────────────────────────────
  Widget _quickOptions(ThemeData t) {
    return ValueListenableBuilder<bool>(
      valueListenable: _testingNf,
      builder: (_, testing, __) => Row(children: [
        // Server chip
        ValueListenableBuilder<int>(
          valueListenable: selectedServerNotifier,
          builder: (_, si, __) {
            final srv = InternetSpeedService.servers[
                InternetSpeedService.resolveServerIndex(si)];
            return GestureDetector(
              onTap: testing ? null : _showServerSheet,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color:        t.colorScheme.onSurface.withValues(alpha: testing ? 0.03 : 0.06),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: t.colorScheme.onSurface.withValues(alpha: 0.09)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(srv.flag, style: const TextStyle(fontSize: 13)),
                  const SizedBox(width: 5),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(srv.name,
                        style: t.textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: t.colorScheme.onSurface
                              .withValues(alpha: testing ? 0.25 : 0.75),
                        )),
                    Text(srv.provider,
                        style: TextStyle(
                          fontSize: 8.5,
                          color:    t.colorScheme.onSurface
                              .withValues(alpha: testing ? 0.15 : 0.35),
                        )),
                  ]),
                  const SizedBox(width: 4),
                  Icon(Icons.expand_more_rounded,
                      size: 13,
                      color: t.colorScheme.onSurface
                          .withValues(alpha: testing ? 0.15 : 0.4)),
                ]),
              ),
            );
          },
        ),
        const Spacer(),
        // Unit toggle
        ValueListenableBuilder<bool>(
          valueListenable: speedUnitMbpsNotifier,
          builder: (_, isMbps, __) => Row(mainAxisSize: MainAxisSize.min, children: [
            _unitChip('Mb/s', isMbps,
                testing ? null : () => setSpeedUnit(true), t),
            const SizedBox(width: 4),
            _unitChip('MB/s', !isMbps,
                testing ? null : () => setSpeedUnit(false), t),
          ]),
        ),
      ]),
    );
  }

  Widget _unitChip(String label, bool sel, VoidCallback? onTap, ThemeData t) =>
      GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
          decoration: BoxDecoration(
            color: sel
                ? t.colorScheme.primary.withValues(alpha: 0.12)
                : t.colorScheme.onSurface.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: sel
                  ? t.colorScheme.primary.withValues(alpha: 0.4)
                  : t.colorScheme.onSurface.withValues(alpha: 0.08),
            ),
          ),
          child: Text(label,
              style: t.textTheme.labelSmall?.copyWith(
                fontWeight: sel ? FontWeight.w800 : FontWeight.w400,
                color: sel
                    ? t.colorScheme.primary
                    : t.colorScheme.onSurface
                        .withValues(alpha: onTap == null ? 0.18 : 0.5),
              )),
        ),
      );

  // Server picker bottom sheet
  void _showServerSheet() {
    showModalBottomSheet(
      context:           context,
      isScrollControlled: true,
      useSafeArea:       true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) {
        final t       = Theme.of(ctx);
        final servers = InternetSpeedService.availableServers;
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            // Handle bar
            Center(
              child: Container(
                width: 36, height: 4,
                margin: const EdgeInsets.only(bottom: 18),
                decoration: BoxDecoration(
                  color:        t.colorScheme.onSurface.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Header + fallback toggle
            Row(children: [
              Text('Select server',
                  style: t.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const Spacer(),
              ValueListenableBuilder<bool>(
                valueListenable: autoFallbackNotifier,
                builder: (_, v, __) => Row(children: [
                  Text('Auto-fallback',
                      style: t.textTheme.labelSmall?.copyWith(
                          color: t.colorScheme.onSurface.withValues(alpha: 0.5))),
                  const SizedBox(width: 4),
                  Switch.adaptive(
                    value:     v,
                    onChanged: setAutoFallback,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ]),
              ),
            ]),
            const SizedBox(height: 12),
            // Server list — scrollable
            ConstrainedBox(
              constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(ctx).size.height * 0.55),
              child: ListView.separated(
                shrinkWrap:     true,
                itemCount:      servers.length,
                separatorBuilder: (_, __) => Divider(
                    height: 1,
                    color: t.colorScheme.onSurface.withValues(alpha: 0.07)),
                itemBuilder: (_, i) {
                  final srv     = servers[i];
                  final realIdx = InternetSpeedService.servers.indexOf(srv);
                  return ValueListenableBuilder<int>(
                    valueListenable: selectedServerNotifier,
                    builder: (_, si, __) {
                      final sel = si == realIdx;
                      return ListTile(
                        leading: Text(srv.flag,
                            style: const TextStyle(fontSize: 22)),
                        title: Text(srv.name,
                            style: t.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600)),
                        subtitle: Text(
                            '${srv.location}  ·  ${srv.provider}',
                            style: t.textTheme.bodySmall?.copyWith(
                                color: t.colorScheme.onSurface
                                    .withValues(alpha: 0.45))),
                        trailing: sel
                            ? Icon(Icons.check_circle_rounded,
                                color: t.colorScheme.primary)
                            : null,
                        selected:          sel,
                        selectedTileColor: t.colorScheme.primary.withValues(alpha: 0.06),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        onTap: () {
                          setServer(realIdx);
                          Navigator.pop(ctx);
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ]),
        );
      },
    );
  }

  // ── Start / Stop button ────────────────────────────────────────────────────
  Widget _startBtn(ThemeData t) {
    return ValueListenableBuilder<bool>(
      valueListenable: _testingNf,
      builder: (_, testing, __) => SizedBox(
        height: 52,
        child: testing
            ? OutlinedButton(
                onPressed: () => setState(() => _stopRequested = true),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(
                      color: t.colorScheme.error.withValues(alpha: 0.45), width: 1.5),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(100)),
                  foregroundColor: t.colorScheme.error,
                ),
                child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                  SizedBox(
                    width: 14, height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: t.colorScheme.error.withValues(alpha: 0.5)),
                  ),
                  const SizedBox(width: 12),
                  Text('STOP',
                      style: TextStyle(
                        fontWeight:    FontWeight.bold,
                        letterSpacing: 2.0,
                        color:         t.colorScheme.error.withValues(alpha: 0.85),
                      )),
                ]),
              )
            : FilledButton(
                onPressed: _runTest,
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(100)),
                ),
                child: const Text('START TEST',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, letterSpacing: 2.0)),
              ),
      ),
    );
  }

  // ── Banners ────────────────────────────────────────────────────────────────
  Widget _webBanner(ThemeData t) => Container(
    margin:  const EdgeInsets.only(bottom: 6),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    decoration: BoxDecoration(
      color:        t.colorScheme.tertiaryContainer.withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: t.colorScheme.tertiary.withValues(alpha: 0.3)),
    ),
    child: Row(children: [
      Icon(Icons.public_rounded, size: 14, color: t.colorScheme.tertiary),
      const SizedBox(width: 8),
      Expanded(
        child: Text('Browser mode — only Cloudflare servers available.',
            style: t.textTheme.labelSmall?.copyWith(
                color: t.colorScheme.onTertiaryContainer, height: 1.4)),
      ),
    ]),
  );

  Widget _errorBanner(ThemeData t) => ValueListenableBuilder<String?>(
    valueListenable: _errorNf,
    builder: (_, err, __) {
      if (err == null) return const SizedBox.shrink();
      return Container(
        margin:  const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color:        t.colorScheme.errorContainer.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: t.colorScheme.error.withValues(alpha: 0.4)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.wifi_off_rounded, size: 16, color: t.colorScheme.error),
          const SizedBox(width: 10),
          Expanded(
            child: Text(err,
                style: t.textTheme.bodySmall?.copyWith(
                    color: t.colorScheme.onErrorContainer, height: 1.5)),
          ),
        ]),
      );
    },
  );

  // ═══════════════════════════════════════════════════════════════════════════
  // HISTORY TAB
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildHistory(ThemeData t) {
    // Group by user location
    final groups = <String, List<({_Entry e, int i})>>{};
    for (int i = 0; i < _history.length; i++) {
      final loc = _history[i].userLoc.isEmpty ? '📍 Unknown' : _history[i].userLoc;
      groups.putIfAbsent(loc, () => []).add((e: _history[i], i: i));
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('METRICS LOGS',
                style: t.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold, letterSpacing: 1.5)),
            if (_history.isNotEmpty)
              Text(
                '${_history.length} test${_history.length > 1 ? 's' : ''}'
                '  ·  ${groups.length} location${groups.length > 1 ? 's' : ''}',
                style: t.textTheme.bodySmall?.copyWith(
                    color: t.colorScheme.onSurface.withValues(alpha: 0.4))),
          ]),
          const Spacer(),
          if (_history.isNotEmpty)
            TextButton.icon(
              onPressed: _confirmClear,
              icon:  const Icon(Icons.delete_sweep_outlined, size: 15),
              label: const Text('Clear all'),
              style: TextButton.styleFrom(
                foregroundColor: t.colorScheme.error,
                visualDensity:   VisualDensity.compact,
              ),
            ),
        ]),
        const SizedBox(height: 14),
        Expanded(
          child: _history.isEmpty
              ? _emptyState(t)
              : ListView(
                  children: [
                    for (final g in groups.entries)
                      _locationGroup(g.key, g.value, t),
                    const SizedBox(height: 12),
                  ],
                ),
        ),
      ]),
    );
  }

  Widget _locationGroup(
      String loc, List<({_Entry e, int i})> items, ThemeData t) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 10),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color:        t.colorScheme.primaryContainer.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.place_rounded, size: 11, color: t.colorScheme.primary),
              const SizedBox(width: 5),
              Text(loc,
                  style: t.textTheme.labelSmall?.copyWith(
                    color:         t.colorScheme.primary,
                    fontWeight:    FontWeight.w800,
                    letterSpacing: 0.4,
                  )),
            ]),
          ),
          const SizedBox(width: 8),
          Expanded(child: Divider(
              color: t.colorScheme.onSurface.withValues(alpha: 0.08))),
          const SizedBox(width: 8),
          Text('${items.length} test${items.length > 1 ? 's' : ''}',
              style: t.textTheme.labelSmall?.copyWith(
                  color: t.colorScheme.onSurface.withValues(alpha: 0.35))),
        ]),
      ),
      // Entry cards
      ...items.map((r) => _entryCard(r.e, r.i, t)),
    ]);
  }

  Widget _entryCard(_Entry e, int idx, ThemeData t) {
    return Dismissible(
      key:       ValueKey('${e.timestamp}_$idx'),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => _deleteEntry(idx),
      background: Container(
        alignment: Alignment.centerRight,
        padding:   const EdgeInsets.only(right: 16),
        margin:    const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color:        t.colorScheme.errorContainer.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Icon(Icons.delete_outline_rounded, color: t.colorScheme.error),
      ),
      child: Container(
        margin:  const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color:        t.colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: t.colorScheme.onSurface.withValues(alpha: 0.06)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Timestamp + server badge
          Row(children: [
            Text(e.timestamp,
                style: t.textTheme.labelSmall?.copyWith(
                  color:    t.colorScheme.onSurface.withValues(alpha: 0.38),
                  fontSize: 9.5,
                )),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color:        t.colorScheme.onSurface.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text('${e.flag}  ${e.server}  ·  ${e.provider}',
                  style: t.textTheme.labelSmall?.copyWith(
                    fontSize: 9.5,
                    color:    t.colorScheme.onSurface.withValues(alpha: 0.45),
                  )),
            ),
          ]),
          const SizedBox(height: 10),
          // Stats row
          Row(children: [
            _histStat('↓', e.dl,           e.unit, t.colorScheme.primary,   t),
            const SizedBox(width: 16),
            _histStat('↑', e.ul,           e.unit, t.colorScheme.secondary, t),
            const SizedBox(width: 16),
            _histStat('ping',   e.ping.toDouble(),   'ms',
                _pingColor(e.ping, context),   t, isInt: true),
            const SizedBox(width: 16),
            _histStat('jitter', e.jitter.toDouble(), 'ms',
                _jitterColor(e.jitter, context), t, isInt: true),
          ]),
        ]),
      ),
    );
  }

  Widget _histStat(String label, double val, String unit, Color color,
      ThemeData t, {bool isInt = false}) {
    final display = isInt
        ? val.toInt().toString()
        : (val >= 100 ? val.toStringAsFixed(0) : val.toStringAsFixed(1));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label,
          style: TextStyle(
            fontSize:      8.5,
            fontWeight:    FontWeight.bold,
            letterSpacing: 0.6,
            color:         color.withValues(alpha: 0.65),
          )),
      const SizedBox(height: 2),
      RichText(
        text: TextSpan(children: [
          TextSpan(
            text:  display,
            style: t.textTheme.labelLarge?.copyWith(
              fontWeight:   FontWeight.w800,
              color:        color,
              height:       1.0,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          TextSpan(
            text:  ' $unit',
            style: t.textTheme.labelSmall?.copyWith(
              fontSize: 8.5,
              color:    color.withValues(alpha: 0.6),
            ),
          ),
        ]),
      ),
    ]);
  }

  // ── Confirm clear dialog ───────────────────────────────────────────────────
  void _confirmClear() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title:   const Text('Clear history'),
        content: const Text('Delete all test results? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child:     const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _clearHistory();
            },
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error),
            child: const Text('Delete all'),
          ),
        ],
      ),
    );
  }

  // ── Empty state (no history) ───────────────────────────────────────────────
  Widget _emptyState(ThemeData t) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.bar_chart_outlined,
            size:  52,
            color: t.colorScheme.onSurface.withValues(alpha: 0.13)),
        const SizedBox(height: 14),
        Text('No tests yet',
            style: t.textTheme.titleSmall?.copyWith(
              color:      t.colorScheme.onSurface.withValues(alpha: 0.35),
              fontWeight: FontWeight.w600,
            )),
        const SizedBox(height: 4),
        Text('Run a speed test to see your results here.',
            style: t.textTheme.bodySmall?.copyWith(
              color: t.colorScheme.onSurface.withValues(alpha: 0.22),
            )),
      ]),
    );
  }
} // ── end _HomeScreenState ───────────────────────────────────────────────────

// ═══════════════════════════════════════════════════════════════════════════════
// PAINTERS & HELPER WIDGETS
// ═══════════════════════════════════════════════════════════════════════════════

// Arc gauge (speedometer ring)
class _ArcPainter extends CustomPainter {
  final double speedMbps, maxMbps;
  final Color  trackColor, primary;
  const _ArcPainter({
    required this.speedMbps, required this.maxMbps,
    required this.trackColor, required this.primary,
  });

  // Starts at bottom-left (150°), sweeps 240° clockwise
  static const double _start = 150 * pi / 180;
  static const double _total = 240 * pi / 180;

  @override
  void paint(Canvas canvas, Size size) {
    final cx   = size.width  / 2;
    final cy   = size.height / 2;
    final r    = min(cx, cy) - 10;
    final rect = Rect.fromCircle(center: Offset(cx, cy), radius: r);

    // Track
    canvas.drawArc(
      rect, _start, _total, false,
      Paint()
        ..style       = PaintingStyle.stroke
        ..strokeWidth = 9
        ..strokeCap   = StrokeCap.round
        ..color       = trackColor,
    );

    // Arc fill
    final frac = (speedMbps / maxMbps).clamp(0.0, 1.0);
    if (frac > 0.005) {
      canvas.drawArc(
        rect, _start, _total * frac, false,
        Paint()
          ..style       = PaintingStyle.stroke
          ..strokeWidth = 9
          ..strokeCap   = StrokeCap.round
          ..shader      = SweepGradient(
            startAngle: _start,
            endAngle:   _start + _total * frac,
            colors:     [primary.withValues(alpha: 0.55), primary],
            transform:  GradientRotation(_start),
          ).createShader(rect),
      );
    }
  }

  @override
  bool shouldRepaint(_ArcPainter o) =>
      o.speedMbps != speedMbps || o.primary != primary || o.trackColor != trackColor;
}

// Segmented phase progress bar
class _SegBar extends StatelessWidget {
  final double progress;
  final bool   active, done;
  final Color  color;
  const _SegBar({
    required this.progress, required this.active,
    required this.done,     required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final fillColor = done
        ? color.withValues(alpha: 0.5)
        : active
            ? color
            : color.withValues(alpha: 0.0);

    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        height: 4,
        child: Stack(fit: StackFit.expand, children: [
          // Track
          ColoredBox(color: color.withValues(alpha: 0.1)),
          // Animated fill
          AnimatedFractionallySizedBox(
            duration:      const Duration(milliseconds: 120),
            alignment:     Alignment.centerLeft,
            widthFactor:   progress.clamp(0.0, 1.0),
            child:         ColoredBox(color: fillColor),
          ),
          // Indeterminate shimmer while ping is running (progress ≈ 0)
          if (active && progress < 0.05) _ShimmerBar(color: color),
        ]),
      ),
    );
  }
}

class _ShimmerBar extends StatefulWidget {
  final Color color;
  const _ShimmerBar({required this.color});
  @override
  State<_ShimmerBar> createState() => _ShimmerBarState();
}

class _ShimmerBarState extends State<_ShimmerBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double>   _anim;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync:    this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _anim,
    builder: (_, __) => Align(
      alignment: Alignment(-1.0 + _anim.value * 2, 0),
      child: FractionallySizedBox(
        widthFactor: 0.3,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                widget.color.withValues(alpha: 0.0),
                widget.color.withValues(alpha: 0.85),
                widget.color.withValues(alpha: 0.0),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

// Live speed chart
class _ChartPainter extends CustomPainter {
  final List<double> points;
  final Color        color;
  final ThemeData    t;
  const _ChartPainter({required this.points, required this.color, required this.t});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Background
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = color.withValues(alpha: 0.03),
    );

    if (points.length < 2) return;

    final maxV = points.reduce((a, b) => a > b ? a : b);
    final cap  = maxV < 1 ? 1.0 : maxV * 1.15;

    Offset pt(int i) => Offset(
      w * i / (points.length - 1),
      h - (points[i] / cap * h * 0.9 + h * 0.05),
    );

    final line = Path()..moveTo(pt(0).dx, pt(0).dy);
    for (int i = 1; i < points.length; i++) {
      line.lineTo(pt(i).dx, pt(i).dy);
    }

    // Fill
    final fill = Path.from(line)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin:  Alignment.topCenter,
          end:    Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.2), color.withValues(alpha: 0.0)],
        ).createShader(Offset.zero & size),
    );

    // Stroke
    canvas.drawPath(
      line,
      Paint()
        ..style       = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeCap   = StrokeCap.round
        ..strokeJoin  = StrokeJoin.round
        ..color       = color.withValues(alpha: 0.8),
    );
  }

  @override
  bool shouldRepaint(_ChartPainter o) =>
      o.points != points || o.color != color;
}

// Stat value + unit display
class _StatVal extends StatelessWidget {
  final String    value, unit;
  final Color     color;
  final ThemeData t;
  const _StatVal({
    required this.value, required this.unit,
    required this.color, required this.t,
  });

  @override
  Widget build(BuildContext context) => RichText(
    text: TextSpan(children: [
      TextSpan(
        text:  value,
        style: t.textTheme.titleMedium?.copyWith(
          fontWeight:   FontWeight.w800,
          color:        color,
          height:       1.0,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
      TextSpan(
        text:  ' $unit',
        style: t.textTheme.labelSmall?.copyWith(
          fontSize: 8.5,
          color:    color.withValues(alpha: 0.6),
        ),
      ),
    ]),
  );
}