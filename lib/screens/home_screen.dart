import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../app_state.dart';
import '../l10n.dart';
import '../services/internet_speed_service.dart';
import '../services/location_service.dart';
import 'settings_screen.dart';

// ── Performance grade based on download speed ──────────────────────────────
enum _Grade { excellent, veryGood, good, fair, slow, poor }

extension _GradeX on _Grade {
  String labelFor(BuildContext ctx) {
    switch (this) {
      case _Grade.excellent: return ctx.tr('grade_excellent');
      case _Grade.veryGood:  return ctx.tr('grade_veryGood');
      case _Grade.good:      return ctx.tr('grade_good');
      case _Grade.fair:      return ctx.tr('grade_fair');
      case _Grade.slow:      return ctx.tr('grade_slow');
      case _Grade.poor:      return ctx.tr('grade_poor');
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

int _phaseDur(int total) =>
    total == 0 ? 0 : max(total ~/ 2, 3);

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
  final _progressNf = ValueNotifier<double>(0);
  final _dlProgNf   = ValueNotifier<double>(0);
  final _ulProgNf   = ValueNotifier<double>(0);
  final _pointsNf   = ValueNotifier<List<double>>([]);
  final _pingHist   = ValueNotifier<List<int>>([]);
  final _elapsedNf  = ValueNotifier<int>(0);
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

  // ── Background ping ────────────────────────────────────────────────────────
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

  // ── Elapsed timer ──────────────────────────────────────────────────────────
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
      _fetchIpLocation();
      _progressNf.value = 0.04;
      if (_stopRequested) { _finish('STOPPED'); return; }

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

  Future<void> _runPhases(int srv) async {
    final total    = testDurationSecsNotifier.value;
    final phaseDur = _phaseDur(total);
    final isInf    = total == 0;

    _phaseNf.value = 'PING';
    _startElapsed();
    final pr = await _svc.testPingWithJitter(srv);
    if (_stopRequested) return;
    if (pr.ping == 999) throw Exception('Server unreachable (ping timeout)');
    _pingNf.value     = pr.ping;
    _jitterNf.value   = pr.jitter;
    _pingHist.value   = [pr.ping];
    _progressNf.value = 0.08;
    _startBgPing(srv);

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
    _speedNf.value    = _dlNf.value;
    _finish('DONE');

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
        unit:      kSpeedUnitLabels[speedUnitIndexNotifier.value],
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
        destinations: [
          NavigationDestination(
            icon:         const Icon(Icons.speed_outlined),
            selectedIcon: const Icon(Icons.speed),
            label:        context.tr('tabTest'),
          ),
          NavigationDestination(
            icon:         const Icon(Icons.bar_chart_outlined),
            selectedIcon: const Icon(Icons.bar_chart),
            label:        context.tr('tabLogs'),
          ),
          NavigationDestination(
            icon:         const Icon(Icons.tune_outlined),
            selectedIcon: const Icon(Icons.tune),
            label:        context.tr('tabSettings'),
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
      Text('JITTER', style: t.textTheme.titleSmall?.copyWith(
        fontWeight:    FontWeight.w900,
        letterSpacing: 3.5,
        color:         t.colorScheme.primary,
      )),
      const SizedBox(width: 8),
      _gpsChip(t),
      const Spacer(),
      _locationChip(t),
      const SizedBox(width: 8),
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
                    fetching ? context.tr('detecting') : loc.isEmpty ? context.tr('unknown') : loc,
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
            Text(phaseLabel(phase, context),
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
          builder: (_, mbps, __) => ValueListenableBuilder<int>(
            valueListenable: speedUnitIndexNotifier,
            builder: (_, unitIdx, __) {
              final display = convertSpeed(mbps, unitIdx);
              return SizedBox(
                width: size, height: size,
                child: Stack(alignment: Alignment.center, children: [
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
                  Column(mainAxisSize: MainAxisSize.min, children: [
                    TweenAnimationBuilder<double>(
                      tween:    Tween(begin: 0.0, end: display),
                      duration: const Duration(milliseconds: 250),
                      curve:    Curves.easeOut,
                      builder: (_, v, __) => Text(
                        formatSpeedValue(v * (mbps > 0 ? mbps / (display > 0 ? display : 1) : 1), unitIdx),
                        style: t.textTheme.displayMedium?.copyWith(
                          fontWeight:   FontWeight.w900,
                          letterSpacing: -2,
                          height:        1.0,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(kSpeedUnitLabels[unitIdx],
                        style: t.textTheme.labelSmall?.copyWith(
                          color:         t.colorScheme.primary,
                          fontWeight:    FontWeight.bold,
                          letterSpacing: 1.5,
                        )),
                    const SizedBox(height: 10),
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
                                          Icon(g.icon, size: 11, color: g.color),
                                          const SizedBox(width: 5),
                                          Text(g.labelFor(context),
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

  // ── Phase progress bar ─────────────────────────────────────────────────────
  Widget _phaseBar(ThemeData t) {
    return ValueListenableBuilder<String>(
      valueListenable: _phaseNf,
      builder: (ctx, phase, __) => ValueListenableBuilder<double>(
        valueListenable: _dlProgNf,
        builder: (_, dlP, __) => ValueListenableBuilder<double>(
          valueListenable: _ulProgNf,
          builder: (_, ulP, __) => ValueListenableBuilder<int>(
            valueListenable: _elapsedNf,
            builder: (_, elapsed, __) => ValueListenableBuilder<bool>(
              valueListenable: _testingNf,
              builder: (_, testing, __) {
                final total = testDurationSecsNotifier.value;
                final pd    = _phaseDur(total);
                final isInf = total == 0;

                final pingDone = ['DOWNLOAD', 'UPLOAD', 'DONE', 'STOPPED'].contains(phase);
                final dlActive = phase == 'DOWNLOAD';
                final dlDone   = ['UPLOAD', 'DONE', 'STOPPED'].contains(phase);
                final ulActive = phase == 'UPLOAD';
                final ulDone   = phase == 'DONE';

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(children: [
                      Expanded(flex: 1, child: _SegBar(
                        progress: pingDone ? 1.0 : (phase == 'PING' ? 0.6 : 0.0),
                        active: phase == 'PING', done: pingDone,
                        color: t.colorScheme.tertiary,
                      )),
                      const SizedBox(width: 4),
                      Expanded(flex: 5, child: _SegBar(
                        progress: dlDone ? 1.0 : (dlActive ? dlP : 0.0),
                        active: dlActive, done: dlDone,
                        color: t.colorScheme.primary,
                      )),
                      const SizedBox(width: 4),
                      Expanded(flex: 5, child: _SegBar(
                        progress: ulDone ? 1.0 : (ulActive ? ulP : 0.0),
                        active: ulActive, done: ulDone,
                        color: t.colorScheme.secondary,
                      )),
                    ]),
                    const SizedBox(height: 7),
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      Text(ctx.tr('ping'),
                          style: _segLabel(phase == 'PING', pingDone, t, t.colorScheme.tertiary)),
                      Column(children: [
                        Text(ctx.tr('dlLabel'),
                            style: _segLabel(dlActive, dlDone, t, t.colorScheme.primary)),
                        if ((dlActive || ulActive) && testing) ...[
                          const SizedBox(height: 2),
                          Text(
                            dlActive
                                ? (isInf ? _fmt(elapsed) : '${_fmt(elapsed)} / ${_fmt(pd)}')
                                : _fmt(pd),
                            style: t.textTheme.labelSmall?.copyWith(
                              fontSize: 9,
                              color: t.colorScheme.onSurface.withValues(alpha: 0.32),
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                        ],
                      ]),
                      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Text(ctx.tr('ulLabel'),
                            style: _segLabel(ulActive, ulDone, t, t.colorScheme.secondary)),
                        if (ulActive && testing) ...[
                          const SizedBox(height: 2),
                          Text(
                            isInf ? _fmt(elapsed) : '${_fmt(elapsed)} / ${_fmt(pd)}',
                            style: t.textTheme.labelSmall?.copyWith(
                              fontSize: 9,
                              color: t.colorScheme.onSurface.withValues(alpha: 0.32),
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                        ],
                      ]),
                    ]),
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
        color:         active ? c : done
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

  // ── Stats row ──────────────────────────────────────────────────────────────
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
            icon: Icons.arrow_downward_rounded,
            label: context.tr('down'),
            iconColor: t.colorScheme.primary,
            valueBuilder: () => ValueListenableBuilder<double>(
              valueListenable: _dlNf,
              builder: (_, v, __) => ValueListenableBuilder<int>(
                valueListenable: speedUnitIndexNotifier,
                builder: (_, ui, __) => _StatVal(
                  value: formatSpeedValue(v, ui),
                  unit:  kSpeedUnitLabels[ui],
                  color: t.colorScheme.primary, t: t,
                ),
              ),
            ),
            t: t,
          ),
          _divider(t),
          _statChip(
            icon: Icons.arrow_upward_rounded,
            label: context.tr('up'),
            iconColor: t.colorScheme.secondary,
            valueBuilder: () => ValueListenableBuilder<double>(
              valueListenable: _ulNf,
              builder: (_, v, __) => ValueListenableBuilder<int>(
                valueListenable: speedUnitIndexNotifier,
                builder: (_, ui, __) => _StatVal(
                  value: formatSpeedValue(v, ui),
                  unit:  kSpeedUnitLabels[ui],
                  color: t.colorScheme.secondary, t: t,
                ),
              ),
            ),
            t: t,
          ),
          _divider(t),
          _statChip(
            icon: Icons.network_ping_rounded,
            label: context.tr('ping'),
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
            icon: Icons.waves_rounded,
            label: context.tr('jitter'),
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
        Text(label, style: TextStyle(
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
          Text(context.tr('duration'),
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
                  final sub = s == 0 ? null : '${_phaseDur(s)}s ↓ + ${_phaseDur(s)}s ↑';
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Tooltip(
                      message: sub ?? 'Runs until you press STOP',
                      child: GestureDetector(
                        onTap: testing ? null : () => setTestDuration(s),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
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
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            Text(_stepLabel(s),
                                style: t.textTheme.labelSmall?.copyWith(
                                  fontWeight: sel ? FontWeight.w800 : FontWeight.w400,
                                  color: sel
                                      ? t.colorScheme.primary
                                      : t.colorScheme.onSurface.withValues(alpha: testing ? 0.2 : 0.5),
                                )),
                            if (sub != null)
                              Text(sub, style: TextStyle(
                                fontSize: 7.5,
                                color: (sel ? t.colorScheme.primary : t.colorScheme.onSurface)
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

  // ── Quick options: server + unit ───────────────────────────────────────────
  Widget _quickOptions(ThemeData t) {
    return ValueListenableBuilder<bool>(
      valueListenable: _testingNf,
      builder: (_, testing, __) => Row(children: [
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
                    Text(srv.name, style: t.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: t.colorScheme.onSurface.withValues(alpha: testing ? 0.25 : 0.75),
                    )),
                    Text(srv.provider, style: TextStyle(
                      fontSize: 8.5,
                      color: t.colorScheme.onSurface.withValues(alpha: testing ? 0.15 : 0.35),
                    )),
                  ]),
                  const SizedBox(width: 4),
                  Icon(Icons.expand_more_rounded, size: 13,
                      color: t.colorScheme.onSurface.withValues(alpha: testing ? 0.15 : 0.4)),
                ]),
              ),
            );
          },
        ),
        const Spacer(),
        // Unit cycle chips — 4 options
        ValueListenableBuilder<int>(
          valueListenable: speedUnitIndexNotifier,
          builder: (_, unitIdx, __) => Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(kSpeedUnitLabels.length, (i) => Padding(
              padding: EdgeInsets.only(left: i == 0 ? 0 : 4),
              child: _unitChip(
                kSpeedUnitLabels[i],
                unitIdx == i,
                testing ? null : () => setSpeedUnitIndex(i),
                t,
              ),
            )),
          ),
        ),
      ]),
    );
  }

  Widget _unitChip(String label, bool sel, VoidCallback? onTap, ThemeData t) =>
      GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
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
                fontSize:   10,
                fontWeight: sel ? FontWeight.w800 : FontWeight.w400,
                color: sel
                    ? t.colorScheme.primary
                    : t.colorScheme.onSurface.withValues(alpha: onTap == null ? 0.18 : 0.5),
              )),
        ),
      );

  void _showServerSheet() {
    showModalBottomSheet(
      context:            context,
      isScrollControlled: true,
      useSafeArea:        true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) {
        final t       = Theme.of(ctx);
        final servers = InternetSpeedService.availableServers;
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Center(child: Container(
              width: 36, height: 4,
              margin: const EdgeInsets.only(bottom: 18),
              decoration: BoxDecoration(
                color: t.colorScheme.onSurface.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(2),
              ),
            )),
            Row(children: [
              Text(context.tr('selectServer'),
                  style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
              const Spacer(),
              ValueListenableBuilder<bool>(
                valueListenable: autoFallbackNotifier,
                builder: (_, v, __) => Row(children: [
                  Text(context.tr('autoFallback'),
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
            ConstrainedBox(
              constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(ctx).size.height * 0.55),
              child: ListView.separated(
                shrinkWrap:       true,
                itemCount:        servers.length,
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
                        leading: Text(srv.flag, style: const TextStyle(fontSize: 22)),
                        title: Text(srv.name,
                            style: t.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                        subtitle: Text('${srv.location}  ·  ${srv.provider}',
                            style: t.textTheme.bodySmall?.copyWith(
                                color: t.colorScheme.onSurface.withValues(alpha: 0.45))),
                        trailing: sel
                            ? Icon(Icons.check_circle_rounded, color: t.colorScheme.primary)
                            : null,
                        selected:          sel,
                        selectedTileColor: t.colorScheme.primary.withValues(alpha: 0.06),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        onTap: () { setServer(realIdx); Navigator.pop(ctx); },
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
                  side: BorderSide(color: t.colorScheme.error.withValues(alpha: 0.45), width: 1.5),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
                  foregroundColor: t.colorScheme.error,
                ),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  SizedBox(
                    width: 14, height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: t.colorScheme.error.withValues(alpha: 0.5)),
                  ),
                  const SizedBox(width: 12),
                  Text(context.tr('stop'), style: TextStyle(
                    fontWeight:    FontWeight.bold,
                    letterSpacing: 2.0,
                    color:         t.colorScheme.error.withValues(alpha: 0.85),
                  )),
                ]),
              )
            : FilledButton(
                onPressed: _runTest,
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
                ),
                child: Text(context.tr('startTest'),
                    style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 2.0)),
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
      Expanded(child: Text(context.tr('webBanner'),
          style: t.textTheme.labelSmall?.copyWith(
              color: t.colorScheme.onTertiaryContainer, height: 1.4))),
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
          Expanded(child: Text(err,
              style: t.textTheme.bodySmall?.copyWith(
                  color: t.colorScheme.onErrorContainer, height: 1.5))),
        ]),
      );
    },
  );

  // ═══════════════════════════════════════════════════════════════════════════
  // HISTORY TAB
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildHistory(ThemeData t) {
    final groups = <String, List<({_Entry e, int i})>>{};
    for (int i = 0; i < _history.length; i++) {
      final loc = _history[i].userLoc.isEmpty
          ? context.tr('unknownLoc')
          : _history[i].userLoc;
      groups.putIfAbsent(loc, () => []).add((e: _history[i], i: i));
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(context.tr('metricsLogs'),
                style: t.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold, letterSpacing: 1.5)),
            if (_history.isNotEmpty)
              Text(
                '${_history.length} test${_history.length > 1 ? 's' : ''}'
                '  ·  ${groups.length} loc.',
                style: t.textTheme.bodySmall?.copyWith(
                    color: t.colorScheme.onSurface.withValues(alpha: 0.4))),
          ]),
          const Spacer(),
          if (_history.isNotEmpty) ...[
            // Export CSV button
            IconButton(
              icon: const Icon(Icons.file_download_outlined, size: 18),
              tooltip: context.tr('exportCsv'),
              onPressed: _exportCsv,
              color: t.colorScheme.secondary,
              visualDensity: VisualDensity.compact,
            ),
            TextButton.icon(
              onPressed: _confirmClear,
              icon:  const Icon(Icons.delete_sweep_outlined, size: 15),
              label: Text(context.tr('clearAll')),
              style: TextButton.styleFrom(
                foregroundColor: t.colorScheme.error,
                visualDensity:   VisualDensity.compact,
              ),
            ),
          ],
        ]),
        const SizedBox(height: 14),
        Expanded(
          child: _history.isEmpty
              ? _emptyState(t)
              : ListView(children: [
                  for (final g in groups.entries)
                    _locationGroup(g.key, g.value, t),
                  const SizedBox(height: 12),
                ]),
        ),
      ]),
    );
  }

  Future<void> _exportCsv() async {
    if (_history.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('exportEmpty'))),
      );
      return;
    }
    final buf = StringBuffer();
    buf.writeln('timestamp,flag,server,provider,server_location,'
        'user_location,download_mbps,upload_mbps,ping_ms,jitter_ms,unit');
    for (final e in _history) {
      final row = [
        e.timestamp,
        e.flag,
        e.server,
        e.provider,
        '"${e.serverLoc.replaceAll('"', '""')}"',
        '"${e.userLoc.replaceAll('"', '""')}"',
        e.dl.toStringAsFixed(2),
        e.ul.toStringAsFixed(2),
        e.ping,
        e.jitter,
        e.unit,
      ].join(',');
      buf.writeln(row);
    }
    await Clipboard.setData(ClipboardData(text: buf.toString()));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(context.tr('exportCopied')),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  Widget _locationGroup(String loc, List<({_Entry e, int i})> items, ThemeData t) {
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
              Text(loc, style: t.textTheme.labelSmall?.copyWith(
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
      child: GestureDetector(
        onTap: () => _showEntryDetail(e),
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
            Row(children: [
              Text(e.timestamp, style: t.textTheme.labelSmall?.copyWith(
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
            Row(children: [
              _histStat('↓', e.dl, e.unit, t.colorScheme.primary, t),
              const SizedBox(width: 16),
              _histStat('↑', e.ul, e.unit, t.colorScheme.secondary, t),
              const SizedBox(width: 16),
              _histStat('ping',   e.ping.toDouble(),   'ms',
                  _pingColor(e.ping, context), t, isInt: true),
              const SizedBox(width: 16),
              _histStat('jitter', e.jitter.toDouble(), 'ms',
                  _jitterColor(e.jitter, context), t, isInt: true),
              const Spacer(),
              Icon(Icons.chevron_right_rounded, size: 16,
                  color: t.colorScheme.onSurface.withValues(alpha: 0.22)),
            ]),
          ]),
        ),
      ),
    );
  }

  void _showEntryDetail(_Entry entry) {
    showModalBottomSheet(
      context:            context,
      isScrollControlled: true,
      useSafeArea:        true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _EntryDetailSheet(
        entry:   entry,
        history: _history,
      ),
    );
  }

  Widget _histStat(String label, double val, String unit, Color color,
      ThemeData t, {bool isInt = false}) {
    final display = isInt
        ? val.toInt().toString()
        : (val >= 100 ? val.toStringAsFixed(0) : val.toStringAsFixed(1));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(
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

  void _confirmClear() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title:   Text(context.tr('clearHistory')),
        content: Text(context.tr('clearHistoryBody')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child:     Text(context.tr('cancel')),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _clearHistory();
            },
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error),
            child: Text(context.tr('deleteAll')),
          ),
        ],
      ),
    );
  }

  Widget _emptyState(ThemeData t) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.bar_chart_outlined,
            size:  52,
            color: t.colorScheme.onSurface.withValues(alpha: 0.13)),
        const SizedBox(height: 14),
        Text(context.tr('noTests'), style: t.textTheme.titleSmall?.copyWith(
          color:      t.colorScheme.onSurface.withValues(alpha: 0.35),
          fontWeight: FontWeight.w600,
        )),
        const SizedBox(height: 4),
        Text(context.tr('noTestsHint'), style: t.textTheme.bodySmall?.copyWith(
          color: t.colorScheme.onSurface.withValues(alpha: 0.22),
        )),
      ]),
    );
  }
} // ── end _HomeScreenState ───────────────────────────────────────────────────

// ═══════════════════════════════════════════════════════════════════════════════
// ENTRY DETAIL SHEET — with interactive trend chart
// ═══════════════════════════════════════════════════════════════════════════════

class _EntryDetailSheet extends StatefulWidget {
  final _Entry entry;
  final List<_Entry> history; // newest-first list from home screen
  const _EntryDetailSheet({required this.entry, required this.history});

  @override
  State<_EntryDetailSheet> createState() => _EntryDetailSheetState();
}

class _EntryDetailSheetState extends State<_EntryDetailSheet> {
  int  _metric   = 0;  // 0=DL, 1=UL, 2=ping, 3=jitter
  int? _hoverIdx;      // index into _chrono list under user's finger

  // Reverse to chronological order (oldest → newest)
  List<_Entry> get _chrono => widget.history.reversed.toList();

  int get _selectedIdx {
    final idx = _chrono.indexOf(widget.entry);
    return idx < 0 ? _chrono.length - 1 : idx;
  }

  _Entry get _displayEntry =>
      (_hoverIdx != null && _hoverIdx! < _chrono.length)
          ? _chrono[_hoverIdx!]
          : widget.entry;

  static const _metricIcons = [
    Icons.arrow_downward_rounded,
    Icons.arrow_upward_rounded,
    Icons.network_ping_rounded,
    Icons.waves_rounded,
  ];
  static const _metricKeys = ['down', 'up', 'ping', 'jitter'];

  Color _metricColor(int m, ThemeData t) {
    switch (m) {
      case 0: return t.colorScheme.primary;
      case 1: return t.colorScheme.secondary;
      case 2: return t.colorScheme.tertiary;
      default: return t.colorScheme.error;
    }
  }

  String _displayValue(_Entry e, int m, int unitIdx) {
    switch (m) {
      case 0: return formatSpeedValue(e.dl, unitIdx);
      case 1: return formatSpeedValue(e.ul, unitIdx);
      case 2: return '${e.ping}';
      default: return '${e.jitter}';
    }
  }

  String _displayUnit(int m, int unitIdx) {
    return (m < 2) ? kSpeedUnitLabels[unitIdx] : 'ms';
  }

  double _rawValue(_Entry e, int m) {
    switch (m) {
      case 0: return e.dl;
      case 1: return e.ul;
      case 2: return e.ping.toDouble();
      default: return e.jitter.toDouble();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t       = Theme.of(context);
    final chrono  = _chrono;
    final displayE = _displayEntry;
    final unitIdx = speedUnitIndexNotifier.value;
    final grade   = _gradeFor(displayE.dl);

    return DraggableScrollableSheet(
      expand:           false,
      initialChildSize: 0.92,
      minChildSize:     0.5,
      maxChildSize:     0.95,
      builder: (_, sc) => Column(children: [
        // Handle
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Center(child: Container(
            width: 36, height: 4,
            decoration: BoxDecoration(
              color:        t.colorScheme.onSurface.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(2),
            ),
          )),
        ),
        // Scrollable body
        Expanded(child: SingleChildScrollView(
          controller: sc,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

            // ── Header ──────────────────────────────────────────────────────
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(context.tr('testDetail'),
                    style: t.textTheme.labelSmall?.copyWith(
                      color:         t.colorScheme.primary,
                      fontWeight:    FontWeight.bold,
                      letterSpacing: 1.5,
                    )),
                const SizedBox(height: 4),
                Text(displayE.timestamp,
                    style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Row(children: [
                  Text(displayE.flag, style: const TextStyle(fontSize: 14)),
                  const SizedBox(width: 5),
                  Flexible(child: Text(
                    '${displayE.server}  ·  ${displayE.provider}\n${displayE.serverLoc}',
                    style: t.textTheme.bodySmall?.copyWith(
                        color: t.colorScheme.onSurface.withValues(alpha: 0.55)),
                  )),
                ]),
                if (displayE.userLoc.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(children: [
                    Icon(Icons.place_rounded, size: 11,
                        color: t.colorScheme.primary.withValues(alpha: 0.6)),
                    const SizedBox(width: 4),
                    Text(displayE.userLoc, style: t.textTheme.bodySmall?.copyWith(
                        color: t.colorScheme.primary.withValues(alpha: 0.6))),
                  ]),
                ],
              ])),
              // Grade badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color:        grade.color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: grade.color.withValues(alpha: 0.3)),
                ),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(grade.icon, size: 18, color: grade.color),
                  const SizedBox(height: 3),
                  Text(grade.labelFor(context), style: TextStyle(
                    fontSize:      9,
                    fontWeight:    FontWeight.w800,
                    letterSpacing: 0.8,
                    color:         grade.color,
                  )),
                ]),
              ),
            ]),
            const SizedBox(height: 20),

            // ── 4 metric cards ───────────────────────────────────────────────
            Row(children: List.generate(4, (m) {
              final color = _metricColor(m, t);
              final val   = _displayValue(displayE, m, unitIdx);
              final unit  = _displayUnit(m, unitIdx);
              final sel   = m == _metric;
              return Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _metric = m),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    margin: EdgeInsets.only(right: m < 3 ? 8 : 0),
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                    decoration: BoxDecoration(
                      color: sel
                          ? color.withValues(alpha: 0.12)
                          : t.colorScheme.onSurface.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: sel
                            ? color.withValues(alpha: 0.4)
                            : t.colorScheme.onSurface.withValues(alpha: 0.07),
                        width: sel ? 1.5 : 1,
                      ),
                    ),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(_metricIcons[m], size: 14,
                          color: color.withValues(alpha: sel ? 1.0 : 0.5)),
                      const SizedBox(height: 5),
                      Text(val, style: t.textTheme.titleSmall?.copyWith(
                        fontWeight:    FontWeight.w800,
                        color:         color,
                        height:        1.0,
                        fontFeatures:  const [FontFeature.tabularFigures()],
                      )),
                      Text(unit, style: TextStyle(
                        fontSize:  8,
                        color:     color.withValues(alpha: 0.65),
                        fontWeight: FontWeight.w600,
                      )),
                    ]),
                  ),
                ),
              );
            })),
            const SizedBox(height: 24),

            // ── Trend chart (only if multiple entries) ────────────────────────
            if (chrono.length > 1) ...[
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text(context.tr('trend'),
                    style: t.textTheme.labelSmall?.copyWith(
                      color:         t.colorScheme.primary,
                      fontWeight:    FontWeight.bold,
                      letterSpacing: 1.5,
                    )),
                if (_hoverIdx != null)
                  Text(
                    _chrono[_hoverIdx!].timestamp,
                    style: t.textTheme.labelSmall?.copyWith(
                        color: t.colorScheme.onSurface.withValues(alpha: 0.5)),
                  ),
              ]),
              const SizedBox(height: 10),
              // Metric tab row
              SizedBox(
                height: 28,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount:       4,
                  separatorBuilder: (_, __) => const SizedBox(width: 6),
                  itemBuilder: (_, m) {
                    final sel   = m == _metric;
                    final color = _metricColor(m, t);
                    return GestureDetector(
                      onTap: () => setState(() => _metric = m),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: sel
                              ? color.withValues(alpha: 0.12)
                              : t.colorScheme.onSurface.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: sel
                                ? color.withValues(alpha: 0.4)
                                : t.colorScheme.onSurface.withValues(alpha: 0.08),
                          ),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(_metricIcons[m], size: 10,
                              color: color.withValues(alpha: sel ? 1.0 : 0.5)),
                          const SizedBox(width: 4),
                          Text(context.tr(_metricKeys[m]),
                              style: t.textTheme.labelSmall?.copyWith(
                                fontSize:   10,
                                fontWeight: sel ? FontWeight.w700 : FontWeight.w400,
                                color:      sel
                                    ? color
                                    : t.colorScheme.onSurface.withValues(alpha: 0.5),
                              )),
                        ]),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              // Interactive chart
              Container(
                height: 190,
                decoration: BoxDecoration(
                  color:        t.colorScheme.onSurface.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color: t.colorScheme.onSurface.withValues(alpha: 0.06)),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: _TrendChart(
                    entries:     chrono,
                    selectedIdx: _selectedIdx,
                    metric:      _metric,
                    color:       _metricColor(_metric, t),
                    t:           t,
                    onHover:     (idx) => setState(() => _hoverIdx = idx),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              // X-axis date labels
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text(_chrono.first.timestamp.substring(5, 10),
                    style: t.textTheme.labelSmall?.copyWith(
                        fontSize: 9,
                        color: t.colorScheme.onSurface.withValues(alpha: 0.35))),
                Text(_chrono.last.timestamp.substring(5, 10),
                    style: t.textTheme.labelSmall?.copyWith(
                        fontSize: 9,
                        color: t.colorScheme.onSurface.withValues(alpha: 0.35))),
              ]),
              const SizedBox(height: 24),
            ],

            // ── VS Average ────────────────────────────────────────────────────
            if (chrono.length > 1) ...[
              Text(context.tr('vsAverage'),
                  style: t.textTheme.labelSmall?.copyWith(
                    color:         t.colorScheme.primary,
                    fontWeight:    FontWeight.bold,
                    letterSpacing: 1.5,
                  )),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color:        t.colorScheme.onSurface.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color: t.colorScheme.onSurface.withValues(alpha: 0.06)),
                ),
                child: Column(children: [
                  _vsRow(
                    label: context.tr('down'),
                    thisVal: displayE.dl,
                    allVals: chrono.map((e) => e.dl).toList(),
                    color:   t.colorScheme.primary,
                    unitIdx: unitIdx,
                    t:       t,
                    isSpeed: true,
                  ),
                  const SizedBox(height: 12),
                  _vsRow(
                    label: context.tr('up'),
                    thisVal: displayE.ul,
                    allVals: chrono.map((e) => e.ul).toList(),
                    color:   t.colorScheme.secondary,
                    unitIdx: unitIdx,
                    t:       t,
                    isSpeed: true,
                  ),
                  const SizedBox(height: 12),
                  _vsRow(
                    label: context.tr('ping'),
                    thisVal: displayE.ping.toDouble(),
                    allVals: chrono.map((e) => e.ping.toDouble()).toList(),
                    color:   _pingColor(displayE.ping, context),
                    unitIdx: unitIdx,
                    t:       t,
                    isSpeed: false,
                  ),
                  const SizedBox(height: 12),
                  _vsRow(
                    label: context.tr('jitter'),
                    thisVal: displayE.jitter.toDouble(),
                    allVals: chrono.map((e) => e.jitter.toDouble()).toList(),
                    color:   _jitterColor(displayE.jitter, context),
                    unitIdx: unitIdx,
                    t:       t,
                    isSpeed: false,
                  ),
                ]),
              ),
            ],
          ]),
        )),
      ]),
    );
  }

  Widget _vsRow({
    required String label,
    required double thisVal,
    required List<double> allVals,
    required Color color,
    required int unitIdx,
    required ThemeData t,
    required bool isSpeed,
  }) {
    final avg = allVals.reduce((a, b) => a + b) / allVals.length;
    final max = allVals.reduce((a, b) => a > b ? a : b);
    final thisFrac = max > 0 ? (thisVal / max).clamp(0.0, 1.0) : 0.0;
    final avgFrac  = max > 0 ? (avg     / max).clamp(0.0, 1.0) : 0.0;

    String fmt(double v) => isSpeed
        ? formatSpeedValue(v, unitIdx)
        : (v >= 10 ? v.toStringAsFixed(0) : v.toStringAsFixed(1));
    String unit = isSpeed ? kSpeedUnitLabels[unitIdx] : 'ms';

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        SizedBox(
          width: 46,
          child: Text(label, style: TextStyle(
            fontSize:      9,
            fontWeight:    FontWeight.bold,
            letterSpacing: 0.5,
            color:         color.withValues(alpha: 0.7),
          )),
        ),
        Expanded(child: Column(children: [
          // This test bar
          Row(children: [
            Expanded(child: Stack(children: [
              Container(
                height: 6,
                decoration: BoxDecoration(
                  color:        t.colorScheme.onSurface.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              FractionallySizedBox(
                widthFactor: thisFrac,
                child: Container(
                  height: 6,
                  decoration: BoxDecoration(
                    color:        color,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ])),
            const SizedBox(width: 8),
            SizedBox(
              width: 70,
              child: Text('${fmt(thisVal)} $unit',
                  textAlign: TextAlign.right,
                  style: t.textTheme.labelSmall?.copyWith(
                    fontWeight:   FontWeight.w700,
                    color:        color,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    fontSize:     10,
                  )),
            ),
          ]),
          const SizedBox(height: 4),
          // Average bar
          Row(children: [
            Expanded(child: Stack(children: [
              Container(
                height: 4,
                decoration: BoxDecoration(
                  color:        t.colorScheme.onSurface.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              FractionallySizedBox(
                widthFactor: avgFrac,
                child: Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color:        color.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ])),
            const SizedBox(width: 8),
            SizedBox(
              width: 70,
              child: Text('avg ${fmt(avg)} $unit',
                  textAlign: TextAlign.right,
                  style: t.textTheme.labelSmall?.copyWith(
                    fontSize:   9,
                    color:      t.colorScheme.onSurface.withValues(alpha: 0.4),
                    fontFeatures: const [FontFeature.tabularFigures()],
                  )),
            ),
          ]),
        ])),
      ]),
    ]);
  }
}

// ── Interactive trend chart ────────────────────────────────────────────────
class _TrendChart extends StatefulWidget {
  final List<_Entry> entries;   // chronological, oldest first
  final int          selectedIdx;
  final int          metric;    // 0=DL, 1=UL, 2=ping, 3=jitter
  final Color        color;
  final ThemeData    t;
  final ValueChanged<int?> onHover;

  const _TrendChart({
    required this.entries,
    required this.selectedIdx,
    required this.metric,
    required this.color,
    required this.t,
    required this.onHover,
  });

  @override
  State<_TrendChart> createState() => _TrendChartState();
}

class _TrendChartState extends State<_TrendChart> {
  int? _hoverIdx;
  final _chartKey = GlobalKey();

  int _posToIdx(Offset local) {
    final box = _chartKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || widget.entries.length < 2) return 0;
    const padL = 44.0, padR = 12.0;
    final chartW = box.size.width - padL - padR;
    final frac   = ((local.dx - padL) / chartW).clamp(0.0, 1.0);
    return (frac * (widget.entries.length - 1)).round()
        .clamp(0, widget.entries.length - 1);
  }

  void _handleTouch(Offset local) {
    final idx = _posToIdx(local);
    if (idx != _hoverIdx) {
      setState(() => _hoverIdx = idx);
      widget.onHover(idx);
    }
  }

  void _endTouch() {
    setState(() => _hoverIdx = null);
    widget.onHover(null);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown:   (d) => _handleTouch(d.localPosition),
      onTapUp:     (_) => _endTouch(),
      onPanStart:  (d) => _handleTouch(d.localPosition),
      onPanUpdate: (d) => _handleTouch(d.localPosition),
      onPanEnd:    (_) => _endTouch(),
      child: RepaintBoundary(
        key: _chartKey,
        child: CustomPaint(
          painter: _TrendChartPainter(
            entries:     widget.entries,
            selectedIdx: widget.selectedIdx,
            hoverIdx:    _hoverIdx,
            metric:      widget.metric,
            color:       widget.color,
            t:           widget.t,
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class _TrendChartPainter extends CustomPainter {
  final List<_Entry> entries;
  final int          selectedIdx;
  final int?         hoverIdx;
  final int          metric;
  final Color        color;
  final ThemeData    t;

  const _TrendChartPainter({
    required this.entries,
    required this.selectedIdx,
    required this.hoverIdx,
    required this.metric,
    required this.color,
    required this.t,
  });

  double _val(_Entry e) {
    switch (metric) {
      case 0: return e.dl;
      case 1: return e.ul;
      case 2: return e.ping.toDouble();
      default: return e.jitter.toDouble();
    }
  }

  String _fmtVal(double v) =>
      v >= 100 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  @override
  void paint(Canvas canvas, Size size) {
    if (entries.isEmpty) return;

    const padL = 44.0, padR = 14.0, padT = 28.0, padB = 20.0;
    final chartW = size.width  - padL - padR;
    final chartH = size.height - padT - padB;

    final values = entries.map(_val).toList();
    final maxV   = (values.reduce(max) * 1.15).clamp(1.0, double.infinity);
    const minV   = 0.0;
    final range  = maxV - minV;

    double toY(double v) =>
        padT + chartH * (1 - (v - minV) / range);
    double toX(int i) =>
        entries.length <= 1
            ? padL + chartW / 2
            : padL + chartW * i / (entries.length - 1);

    // ── Grid lines ──────────────────────────────────────────────────────────
    final gridPaint = Paint()
      ..color       = t.colorScheme.onSurface.withValues(alpha: 0.06)
      ..strokeWidth = 1;
    for (int g = 0; g <= 4; g++) {
      final y = padT + chartH * g / 4;
      canvas.drawLine(Offset(padL, y), Offset(padL + chartW, y), gridPaint);
    }

    // ── Y-axis labels ────────────────────────────────────────────────────────
    final tp = TextPainter(textDirection: TextDirection.ltr);
    for (int g = 0; g <= 4; g++) {
      final v     = maxV * (4 - g) / 4;
      final label = v >= 1000
          ? '${(v / 1000).toStringAsFixed(1)}G'
          : _fmtVal(v);
      tp.text = TextSpan(
        text:  label,
        style: TextStyle(
          fontSize:   8.5,
          color:      t.colorScheme.onSurface.withValues(alpha: 0.3),
          fontFamily: 'monospace',
        ),
      );
      tp.layout();
      final y = padT + chartH * g / 4;
      tp.paint(canvas,
          Offset(padL - tp.width - 4, y - tp.height / 2));
    }

    if (entries.length < 2) {
      // Single point — just draw a dot
      final x = toX(0), y = toY(values[0]);
      canvas.drawCircle(Offset(x, y), 5, Paint()..color = color);
      return;
    }

    // ── Build bezier path ────────────────────────────────────────────────────
    final linePath = Path();
    linePath.moveTo(toX(0), toY(values[0]));
    for (int i = 1; i < entries.length; i++) {
      final px = toX(i - 1), py = toY(values[i - 1]);
      final cx = toX(i),     cy = toY(values[i]);
      final cpx = (px + cx) / 2;
      linePath.cubicTo(cpx, py, cpx, cy, cx, cy);
    }

    // ── Gradient fill ────────────────────────────────────────────────────────
    final fillPath = Path.from(linePath)
      ..lineTo(toX(entries.length - 1), size.height - padB)
      ..lineTo(padL, size.height - padB)
      ..close();
    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = LinearGradient(
          begin:  Alignment.topCenter,
          end:    Alignment.bottomCenter,
          colors: [
            color.withValues(alpha: 0.3),
            color.withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromLTWH(0, padT, size.width, chartH)),
    );

    // ── Stroke ───────────────────────────────────────────────────────────────
    canvas.drawPath(
      linePath,
      Paint()
        ..style       = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..strokeCap   = StrokeCap.round
        ..strokeJoin  = StrokeJoin.round
        ..color       = color.withValues(alpha: 0.9),
    );

    // ── Data points ──────────────────────────────────────────────────────────
    for (int i = 0; i < entries.length; i++) {
      final x = toX(i), y = toY(values[i]);
      final isSel   = i == selectedIdx;
      final isHover = i == hoverIdx;

      if (isSel) {
        canvas.drawCircle(Offset(x, y), 10,
            Paint()..color = color.withValues(alpha: 0.15));
        canvas.drawCircle(Offset(x, y), 6,
            Paint()..color = color);
        canvas.drawCircle(Offset(x, y), 3,
            Paint()..color = Colors.white);
      } else if (isHover) {
        canvas.drawCircle(Offset(x, y), 7,
            Paint()..color = color.withValues(alpha: 0.25));
        canvas.drawCircle(Offset(x, y), 5,
            Paint()..color = color);
        canvas.drawCircle(Offset(x, y), 2.5,
            Paint()..color = Colors.white);
      } else {
        canvas.drawCircle(Offset(x, y), 3,
            Paint()..color = color.withValues(alpha: 0.6));
        canvas.drawCircle(Offset(x, y), 1.5,
            Paint()..color = t.colorScheme.surface);
      }
    }

    // ── Hover cursor + tooltip ────────────────────────────────────────────────
    if (hoverIdx != null && hoverIdx! < entries.length) {
      final hi = hoverIdx!;
      final hx = toX(hi);
      final hy = toY(values[hi]);

      // Vertical cursor line
      canvas.drawLine(
        Offset(hx, padT),
        Offset(hx, size.height - padB),
        Paint()
          ..color       = color.withValues(alpha: 0.35)
          ..strokeWidth = 1.2,
      );

      // Tooltip background + text
      final label = '${_fmtVal(values[hi])}  •  '
          '${entries[hi].timestamp.length >= 16 ? entries[hi].timestamp.substring(5, 16) : entries[hi].timestamp}';
      tp.text = TextSpan(
        text:  label,
        style: TextStyle(
          fontSize:   10.5,
          color:      t.colorScheme.onSurface,
          fontWeight: FontWeight.w600,
        ),
      );
      tp.layout(maxWidth: 200);

      double tx = (hx - tp.width / 2 - 8).clamp(padL - 2, size.width - tp.width - 18);
      const ty = 3.0;

      final rrect = RRect.fromRectAndRadius(
        Rect.fromLTWH(tx, ty, tp.width + 16, tp.height + 8),
        const Radius.circular(6),
      );
      canvas.drawRRect(
        rrect,
        Paint()..color = t.colorScheme.surface.withValues(alpha: 0.97),
      );
      canvas.drawRRect(
        rrect,
        Paint()
          ..style       = PaintingStyle.stroke
          ..color       = color.withValues(alpha: 0.5)
          ..strokeWidth = 1,
      );
      // Small triangle pointer
      final triPath = Path()
        ..moveTo(hx - 5, ty + tp.height + 8)
        ..lineTo(hx + 5, ty + tp.height + 8)
        ..lineTo(hx, hy - 10)
        ..close();
      canvas.drawPath(triPath,
          Paint()..color = color.withValues(alpha: 0.15));

      tp.paint(canvas, Offset(tx + 8, ty + 4));

      // Value circle at hover point
      canvas.drawCircle(Offset(hx, hy), 4, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(_TrendChartPainter old) =>
      old.entries     != entries      ||
      old.selectedIdx != selectedIdx  ||
      old.hoverIdx    != hoverIdx     ||
      old.metric      != metric       ||
      old.color       != color;
}

// ═══════════════════════════════════════════════════════════════════════════════
// PAINTERS & HELPER WIDGETS (unchanged from original)
// ═══════════════════════════════════════════════════════════════════════════════

class _ArcPainter extends CustomPainter {
  final double speedMbps, maxMbps;
  final Color  trackColor, primary;
  const _ArcPainter({
    required this.speedMbps, required this.maxMbps,
    required this.trackColor, required this.primary,
  });

  static const double _start = 150 * pi / 180;
  static const double _total = 240 * pi / 180;

  @override
  void paint(Canvas canvas, Size size) {
    final cx   = size.width  / 2;
    final cy   = size.height / 2;
    final r    = min(cx, cy) - 10;
    final rect = Rect.fromCircle(center: Offset(cx, cy), radius: r);

    canvas.drawArc(rect, _start, _total, false,
      Paint()
        ..style       = PaintingStyle.stroke
        ..strokeWidth = 9
        ..strokeCap   = StrokeCap.round
        ..color       = trackColor,
    );

    final frac = (speedMbps / maxMbps).clamp(0.0, 1.0);
    if (frac > 0.005) {
      canvas.drawArc(rect, _start, _total * frac, false,
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
        : active ? color : color.withValues(alpha: 0.0);

    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        height: 4,
        child: Stack(fit: StackFit.expand, children: [
          ColoredBox(color: color.withValues(alpha: 0.1)),
          AnimatedFractionallySizedBox(
            duration:    const Duration(milliseconds: 120),
            alignment:   Alignment.centerLeft,
            widthFactor: progress.clamp(0.0, 1.0),
            child:       ColoredBox(color: fillColor),
          ),
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
            gradient: LinearGradient(colors: [
              widget.color.withValues(alpha: 0.0),
              widget.color.withValues(alpha: 0.85),
              widget.color.withValues(alpha: 0.0),
            ]),
          ),
        ),
      ),
    ),
  );
}

class _ChartPainter extends CustomPainter {
  final List<double> points;
  final Color        color;
  final ThemeData    t;
  const _ChartPainter({required this.points, required this.color, required this.t});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    canvas.drawRect(Offset.zero & size, Paint()..color = color.withValues(alpha: 0.03));
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

    final fill = Path.from(line)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(fill, Paint()
      ..shader = LinearGradient(
        begin:  Alignment.topCenter,
        end:    Alignment.bottomCenter,
        colors: [color.withValues(alpha: 0.2), color.withValues(alpha: 0.0)],
      ).createShader(Offset.zero & size));

    canvas.drawPath(line, Paint()
      ..style       = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap   = StrokeCap.round
      ..strokeJoin  = StrokeJoin.round
      ..color       = color.withValues(alpha: 0.8));
  }

  @override
  bool shouldRepaint(_ChartPainter o) => o.points != points || o.color != color;
}

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