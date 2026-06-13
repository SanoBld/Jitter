import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:shared_preferences/shared_preferences.dart';
import '../app_state.dart';
import '../l10n.dart';
import '../services/connection_service.dart';
import '../services/internet_speed_service.dart';
import '../services/location_service.dart';
import 'settings_screen.dart';

// ── Performance grade ──────────────────────────────────────────────────────
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
  final String  timestamp, flag, server, provider, serverLoc, userLoc, unit;
  final double  dl, ul;
  final int     ping, jitter;
  final double? lat, lng; // GPS coordinates of the user at test time
  const _Entry({
    required this.timestamp, required this.flag,   required this.server,
    required this.provider,  required this.serverLoc, required this.userLoc,
    required this.dl,        required this.ul,     required this.ping,
    required this.jitter,    required this.unit,
    this.lat, this.lng,
  });
  Map<String, dynamic> toJson() => {
    'ts': timestamp, 'flag': flag, 'server': server,
    'provider': provider, 'location': serverLoc, 'userLocation': userLoc,
    'dl': dl, 'ul': ul, 'ping': ping, 'jitter': jitter, 'unit': unit,
    if (lat != null) 'lat': lat,
    if (lng != null) 'lng': lng,
  };
  factory _Entry.fromJson(Map<String, dynamic> j) => _Entry(
    timestamp: j['ts']  as String,
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
    lat:       (j['lat'] as num?)?.toDouble(),
    lng:       (j['lng'] as num?)?.toDouble(),
  );
}


String _fmt(int secs) {
  final m = secs ~/ 60, s = secs % 60;
  return '${m.toString().padLeft(2,'0')}:${s.toString().padLeft(2,'0')}';
}

// ══════════════════════════════════════════════════════════════════════════════
// HOME SCREEN
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
  // Phase averages (set at the END of each phase, kept until next test)
  final _dlAvgNf    = ValueNotifier<double>(0);
  final _ulAvgNf    = ValueNotifier<double>(0);
  // Connection info (updated at test start)
  final _connTypNf  = ValueNotifier<String>('');
  final _wifiSsidNf = ValueNotifier<String>('');
  final _localIpNf  = ValueNotifier<String>('');

  // Cumulative average accumulators (reset per phase, not notifiers)
  double _dlSum   = 0; int _dlCount   = 0;
  double _ulSum   = 0; int _ulCount   = 0;
  bool   _stopRequested = false;
  bool   _histShowStats = false; // toggle between list and trend view in History
  Timer? _bgPingTimer;
  Timer? _elapsedTimer;

  late AnimationController _pulse;
  List<_Entry> _history = [];

  @override
  void initState() {
    super.initState();
    _loadHistory();
    _pulse = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _refreshLocations();
  }

  @override
  void dispose() {
    _pulse.dispose();
    _bgPingTimer?.cancel();
    _elapsedTimer?.cancel();
    for (final n in [
      _speedNf,_dlNf,_ulNf,_pingNf,_jitterNf,_testingNf,
      _phaseNf,_progressNf,_dlProgNf,_ulProgNf,_pointsNf,
      _pingHist,_elapsedNf,_errorNf,
      _dlAvgNf,_ulAvgNf,
      _connTypNf,_wifiSsidNf,_localIpNf,
    ]) { n.dispose(); }
    super.dispose();
  }

  // ── Locations ──────────────────────────────────────────────────────────────
  Future<void> _refreshLocations() async {
    await Future.wait([_fetchIpLocation(), _fetchGpsLocation()]);
  }
  Future<void> _fetchIpLocation() async {
    locationFetchingNotifier.value = true;
    try {
      final info = await InternetSpeedService.getLocationAndIsp();
      if (info.location.isNotEmpty) await setIpLocation(info.location);
      if (info.isp.isNotEmpty)      await setIspName(info.isp);
    } finally { locationFetchingNotifier.value = false; }
  }
  Future<void> _fetchGpsLocation() async {
    if (!useGpsLocationNotifier.value) return;
    gpsFetchingNotifier.value = true;
    try {
      final r = await LocationService.getGpsLocation();
      if (r.city.isNotEmpty) await setGpsLocation(r.city, r.lat, r.lng);
    } finally { gpsFetchingNotifier.value = false; }
  }

  // ── History ────────────────────────────────────────────────────────────────
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
        'speed_history', _history.map((e) => json.encode(e.toJson())).toList());
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
  void _startBgPing(int srv) {
    _bgPingTimer?.cancel();
    _bgPingTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (!_testingNf.value) { _stopBgPing(); return; }
      final ms = await _svc.testPing(srv);
      if (ms < 999 && _testingNf.value) {
        _pingNf.value = ms;
        final h = List<int>.from(_pingHist.value)..add(ms);
        if (h.length > 20) h.removeAt(0);
        _pingHist.value = h;
        if (h.length >= 3) {
          final avg  = h.fold(0.0,(a,b)=>a+b) / h.length;
          final vari = h.fold(0.0,(a,b)=>a+pow(b-avg,2)) / h.length;
          _jitterNf.value = sqrt(vari).round();
        }
      }
    });
  }
  void _stopBgPing() { _bgPingTimer?.cancel(); _bgPingTimer = null; }

  // ── Elapsed timer ──────────────────────────────────────────────────────────
  void _startElapsed() {
    _elapsedNf.value = 0;
    _elapsedTimer?.cancel();
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_testingNf.value) { _stopElapsed(); return; }
      _elapsedNf.value++;
    });
  }
  void _stopElapsed() { _elapsedTimer?.cancel(); _elapsedTimer = null; }

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
    _dlSum = 0; _dlCount = 0;
    _ulSum = 0; _ulCount = 0;
    _dlAvgNf.value = 0;
    _ulAvgNf.value = 0;
    _phaseNf.value = 'LOCATING';
    // Fetch connection info (non-blocking)
    ConnectionService.getInfo().then((info) {
      _connTypNf.value  = info.type;
      _wifiSsidNf.value = info.ssid;
      _localIpNf.value  = info.localIp;
    });
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

      bool   ok = false;
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
    // Resolve parallel connections: 0 = Auto → default 4
    final rawConns = parallelConnsNotifier.value;
    final conns    = rawConns <= 0 ? 4 : rawConns;
    final dlDur  = dlDurationSecsNotifier.value;
    final ulDur  = ulDurationSecsNotifier.value;
    final isDlInf = dlDur == 0;
    final isUlInf = ulDur == 0;

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

    // ── Download phase ─────────────────────────────────────────────────────
    _phaseNf.value  = 'DOWNLOAD';
    _dlProgNf.value = 0;
    _pointsNf.value = [];
    _startElapsed();
    Timer? dlTicker;
    if (!isDlInf) {
      final sw = Stopwatch()..start();
      dlTicker = Timer.periodic(const Duration(milliseconds: 150), (_) {
        if (_stopRequested) { dlTicker?.cancel(); return; }
        final frac = (sw.elapsedMilliseconds / (dlDur * 1000)).clamp(0.0, 1.0);
        _dlProgNf.value   = frac;
        _progressNf.value = 0.08 + 0.46 * frac;
      });
    }
    await for (final mbps
        in _svc.testDownloadSpeed(
          serverIndex:         srv,
          durationSecs:        dlDur,
          parallelConnections: conns,
        )) {
      if (_stopRequested) break;
      _speedNf.value = mbps;              // gauge: instantaneous
      _addPoint(mbps);
      _dlSum += mbps; _dlCount++;
      _dlNf.value = _dlSum / _dlCount;   // stats: running average
    }
    dlTicker?.cancel();
    if (_stopRequested) return;
    _progressNf.value = 0.54;
    _dlProgNf.value   = 1.0;
    // Compute and store DL average from accumulated points
    final dlPts = _pointsNf.value;
    if (dlPts.isNotEmpty) {
      _dlAvgNf.value = dlPts.fold(0.0, (a, b) => a + b) / dlPts.length;
    }

    // ── Upload phase ───────────────────────────────────────────────────────
    _phaseNf.value  = 'UPLOAD';
    _ulProgNf.value = 0;
    _speedNf.value  = 0;
    _pointsNf.value = [];
    _startElapsed();
    Timer? ulTicker;
    if (!isUlInf) {
      final sw = Stopwatch()..start();
      ulTicker = Timer.periodic(const Duration(milliseconds: 150), (_) {
        if (_stopRequested) { ulTicker?.cancel(); return; }
        final frac = (sw.elapsedMilliseconds / (ulDur * 1000)).clamp(0.0, 1.0);
        _ulProgNf.value   = frac;
        _progressNf.value = 0.54 + 0.46 * frac;
      });
    }
    _ulSum = 0; _ulCount = 0;
    await for (final mbps in _svc.testUploadSpeed(
      durationSecs:        ulDur,
      parallelConnections: conns,
    )) {
      if (_stopRequested) break;
      _speedNf.value = mbps;              // gauge: instantaneous
      _addPoint(mbps);
      _ulSum += mbps; _ulCount++;
      _ulNf.value = _ulSum / _ulCount;   // stats: running average
    }
    ulTicker?.cancel();
    _stopBgPing();
    _stopElapsed();
    if (_stopRequested) return;

    _progressNf.value = 1.0;
    _ulProgNf.value   = 1.0;
    // Compute and store UL average
    final ulPts = _pointsNf.value;
    if (ulPts.isNotEmpty) {
      _ulAvgNf.value = ulPts.fold(0.0, (a, b) => a + b) / ulPts.length;
    }
    _speedNf.value = _dlNf.value;
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
        lat:       gpsLatNotifier.value,
        lng:       gpsLngNotifier.value,
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
    return LayoutBuilder(builder: (context, constraints) {
      final isWide = constraints.maxWidth >= 600;

      final stack = IndexedStack(
        index: _tab,
        children: [
          _buildDash(t),
          _buildHistory(t),
          _MapScreen(history: _history),
          const SettingsScreen(),
        ],
      );

      // Shared navigation destinations
      final navDests = <({IconData icon, IconData selIcon, String key})>[
        (icon: Icons.speed_outlined,      selIcon: Icons.speed,      key: 'tabTest'),
        (icon: Icons.bar_chart_outlined,  selIcon: Icons.bar_chart,  key: 'tabLogs'),
        (icon: Icons.map_outlined,        selIcon: Icons.map,        key: 'tabMap'),
        (icon: Icons.tune_outlined,       selIcon: Icons.tune,       key: 'tabSettings'),
      ];

      if (isWide) {
        // ── Wide layout: NavigationRail on the left ──────────────────────────
        return Scaffold(
          backgroundColor: t.colorScheme.surface,
          body: SafeArea(
            child: Row(children: [
              NavigationRail(
                selectedIndex:         _tab,
                onDestinationSelected: (i) => setState(() => _tab = i),
                labelType:             NavigationRailLabelType.all,
                backgroundColor:       t.colorScheme.surface,
                indicatorColor:        t.colorScheme.primaryContainer.withValues(alpha: 0.5),
                minWidth:              72,
                destinations: navDests.map((d) => NavigationRailDestination(
                  icon:         Icon(d.icon),
                  selectedIcon: Icon(d.selIcon),
                  label:        Text(context.tr(d.key),
                      style: const TextStyle(fontSize: 11)),
                )).toList(),
              ),
              VerticalDivider(
                thickness: 1, width: 1,
                color: t.colorScheme.onSurface.withValues(alpha: 0.08),
              ),
              Expanded(child: stack),
            ]),
          ),
        );
      }

      // ── Mobile layout: NavigationBar at the bottom ───────────────────────
      return Scaffold(
        backgroundColor: t.colorScheme.surface,
        body: SafeArea(child: stack),
        bottomNavigationBar: NavigationBar(
          selectedIndex:         _tab,
          onDestinationSelected: (i) => setState(() => _tab = i),
          backgroundColor:       t.colorScheme.surface,
          indicatorColor:        t.colorScheme.primaryContainer.withValues(alpha: 0.5),
          destinations: navDests.map((d) => NavigationDestination(
            icon:         Icon(d.icon),
            selectedIcon: Icon(d.selIcon),
            label:        context.tr(d.key),
          )).toList(),
        ),
      );
    });
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // DASHBOARD
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildDash(ThemeData t) => Padding(
    padding: const EdgeInsets.fromLTRB(18, 12, 18, 6),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _topBar(t),
      if (kIsWeb) ...[const SizedBox(height: 6), _webBanner(t)],
      _errorBanner(t),
      Expanded(child: _gauge(t)),
      _phaseBar(t),
      const SizedBox(height: 8),
      _chart(t),
      const SizedBox(height: 10),
      _statsRow(t),
      const SizedBox(height: 8),
      // Compact options bar — fades out while testing
      ValueListenableBuilder<bool>(
        valueListenable: _testingNf,
        builder: (_, testing, __) => AnimatedSize(
          duration: const Duration(milliseconds: 350),
          curve:    Curves.easeInOut,
          child: testing
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _optionsBar(t),
                ),
        ),
      ),
      _startBtn(t),
      const SizedBox(height: 2),
    ]),
  );

  // ── One compact scrollable row with all test options ───────────────────────
  Widget _optionsBar(ThemeData t) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        // Server
        ValueListenableBuilder<int>(
          valueListenable: selectedServerNotifier,
          builder: (_, si, __) {
            final srv = InternetSpeedService.servers[
                InternetSpeedService.resolveServerIndex(si)];
            return _optChip(
              flag:  srv.flag,
              label: '${srv.name}',
              sub:   srv.fileSize,
              onTap: _showServerSheet,
              t:     t,
            );
          },
        ),
        const SizedBox(width: 8),
        // Duration — tap opens sheet
        ValueListenableBuilder<bool>(
          valueListenable: linkDurationsNotifier,
          builder: (_, linked, __) => ValueListenableBuilder<int>(
            valueListenable: dlDurationSecsNotifier,
            builder: (_, dl, __) => ValueListenableBuilder<int>(
              valueListenable: ulDurationSecsNotifier,
              builder: (_, ul, __) => _optChip(
                icon:  Icons.timer_outlined,
                label: linked
                    ? '${_fmtDur(dl)}'
                    : '↓${_fmtDur(dl)}  ↑${_fmtDur(ul)}',
                sub:   linked ? 'DL + UL' : 'Custom',
                onTap: () => _showDurationSheet(t),
                t:     t,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        // Unit — tap to cycle
        ValueListenableBuilder<int>(
          valueListenable: speedUnitIndexNotifier,
          builder: (_, ui, __) => _optChip(
            icon:      Icons.speed_outlined,
            label:     kSpeedUnitLabels[ui],
            sub:       'Unit',
            onTap:     () => setSpeedUnitIndex((ui + 1) % kSpeedUnitLabels.length),
            t:         t,
            primary:   true,
          ),
        ),
        const SizedBox(width: 8),
        // Parallel connections — info only, set in Settings
        ValueListenableBuilder<int>(
          valueListenable: parallelConnsNotifier,
          builder: (_, n, __) => _optChip(
            icon:  Icons.merge_type_rounded,
            label: '${n}× conns',
            sub:   'Settings',
            onTap: () => setState(() => _tab = 3), // go to Settings
            t:     t,
          ),
        ),
      ]),
    );
  }

  Widget _optChip({
    String?       flag,
    IconData?     icon,
    required String label,
    String?       sub,
    VoidCallback? onTap,
    required ThemeData t,
    bool primary = false,
  }) {
    final color = primary ? t.colorScheme.primary : t.colorScheme.onSurface;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        decoration: BoxDecoration(
          color: primary
              ? t.colorScheme.primary.withValues(alpha: 0.08)
              : t.colorScheme.onSurface.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: primary
                ? t.colorScheme.primary.withValues(alpha: 0.3)
                : t.colorScheme.onSurface.withValues(alpha: 0.09),
          ),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (flag != null) ...[
            Text(flag, style: const TextStyle(fontSize: 13)),
            const SizedBox(width: 6),
          ] else if (icon != null) ...[
            Icon(icon, size: 12, color: color.withValues(alpha: 0.55)),
            const SizedBox(width: 5),
          ],
          Column(crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min, children: [
            Text(label, style: t.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: color.withValues(alpha: primary ? 1.0 : 0.75),
            )),
            if (sub != null)
              Text(sub, style: t.textTheme.labelSmall?.copyWith(
                fontSize: 9,
                color: color.withValues(alpha: 0.38),
              )),
          ]),
          if (onTap != null) ...[
            const SizedBox(width: 4),
            Icon(Icons.keyboard_arrow_down_rounded, size: 13,
                color: color.withValues(alpha: 0.28)),
          ],
        ]),
      ),
    );
  }

  String _fmtDur(int s) => s == 0 ? '∞' : s >= 60 ? '${s ~/ 60}m' : '${s}s';

  void _showDurationSheet(ThemeData t) {
    showModalBottomSheet(
      context:            context,
      isScrollControlled: true,
      useSafeArea:        true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Center(child: Container(
            width: 36, height: 4,
            margin: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: t.colorScheme.onSurface.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(2),
            ),
          )),
          Text('Test Duration',
              style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          _dualDurationRow(t),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  // ── Top bar ────────────────────────────────────────────────────────────────
  Widget _topBar(ThemeData t) => Row(children: [
    _gpsChip(t),
    const Spacer(),
    _locationChip(t),
    const SizedBox(width: 8),
    _statusBadge(t),
  ]);

  Widget _gpsChip(ThemeData t) => ValueListenableBuilder<bool>(
    valueListenable: useGpsLocationNotifier,
    builder: (_, useGps, __) {
      if (!useGps) return const SizedBox.shrink();
      return ValueListenableBuilder<String>(
        valueListenable: gpsLocationNotifier,
        builder: (_, city, __) {
          if (city.isEmpty) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color:        t.colorScheme.tertiaryContainer.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: t.colorScheme.tertiary.withValues(alpha: 0.3)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.gps_fixed_rounded, size: 10, color: t.colorScheme.tertiary),
                const SizedBox(width: 4),
                Text(city, style: t.textTheme.labelSmall?.copyWith(
                  fontSize: 9, color: t.colorScheme.onTertiaryContainer,
                  fontWeight: FontWeight.w600,
                )),
              ]),
            ),
          );
        },
      );
    },
  );

  Widget _locationChip(ThemeData t) => ValueListenableBuilder<bool>(
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
              border: Border.all(color: t.colorScheme.secondary.withValues(alpha: 0.2)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              SizedBox(width: 11, height: 11,
                child: fetching
                    ? CircularProgressIndicator(strokeWidth: 1.5, color: t.colorScheme.secondary)
                    : Icon(Icons.language_rounded, size: 11, color: t.colorScheme.secondary),
              ),
              const SizedBox(width: 4),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  fetching ? context.tr('detecting') : loc.isEmpty ? context.tr('unknown') : loc,
                  style: t.textTheme.labelSmall?.copyWith(
                    fontSize: 10, fontWeight: FontWeight.w600,
                    color: fetching || loc.isEmpty
                        ? t.colorScheme.onSurface.withValues(alpha: 0.4)
                        : t.colorScheme.onSecondaryContainer,
                  ),
                ),
                if (isp.isNotEmpty && !fetching)
                  Text(isp, style: t.textTheme.labelSmall?.copyWith(
                    fontSize: 8, color: t.colorScheme.onSurface.withValues(alpha: 0.38),
                  )),
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

  Widget _statusBadge(ThemeData t) => ValueListenableBuilder<bool>(
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
                    ? t.colorScheme.error.withValues(alpha: 0.4 + _pulse.value * 0.6)
                    : phase == 'DONE'
                        ? t.colorScheme.primary.withValues(alpha: 0.4 + _pulse.value * 0.3)
                        : t.colorScheme.onSurface.withValues(alpha: 0.2),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(phaseLabel(phase, context),
              style: t.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.bold, letterSpacing: 0.6, fontSize: 10)),
        ]),
      ),
    ),
  );

  // ── Gauge ──────────────────────────────────────────────────────────────────
  Widget _gauge(ThemeData t) => Center(
    child: LayoutBuilder(builder: (_, box) {
      final size = min(box.maxWidth * 0.88, box.maxHeight).clamp(150.0, 260.0);
      return ValueListenableBuilder<double>(
        valueListenable: _speedNf,
        builder: (_, mbps, __) => ValueListenableBuilder<int>(
          valueListenable: speedUnitIndexNotifier,
          builder: (_, unitIdx, __) {
            final display = convertSpeed(mbps, unitIdx);
            return SizedBox(width: size, height: size,
              child: Stack(alignment: Alignment.center, children: [
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.0, end: mbps),
                  duration: const Duration(milliseconds: 350),
                  curve: Curves.easeOut,
                  builder: (_, v, __) => CustomPaint(
                    size: Size(size, size),
                    painter: _ArcPainter(
                      speedMbps: v, maxMbps: 1000,
                      trackColor: t.colorScheme.onSurface.withValues(alpha: 0.07),
                      primary:    t.colorScheme.primary,
                    ),
                  ),
                ),
                Column(mainAxisSize: MainAxisSize.min, children: [
                  // Main speed value with spring bounce animation
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.0, end: display),
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOutCubic,
                    builder: (_, v, __) {
                      final rawMbps = unitIdx == 0 ? v
                          : unitIdx == 1 ? v * 8
                          : unitIdx == 2 ? v * 1000
                          : v * 8000;
                      return Text(
                        formatSpeedValue(rawMbps, unitIdx),
                        style: t.textTheme.displayMedium?.copyWith(
                          fontWeight: FontWeight.w900, letterSpacing: -2,
                          height: 1.0,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 3),
                  Text(kSpeedUnitLabels[unitIdx],
                      style: t.textTheme.labelSmall?.copyWith(
                        color: t.colorScheme.primary,
                        fontWeight: FontWeight.bold, letterSpacing: 1.5,
                      )),
                  const SizedBox(height: 10),
                  ValueListenableBuilder<int>(
                    valueListenable: selectedServerNotifier,
                    builder: (_, si, __) {
                      final srv = InternetSpeedService.servers[
                          InternetSpeedService.resolveServerIndex(si)];
                      return Column(children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                          decoration: BoxDecoration(
                            color: t.colorScheme.onSurface.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text('${srv.flag}  ${srv.location}  ·  ${srv.provider}',
                              style: t.textTheme.labelSmall?.copyWith(
                                color: t.colorScheme.onSurface.withValues(alpha: 0.4),
                                fontSize: 9.5,
                              )),
                        ),
                        const SizedBox(height: 4),
                        ValueListenableBuilder<String>(
                          valueListenable: ispNameNotifier,
                          builder: (_, isp, __) => isp.isEmpty
                              ? const SizedBox.shrink()
                              : Text('📶  $isp',
                                  style: t.textTheme.labelSmall?.copyWith(
                                    color: t.colorScheme.onSurface.withValues(alpha: 0.28),
                                    fontSize: 9,
                                  )),
                        ),
                        const SizedBox(height: 4),
                        ValueListenableBuilder<String>(
                          valueListenable: _phaseNf,
                          builder: (_, phase, __) => phase == 'DONE'
                              ? ValueListenableBuilder<double>(
                                  valueListenable: _dlNf,
                                  builder: (_, dl, __) {
                                    final g = _gradeFor(dl);
                                    return AnimatedScale(
                                      scale: 1.0, duration: const Duration(milliseconds: 300),
                                      curve: Curves.easeOutBack,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color:  g.color.withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(20),
                                          border: Border.all(color: g.color.withValues(alpha: 0.3)),
                                        ),
                                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                                          Icon(g.icon, size: 11, color: g.color),
                                          const SizedBox(width: 5),
                                          Text(g.labelFor(context), style: TextStyle(
                                            fontSize: 10, fontWeight: FontWeight.w800,
                                            letterSpacing: 1, color: g.color,
                                          )),
                                        ]),
                                      ),
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

  // ── Phase progress bar ─────────────────────────────────────────────────────
  Widget _phaseBar(ThemeData t) => ValueListenableBuilder<String>(
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
              final dlDur = dlDurationSecsNotifier.value;
              final ulDur = ulDurationSecsNotifier.value;
              final isDlInf = dlDur == 0;
              final isUlInf = ulDur == 0;
              final pingDone = ['DOWNLOAD','UPLOAD','DONE','STOPPED'].contains(phase);
              final dlActive = phase == 'DOWNLOAD';
              final dlDone   = ['UPLOAD','DONE','STOPPED'].contains(phase);
              final ulActive = phase == 'UPLOAD';
              final ulDone   = phase == 'DONE';
              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Expanded(flex: 1, child: _SegBar(
                    progress: pingDone ? 1.0 : (phase == 'PING' ? 0.6 : 0.0),
                    active: phase == 'PING', done: pingDone,
                    color: t.colorScheme.tertiary,
                  )),
                  const SizedBox(width: 4),
                  Expanded(flex: 5, child: _SegBar(
                    progress: dlDone ? 1.0 : (dlActive ? dlP : 0.0),
                    active: dlActive, done: dlDone, color: t.colorScheme.primary,
                  )),
                  const SizedBox(width: 4),
                  Expanded(flex: 5, child: _SegBar(
                    progress: ulDone ? 1.0 : (ulActive ? ulP : 0.0),
                    active: ulActive, done: ulDone, color: t.colorScheme.secondary,
                  )),
                ]),
                const SizedBox(height: 7),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  // PING — show value when done
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(ctx.tr('ping'),
                        style: _segLabel(phase == 'PING', pingDone, t, t.colorScheme.tertiary)),
                    if (pingDone && _pingNf.value > 0)
                      ValueListenableBuilder<int>(
                        valueListenable: _pingNf,
                        builder: (_, ms, __) => Text(
                          '$ms ms',
                          style: t.textTheme.labelSmall?.copyWith(
                            fontSize: 8.5, fontWeight: FontWeight.w700,
                            color: t.colorScheme.tertiary.withValues(alpha: 0.7),
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                  ]),
                  // DOWNLOAD — show timer when active, avg when done
                  Column(children: [
                    Text(ctx.tr('dlLabel'),
                        style: _segLabel(dlActive, dlDone, t, t.colorScheme.primary)),
                    if (dlActive && testing)
                      Text(
                        isDlInf ? _fmt(elapsed) : '${_fmt(elapsed)} / ${_fmt(dlDur)}',
                        style: t.textTheme.labelSmall?.copyWith(
                          fontSize: 9,
                          color: t.colorScheme.onSurface.withValues(alpha: 0.32),
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    if (dlDone)
                      ValueListenableBuilder<double>(
                        valueListenable: _dlAvgNf,
                        builder: (_, avg, __) => avg > 0
                            ? ValueListenableBuilder<int>(
                                valueListenable: speedUnitIndexNotifier,
                                builder: (_, ui, __) => Text(
                                  '⌀ ${formatSpeedValue(avg, ui)} ${kSpeedUnitLabels[ui]}',
                                  style: t.textTheme.labelSmall?.copyWith(
                                    fontSize: 8.5, fontWeight: FontWeight.w700,
                                    color: t.colorScheme.primary.withValues(alpha: 0.7),
                                    fontFeatures: const [FontFeature.tabularFigures()],
                                  ),
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                  ]),
                  // UPLOAD — show timer when active, avg when done
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text(ctx.tr('ulLabel'),
                        style: _segLabel(ulActive, ulDone, t, t.colorScheme.secondary)),
                    if (ulActive && testing)
                      Text(
                        isUlInf ? _fmt(elapsed) : '${_fmt(elapsed)} / ${_fmt(ulDur)}',
                        style: t.textTheme.labelSmall?.copyWith(
                          fontSize: 9,
                          color: t.colorScheme.onSurface.withValues(alpha: 0.32),
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    if (ulDone)
                      ValueListenableBuilder<double>(
                        valueListenable: _ulAvgNf,
                        builder: (_, avg, __) => avg > 0
                            ? ValueListenableBuilder<int>(
                                valueListenable: speedUnitIndexNotifier,
                                builder: (_, ui, __) => Text(
                                  '⌀ ${formatSpeedValue(avg, ui)} ${kSpeedUnitLabels[ui]}',
                                  style: t.textTheme.labelSmall?.copyWith(
                                    fontSize: 8.5, fontWeight: FontWeight.w700,
                                    color: t.colorScheme.secondary.withValues(alpha: 0.7),
                                    fontFeatures: const [FontFeature.tabularFigures()],
                                  ),
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                  ]),
                ]),
              ]);
            },
          ),
        ),
      ),
    ),
  );

  TextStyle? _segLabel(bool active, bool done, ThemeData t, Color c) =>
      t.textTheme.labelSmall?.copyWith(
        fontSize: 9.5, fontWeight: active ? FontWeight.w800 : FontWeight.w400,
        letterSpacing: 0.6,
        color: active ? c : done
            ? c.withValues(alpha: 0.5)
            : t.colorScheme.onSurface.withValues(alpha: 0.22),
      );

  // ── Live chart ─────────────────────────────────────────────────────────────
  Widget _chart(ThemeData t) => SizedBox(
    height: 52,
    child: ValueListenableBuilder<List<double>>(
      valueListenable: _pointsNf,
      builder: (_, pts, __) => ValueListenableBuilder<String>(
        valueListenable: _phaseNf,
        builder: (_, phase, __) {
          final color = phase == 'UPLOAD' ? t.colorScheme.secondary : t.colorScheme.primary;
          return ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LayoutBuilder(
              builder: (_, box) => CustomPaint(
                size:    Size(box.maxWidth, box.maxHeight),
                painter: _ChartPainter(points: pts, color: color, t: t),
              ),
            ),
          );
        },
      ),
    ),
  );

  // ── Stats row — animated pop on value change ───────────────────────────────
  Widget _statsRow(ThemeData t) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
    decoration: BoxDecoration(
      color:        t.colorScheme.onSurface.withValues(alpha: 0.04),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: t.colorScheme.onSurface.withValues(alpha: 0.07)),
    ),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
      // Download
      ValueListenableBuilder<double>(
        valueListenable: _dlNf,
        builder: (_, v, __) => ValueListenableBuilder<int>(
          valueListenable: speedUnitIndexNotifier,
          builder: (_, ui, __) => _PopStat(
            icon: Icons.arrow_downward_rounded, label: context.tr('down'),
            value: formatSpeedValue(v, ui), unit: kSpeedUnitLabels[ui],
            iconColor: t.colorScheme.primary, valueColor: t.colorScheme.primary, t: t,
          ),
        ),
      ),
      _divider(t),
      // Upload
      ValueListenableBuilder<double>(
        valueListenable: _ulNf,
        builder: (_, v, __) => ValueListenableBuilder<int>(
          valueListenable: speedUnitIndexNotifier,
          builder: (_, ui, __) => _PopStat(
            icon: Icons.arrow_upward_rounded, label: context.tr('up'),
            value: formatSpeedValue(v, ui), unit: kSpeedUnitLabels[ui],
            iconColor: t.colorScheme.secondary, valueColor: t.colorScheme.secondary, t: t,
          ),
        ),
      ),
      _divider(t),
      // Ping
      ValueListenableBuilder<int>(
        valueListenable: _pingNf,
        builder: (_, v, __) => _PopStat(
          icon: Icons.network_ping_rounded, label: context.tr('ping'),
          value: '$v', unit: 'ms',
          iconColor: t.colorScheme.tertiary, valueColor: _pingColor(v, context), t: t,
        ),
      ),
      _divider(t),
      // Jitter
      ValueListenableBuilder<int>(
        valueListenable: _jitterNf,
        builder: (_, v, __) => _PopStat(
          icon: Icons.waves_rounded, label: context.tr('jitter'),
          value: '$v', unit: 'ms',
          iconColor: t.colorScheme.error, valueColor: _jitterColor(v, context), t: t,
        ),
      ),
    ]),
  );

  Widget _divider(ThemeData t) => Container(
    height: 28, width: 1,
    color: t.colorScheme.onSurface.withValues(alpha: 0.07),
  );

  // ── Connection info row: type, SSID, local IP, external IP ────────────────
  Widget _connInfoRow(ThemeData t) {
    return ValueListenableBuilder<String>(
      valueListenable: _connTypNf,
      builder: (_, type, __) => ValueListenableBuilder<String>(
        valueListenable: _wifiSsidNf,
        builder: (_, ssid, __) => ValueListenableBuilder<String>(
          valueListenable: _localIpNf,
          builder: (_, localIp, __) => ValueListenableBuilder<String>(
            valueListenable: ipLocationNotifier,
            builder: (_, extLoc, __) => ValueListenableBuilder<String>(
              valueListenable: ispNameNotifier,
              builder: (_, isp, __) {
                // Only show when we have at least one piece of info
                final hasAny = type.isNotEmpty || ssid.isNotEmpty ||
                    localIp.isNotEmpty || isp.isNotEmpty;
                if (!hasAny) return const SizedBox.shrink();

                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    if (type.isNotEmpty)
                      _connChip(
                        icon:  type == 'Wi-Fi'
                            ? Icons.wifi_rounded
                            : type == 'Mobile'
                                ? Icons.signal_cellular_alt_rounded
                                : Icons.lan_rounded,
                        label: type,
                        color: t.colorScheme.primary,
                        t:     t,
                      ),
                    if (ssid.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      _connChip(
                        icon:  Icons.router_rounded,
                        label: ssid,
                        color: t.colorScheme.tertiary,
                        t:     t,
                      ),
                    ],
                    if (localIp.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      _connChip(
                        icon:  Icons.devices_rounded,
                        label: localIp,
                        color: t.colorScheme.secondary,
                        t:     t,
                      ),
                    ],
                    if (isp.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      _connChip(
                        icon:  Icons.business_rounded,
                        label: isp,
                        color: t.colorScheme.onSurface.withValues(alpha: 0.5),
                        t:     t,
                      ),
                    ],
                  ]),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _connChip({
    required IconData icon,
    required String   label,
    required Color    color,
    required ThemeData t,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color:        color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border:       Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 10, color: color),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(
              fontSize:   9.5,
              color:      color,
              fontWeight: FontWeight.w600,
            )),
      ]),
    );
  }

  // ── Dual duration row — fully free custom input ───────────────────────────
  Widget _dualDurationRow(ThemeData t) {
    return ValueListenableBuilder<bool>(
      valueListenable: linkDurationsNotifier,
      builder: (_, linked, __) => ValueListenableBuilder<bool>(
        valueListenable: _testingNf,
        builder: (_, testing, __) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Text(context.tr('duration'),
                  style: t.textTheme.labelSmall?.copyWith(
                    color: t.colorScheme.onSurface.withValues(alpha: 0.4),
                    fontWeight: FontWeight.w600,
                  )),
              const Spacer(),
              GestureDetector(
                onTap: testing ? null : () => setLinkDurations(!linked),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: linked
                        ? t.colorScheme.primary.withValues(alpha: 0.1)
                        : t.colorScheme.secondary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: linked
                          ? t.colorScheme.primary.withValues(alpha: 0.3)
                          : t.colorScheme.secondary.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(
                      linked ? Icons.link_rounded : Icons.link_off_rounded,
                      size: 12,
                      color: linked ? t.colorScheme.primary : t.colorScheme.secondary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      linked ? context.tr('linked') : context.tr('custom'),
                      style: t.textTheme.labelSmall?.copyWith(
                        fontSize: 10, fontWeight: FontWeight.w700,
                        color: linked ? t.colorScheme.primary : t.colorScheme.secondary,
                      ),
                    ),
                  ]),
                ),
              ),
            ]),
            const SizedBox(height: 8),
            // DL
            _durationPhaseRow(
              label:    context.tr('dlDuration'),
              notifier: dlDurationSecsNotifier,
              setter:   testing ? null : setDlDuration,
              color:    t.colorScheme.primary,
              t:        t,
            ),
            // UL — only shown when unlinked
            if (!linked) ...[
              const SizedBox(height: 6),
              _durationPhaseRow(
                label:    context.tr('ulDuration'),
                notifier: ulDurationSecsNotifier,
                setter:   testing ? null : setUlDuration,
                color:    t.colorScheme.secondary,
                t:        t,
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Free-input duration row:  [label]  [-5]  [tap-to-edit value]  [+5]  [∞]
  Widget _durationPhaseRow({
    required String                       label,
    required ValueNotifier<int>           notifier,
    required Future<void> Function(int)?  setter,
    required Color                        color,
    required ThemeData                    t,
  }) {
    return ValueListenableBuilder<int>(
      valueListenable: notifier,
      builder: (_, cur, __) {
        final isInf     = cur == 0;
        final canChange = setter != null;
        // Shadow as non-nullable for safe calls below
        final safeSet = setter;

        return Row(children: [
          // Phase label
          SizedBox(
            width: 46,
            child: Text(label,
                style: t.textTheme.labelSmall?.copyWith(
                  fontSize: 10, fontWeight: FontWeight.w700, color: color,
                )),
          ),

          // −5 button
          _durBtn(
            icon:    Icons.remove_rounded,
            color:   color,
            enabled: canChange && !isInf && cur > 1,
            onTap:   () => safeSet!(max(1, cur - 5)),
            t:       t,
          ),
          const SizedBox(width: 4),

          // Value display — tap to type freely
          GestureDetector(
            onTap: canChange ? () => _pickDuration(notifier, safeSet!, color) : null,
            child: AnimatedContainer(
              duration:  const Duration(milliseconds: 180),
              padding:   const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: color.withValues(alpha: 0.35)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(
                  isInf ? '∞' : '$cur',
                  style: t.textTheme.titleSmall?.copyWith(
                    fontWeight:   FontWeight.w800,
                    color:        color,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                if (!isInf) ...[
                  const SizedBox(width: 3),
                  Text('s', style: t.textTheme.labelSmall?.copyWith(
                    fontSize: 10, color: color.withValues(alpha: 0.6),
                  )),
                ],
                const SizedBox(width: 5),
                Icon(Icons.edit_rounded, size: 10,
                    color: color.withValues(alpha: canChange ? 0.45 : 0.2)),
              ]),
            ),
          ),
          const SizedBox(width: 4),

          // +5 button
          _durBtn(
            icon:    Icons.add_rounded,
            color:   color,
            enabled: canChange && !isInf,
            onTap:   () => safeSet!(min(3600, cur + 5)),
            t:       t,
          ),
          const SizedBox(width: 6),

          // ∞ toggle
          GestureDetector(
            onTap: canChange ? () => safeSet!(isInf ? 30 : 0) : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding:  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: isInf
                    ? color.withValues(alpha: 0.12)
                    : t.colorScheme.onSurface.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isInf
                      ? color.withValues(alpha: 0.35)
                      : t.colorScheme.onSurface.withValues(alpha: 0.08),
                ),
              ),
              child: Icon(Icons.all_inclusive_rounded,
                  size: 14,
                  color: isInf
                      ? color
                      : t.colorScheme.onSurface.withValues(alpha: canChange ? 0.35 : 0.15)),
            ),
          ),
        ]);
      },
    );
  }

  Widget _durBtn({
    required IconData              icon,
    required Color                 color,
    required bool                  enabled,
    required VoidCallback          onTap,
    required ThemeData             t,
  }) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 32, height: 32,
        decoration: BoxDecoration(
          color:        t.colorScheme.onSurface.withValues(alpha: enabled ? 0.06 : 0.03),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: t.colorScheme.onSurface.withValues(alpha: enabled ? 0.10 : 0.04)),
        ),
        child: Icon(icon, size: 14,
            color: enabled
                ? color.withValues(alpha: 0.8)
                : t.colorScheme.onSurface.withValues(alpha: 0.18)),
      ),
    );
  }

  /// Dialog for fully free text input of duration in seconds
  Future<void> _pickDuration(
    ValueNotifier<int>          notifier,
    Future<void> Function(int)  setter,
    Color                       color,
  ) async {
    final t    = Theme.of(context);
    final cur  = notifier.value;
    final ctrl = TextEditingController(text: cur == 0 ? '' : '$cur');
    ctrl.selection = TextSelection(baseOffset: 0, extentOffset: ctrl.text.length);

    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Duration (seconds)',
            style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Enter any value from 1 to 3600 s,\nor leave empty for ∞ (infinite).',
              style: t.textTheme.bodySmall?.copyWith(
                  color: t.colorScheme.onSurface.withValues(alpha: 0.5))),
          const SizedBox(height: 16),
          TextField(
            controller:     ctrl,
            autofocus:      true,
            keyboardType:   TextInputType.number,
            textAlign:      TextAlign.center,
            style:          t.textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.w800, color: color),
            decoration: InputDecoration(
              suffix: Text('s', style: TextStyle(
                  color: color.withValues(alpha: 0.5), fontSize: 16)),
              hintText: '∞',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: color, width: 2),
              ),
            ),
          ),
          const SizedBox(height: 10),
          // Quick preset chips
          Wrap(spacing: 6, children: [
            for (final s in [5, 10, 15, 20, 30, 45, 60, 90, 120])
              ActionChip(
                label:      Text('${s}s'),
                onPressed:  () => Navigator.pop(ctx, s),
                visualDensity: VisualDensity.compact,
                backgroundColor: color.withValues(alpha: 0.1),
                side: BorderSide(color: color.withValues(alpha: 0.3)),
                labelStyle: TextStyle(
                    color: color, fontWeight: FontWeight.w600, fontSize: 11),
              ),
          ]),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child:     const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: color),
            onPressed: () {
              final txt = ctrl.text.trim();
              if (txt.isEmpty) {
                Navigator.pop(ctx, 0); // infinite
              } else {
                final v = int.tryParse(txt);
                if (v != null && v >= 1) {
                  Navigator.pop(ctx, v.clamp(1, 3600));
                }
              }
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );

    if (result != null) { await setter(result); }
  }

  // ── Quick options: server + unit ───────────────────────────────────────────
  Widget _quickOptions(ThemeData t) => ValueListenableBuilder<bool>(
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
                border: Border.all(color: t.colorScheme.onSurface.withValues(alpha: 0.09)),
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
      ValueListenableBuilder<int>(
        valueListenable: speedUnitIndexNotifier,
        builder: (_, unitIdx, __) => Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(kSpeedUnitLabels.length, (i) => Padding(
            padding: EdgeInsets.only(left: i == 0 ? 0 : 4),
            child: _unitChip(
              kSpeedUnitLabels[i], unitIdx == i,
              testing ? null : () => setSpeedUnitIndex(i), t,
            ),
          )),
        ),
      ),
    ]),
  );

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
                fontSize: 10, fontWeight: sel ? FontWeight.w800 : FontWeight.w400,
                color: sel
                    ? t.colorScheme.primary
                    : t.colorScheme.onSurface.withValues(alpha: onTap == null ? 0.18 : 0.5),
              )),
        ),
      );

  void _showServerSheet() {
    showModalBottomSheet(
      context: context, isScrollControlled: true, useSafeArea: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) {
        final t       = Theme.of(ctx);
        final servers = InternetSpeedService.availableServers;
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Center(child: Container(
              width: 36, height: 4, margin: const EdgeInsets.only(bottom: 18),
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
                    value: v, onChanged: setAutoFallback,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ]),
              ),
            ]),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.55),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount:  servers.length,
                separatorBuilder: (_, __) => Divider(
                    height: 1, color: t.colorScheme.onSurface.withValues(alpha: 0.07)),
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
                        subtitle: Text(
                            '${srv.location}  ·  ${srv.provider}\n${srv.fileSize}',
                            style: t.textTheme.bodySmall?.copyWith(
                                color: t.colorScheme.onSurface.withValues(alpha: 0.45))),
                        trailing: sel
                            ? Icon(Icons.check_circle_rounded, color: t.colorScheme.primary)
                            : srv.minConnections >= 8
                                ? Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: t.colorScheme.tertiaryContainer.withValues(alpha: 0.5),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text('${srv.minConnections}×',
                                        style: t.textTheme.labelSmall?.copyWith(
                                          fontSize: 9,
                                          color: t.colorScheme.tertiary,
                                          fontWeight: FontWeight.w700,
                                        )),
                                  )
                                : null,
                        selected: sel,
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
  Widget _startBtn(ThemeData t) => ValueListenableBuilder<bool>(
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
                SizedBox(width: 14, height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2,
                      color: t.colorScheme.error.withValues(alpha: 0.5))),
                const SizedBox(width: 12),
                Text(context.tr('stop'), style: TextStyle(
                  fontWeight: FontWeight.bold, letterSpacing: 2.0,
                  color: t.colorScheme.error.withValues(alpha: 0.85),
                )),
              ]),
            )
          : FilledButton(
              onPressed: _runTest,
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100))),
              child: Text(context.tr('startTest'),
                  style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 2.0)),
            ),
    ),
  );

  // ── Banners ────────────────────────────────────────────────────────────────
  Widget _webBanner(ThemeData t) => Container(
    margin: const EdgeInsets.only(bottom: 6),
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
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color:        t.colorScheme.errorContainer.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: t.colorScheme.error.withValues(alpha: 0.4)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.wifi_off_rounded, size: 16, color: t.colorScheme.error),
          const SizedBox(width: 10),
          Expanded(child: Text(err, style: t.textTheme.bodySmall?.copyWith(
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
                '${_history.length} test${_history.length > 1 ? 's' : ''}  ·  ${groups.length} loc.',
                style: t.textTheme.bodySmall?.copyWith(
                    color: t.colorScheme.onSurface.withValues(alpha: 0.4)),
              ),
          ]),
          const Spacer(),
          // List / Stats toggle
          if (_history.length >= 2)
            Container(
              decoration: BoxDecoration(
                color:        t.colorScheme.onSurface.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: t.colorScheme.onSurface.withValues(alpha: 0.08)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                _viewToggleChip(
                  label:    context.tr('tabLogs'),
                  icon:     Icons.list_rounded,
                  selected: !_histShowStats,
                  onTap:    () => setState(() => _histShowStats = false),
                  t:        t,
                ),
                _viewToggleChip(
                  label:    context.tr('trend'),
                  icon:     Icons.show_chart_rounded,
                  selected: _histShowStats,
                  onTap:    () => setState(() => _histShowStats = true),
                  t:        t,
                ),
              ]),
            ),
          if (_history.isNotEmpty) ...[
            IconButton(
              icon: const Icon(Icons.file_download_outlined, size: 18),
              tooltip: context.tr('exportCsv'),
              onPressed: _exportToFile,
              color: t.colorScheme.secondary,
              visualDensity: VisualDensity.compact,
            ),
          ],
          IconButton(
            icon: const Icon(Icons.file_upload_outlined, size: 18),
            tooltip: 'Import CSV',
            onPressed: _importData,
            color: t.colorScheme.tertiary,
            visualDensity: VisualDensity.compact,
          ),
          if (_history.isNotEmpty)
            TextButton.icon(
              onPressed: _confirmClear,
              icon:  const Icon(Icons.delete_sweep_outlined, size: 15),
              label: Text(context.tr('clearAll')),
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
              : _histShowStats
                  ? _HistoryStatsView(history: _history, t: t)
                  : ListView(children: [
                      for (final g in groups.entries)
                        _locationGroup(g.key, g.value, t),
                      const SizedBox(height: 12),
                    ]),
        ),
      ]),
    );
  }

  Widget _viewToggleChip({
    required String    label,
    required IconData  icon,
    required bool      selected,
    required VoidCallback onTap,
    required ThemeData t,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color:        selected
              ? t.colorScheme.primary.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 12,
              color: selected
                  ? t.colorScheme.primary
                  : t.colorScheme.onSurface.withValues(alpha: 0.4)),
          const SizedBox(width: 4),
          Text(label, style: t.textTheme.labelSmall?.copyWith(
            fontSize:   10,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
            color:      selected
                ? t.colorScheme.primary
                : t.colorScheme.onSurface.withValues(alpha: 0.45),
          )),
        ]),
      ),
    );
  }

  // ── CSV export/import (build, copy, parse) ────────────────────────────────
  String _buildCsv() {
    final buf = StringBuffer('\uFEFF'); // UTF-8 BOM so Excel reads it correctly
    buf.writeln('timestamp,flag,server,provider,server_location,'
        'user_location,download_mbps,upload_mbps,ping_ms,jitter_ms,unit,lat,lng');
    for (final e in _history) {
      buf.writeln([
        e.timestamp, e.flag, e.server, e.provider,
        '"${e.serverLoc.replaceAll('"','""')}"',
        '"${e.userLoc.replaceAll('"','""')}"',
        e.dl.toStringAsFixed(2), e.ul.toStringAsFixed(2),
        e.ping, e.jitter, e.unit,
        e.lat ?? '', e.lng ?? '',
      ].join(','));
    }
    return buf.toString();
  }

  Future<void> _exportToFile() async {
    if (_history.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('exportEmpty'))));
      return;
    }
    await Clipboard.setData(ClipboardData(text: _buildCsv()));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(context.tr('exportCopied')),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  Future<void> _importData() async {
    final ctrl = TextEditingController();

    // Pre-fill clipboard if it looks like a Jitter CSV
    try {
      final clip = await Clipboard.getData('text/plain');
      final text = clip?.text ?? '';
      if (text.contains('download_mbps') || text.contains('timestamp')) {
        ctrl.text = text;
      }
    } catch (_) {}

    if (!mounted) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final t = Theme.of(ctx);
        return AlertDialog(
          title: const Text('Import CSV'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(
              'Paste a previously exported Jitter CSV.\n'
              'Existing entries with the same timestamp are skipped.',
              style: t.textTheme.bodySmall?.copyWith(
                  color: t.colorScheme.onSurface.withValues(alpha: 0.55)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller:  ctrl,
              maxLines:    6,
              style:       const TextStyle(fontSize: 11, fontFamily: 'monospace'),
              decoration:  InputDecoration(
                border:      OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                hintText:    'timestamp,flag,server,…',
                hintStyle:   TextStyle(
                    fontSize: 11,
                    color: t.colorScheme.onSurface.withValues(alpha: 0.3)),
                contentPadding: const EdgeInsets.all(10),
              ),
            ),
          ]),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child:     Text(context.tr('cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child:     const Text('Import'),
            ),
          ],
        );
      },
    );

    if (ok != true || ctrl.text.trim().isEmpty) return;
    await _parseCsvAndImport(ctrl.text);
  }

  Future<void> _parseCsvAndImport(String csv) async {
    // Strip UTF-8 BOM if present
    final raw = csv.startsWith('\uFEFF') ? csv.substring(1) : csv;
    final lines = raw.split('\n').map((l) => l.trim()).toList();
    if (lines.isEmpty) return;

    // Skip header row if present
    final startIdx = lines.first.toLowerCase().contains('timestamp') ? 1 : 0;

    final imported = <_Entry>[];
    for (final line in lines.skip(startIdx)) {
      if (line.isEmpty) continue;
      try {
        final cols = _splitCsvLine(line);
        if (cols.length < 10) continue;
        imported.add(_Entry(
          timestamp: cols[0],
          flag:      cols[1],
          server:    cols[2],
          provider:  cols.length > 3  ? cols[3]  : '',
          serverLoc: cols.length > 4  ? cols[4]  : '',
          userLoc:   cols.length > 5  ? cols[5]  : '',
          dl:        double.tryParse(cols[6]) ?? 0,
          ul:        double.tryParse(cols[7]) ?? 0,
          ping:      int.tryParse(cols[8])    ?? 0,
          jitter:    int.tryParse(cols[9])    ?? 0,
          unit:      cols.length > 10 ? cols[10] : 'Mb/s',
          lat:       cols.length > 11 ? double.tryParse(cols[11]) : null,
          lng:       cols.length > 12 ? double.tryParse(cols[12]) : null,
        ));
      } catch (_) { continue; }
    }

    if (imported.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No valid entries found.')));
      }
      return;
    }

    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Import data'),
        content: Text(
            'Found ${imported.length} test(s).\n'
            'Add them to your ${_history.length} existing result(s)?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child:     Text(context.tr('cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child:     const Text('Import')),
        ],
      ),
    );
    if (ok != true) return;

    final seen = <String>{
      for (final e in _history) '${e.timestamp}_${e.server}',
    };
    int added = 0;
    for (final e in imported) {
      final key = '${e.timestamp}_${e.server}';
      if (!seen.contains(key)) {
        _history.add(e);
        seen.add(key);
        added++;
      }
    }
    _history.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    setState(() {});
    await _saveHistory();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('$added new result(s) imported.'),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  /// Splits a single CSV line respecting double-quoted fields.
  List<String> _splitCsvLine(String line) {
    final result = <String>[];
    final buf    = StringBuffer();
    bool inQuote = false;
    for (int i = 0; i < line.length; i++) {
      final c = line[i];
      if (c == '"') {
        if (inQuote && i + 1 < line.length && line[i + 1] == '"') {
          buf.write('"'); i++; // escaped quote
        } else {
          inQuote = !inQuote;
        }
      } else if (c == ',' && !inQuote) {
        result.add(buf.toString().trim()); buf.clear();
      } else {
        buf.write(c);
      }
    }
    result.add(buf.toString().trim());
    return result;
  }

  Widget _locationGroup(String loc, List<({_Entry e, int i})> items, ThemeData t) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
                  color: t.colorScheme.primary, fontWeight: FontWeight.w800, letterSpacing: 0.4,
                )),
              ]),
            ),
            const SizedBox(width: 8),
            Expanded(child: Divider(color: t.colorScheme.onSurface.withValues(alpha: 0.08))),
            const SizedBox(width: 8),
            Text('${items.length} test${items.length > 1 ? 's' : ''}',
                style: t.textTheme.labelSmall?.copyWith(
                    color: t.colorScheme.onSurface.withValues(alpha: 0.35))),
          ]),
        ),
        ...items.map((r) => _entryCard(r.e, r.i, t)),
      ]);

  Widget _entryCard(_Entry e, int idx, ThemeData t) {
    final grade = _gradeFor(e.dl);
    final ui    = speedUnitIndexNotifier.value;
    return Dismissible(
      key:       ValueKey('${e.timestamp}_$idx'),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => _deleteEntry(idx),
      background: Container(
        alignment: Alignment.centerRight,
        padding:   const EdgeInsets.only(right: 22),
        margin:    const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color:        t.colorScheme.errorContainer.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Icon(Icons.delete_sweep_rounded, color: t.colorScheme.error, size: 22),
      ),
      child: GestureDetector(
        onTap: () => _showEntryDetail(e),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color:        t.colorScheme.surface,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color:      t.colorScheme.shadow.withValues(alpha: 0.05),
                blurRadius: 10,
                offset:     const Offset(0, 2),
              ),
            ],
            border: Border.all(
                color: t.colorScheme.onSurface.withValues(alpha: 0.07)),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: IntrinsicHeight(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                // Grade colour bar on left edge
                Container(width: 5, color: grade.color),

                // Main content
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 11, 14, 11),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      // Top row: grade badge + timestamp
                      Row(children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color:        grade.color.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(grade.icon, size: 10, color: grade.color),
                            const SizedBox(width: 4),
                            Text(grade.labelFor(context), style: TextStyle(
                              fontSize:   9,
                              fontWeight: FontWeight.w700,
                              color:      grade.color,
                              letterSpacing: 0.4,
                            )),
                          ]),
                        ),
                        const Spacer(),
                        if (e.lat != null)
                          Padding(
                            padding: const EdgeInsets.only(right: 5),
                            child: Icon(Icons.location_on_rounded, size: 10,
                                color: t.colorScheme.tertiary.withValues(alpha: 0.5)),
                          ),
                        Text(e.timestamp, style: t.textTheme.labelSmall?.copyWith(
                          color:    t.colorScheme.onSurface.withValues(alpha: 0.35),
                          fontSize: 9.5,
                        )),
                      ]),
                      const SizedBox(height: 9),

                      // Speed metrics row
                      Row(children: [
                        // DL
                        Expanded(child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text('↓  DOWN', style: TextStyle(
                            fontSize: 8, fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                            color: t.colorScheme.primary.withValues(alpha: 0.55),
                          )),
                          const SizedBox(height: 2),
                          RichText(text: TextSpan(children: [
                            TextSpan(
                              text: formatSpeedValue(e.dl, ui),
                              style: t.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                                color:      t.colorScheme.primary,
                                fontFeatures: const [FontFeature.tabularFigures()],
                              ),
                            ),
                            TextSpan(
                              text: ' ${kSpeedUnitLabels[ui]}',
                              style: t.textTheme.labelSmall?.copyWith(
                                fontSize: 9,
                                color: t.colorScheme.primary.withValues(alpha: 0.55),
                              ),
                            ),
                          ])),
                        ])),

                        // UL
                        Expanded(child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text('↑  UP', style: TextStyle(
                            fontSize: 8, fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                            color: t.colorScheme.secondary.withValues(alpha: 0.55),
                          )),
                          const SizedBox(height: 2),
                          RichText(text: TextSpan(children: [
                            TextSpan(
                              text: formatSpeedValue(e.ul, ui),
                              style: t.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                                color:      t.colorScheme.secondary,
                                fontFeatures: const [FontFeature.tabularFigures()],
                              ),
                            ),
                            TextSpan(
                              text: ' ${kSpeedUnitLabels[ui]}',
                              style: t.textTheme.labelSmall?.copyWith(
                                fontSize: 9,
                                color: t.colorScheme.secondary.withValues(alpha: 0.55),
                              ),
                            ),
                          ])),
                        ])),

                        // Ping
                        Column(crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                          Text('PING', style: TextStyle(
                            fontSize: 8, fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                            color: _pingColor(e.ping, context).withValues(alpha: 0.6),
                          )),
                          const SizedBox(height: 2),
                          Text('${e.ping} ms',
                              style: t.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                            color:      _pingColor(e.ping, context),
                            fontFeatures: const [FontFeature.tabularFigures()],
                          )),
                        ]),
                        const SizedBox(width: 14),
                        // Jitter
                        Column(crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                          Text('JITTER', style: TextStyle(
                            fontSize: 8, fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                            color: _jitterColor(e.jitter, context).withValues(alpha: 0.6),
                          )),
                          const SizedBox(height: 2),
                          Text('${e.jitter} ms',
                              style: t.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                            color:      _jitterColor(e.jitter, context),
                            fontFeatures: const [FontFeature.tabularFigures()],
                          )),
                        ]),
                        const SizedBox(width: 2),
                        Icon(Icons.chevron_right_rounded, size: 15,
                            color: t.colorScheme.onSurface.withValues(alpha: 0.2)),
                      ]),
                      const SizedBox(height: 7),

                      // Footer: server + location
                      Row(children: [
                        Text('${e.flag}  ${e.server}',
                            style: t.textTheme.labelSmall?.copyWith(
                              fontSize: 9.5,
                              color: t.colorScheme.onSurface.withValues(alpha: 0.38),
                            )),
                        if (e.userLoc.isNotEmpty) ...[
                          Text('  ·  ', style: TextStyle(
                              color: t.colorScheme.onSurface.withValues(alpha: 0.2),
                              fontSize: 9)),
                          Icon(Icons.place_rounded, size: 9,
                              color: t.colorScheme.onSurface.withValues(alpha: 0.28)),
                          const SizedBox(width: 2),
                          Flexible(child: Text(e.userLoc,
                              overflow: TextOverflow.ellipsis,
                              style: t.textTheme.labelSmall?.copyWith(
                                fontSize: 9.5,
                                color: t.colorScheme.onSurface.withValues(alpha: 0.38),
                              ))),
                        ],
                      ]),
                    ]),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  void _showEntryDetail(_Entry entry) {
    showModalBottomSheet(
      context: context, isScrollControlled: true, useSafeArea: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _EntryDetailSheet(entry: entry, history: _history),
    );
  }

  void _confirmClear() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title:   Text(context.tr('clearHistory')),
        content: Text(context.tr('clearHistoryBody')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(context.tr('cancel'))),
          FilledButton(
            onPressed: () async { Navigator.pop(ctx); await _clearHistory(); },
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            child: Text(context.tr('deleteAll')),
          ),
        ],
      ),
    );
  }

  Widget _emptyState(ThemeData t) => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.bar_chart_outlined, size: 52,
          color: t.colorScheme.onSurface.withValues(alpha: 0.13)),
      const SizedBox(height: 14),
      Text(context.tr('noTests'), style: t.textTheme.titleSmall?.copyWith(
        color: t.colorScheme.onSurface.withValues(alpha: 0.35), fontWeight: FontWeight.w600,
      )),
      const SizedBox(height: 4),
      Text(context.tr('noTestsHint'), style: t.textTheme.bodySmall?.copyWith(
        color: t.colorScheme.onSurface.withValues(alpha: 0.22),
      )),
    ]),
  );
} // end _HomeScreenState


// ═══════════════════════════════════════════════════════════════════════════════
// HISTORY STATS VIEW — trend charts across all history entries
// ═══════════════════════════════════════════════════════════════════════════════
class _HistoryStatsView extends StatefulWidget {
  final List<_Entry> history;
  final ThemeData    t;
  const _HistoryStatsView({required this.history, required this.t});
  @override
  State<_HistoryStatsView> createState() => _HistoryStatsViewState();
}

class _HistoryStatsViewState extends State<_HistoryStatsView> {
  int  _metric   = 0;
  int? _hoverIdx;

  List<_Entry> get _chrono => widget.history.reversed.toList();

  Color _mc(int m) {
    final t = widget.t;
    switch (m) {
      case 0:  return t.colorScheme.primary;
      case 1:  return t.colorScheme.secondary;
      case 2:  return t.colorScheme.tertiary;
      default: return t.colorScheme.error;
    }
  }

  static const _icons = [
    Icons.arrow_downward_rounded, Icons.arrow_upward_rounded,
    Icons.network_ping_rounded,   Icons.waves_rounded,
  ];
  static const _keys = ['down', 'up', 'ping', 'jitter'];

  @override
  Widget build(BuildContext context) {
    final t      = widget.t;
    final chrono = _chrono;
    final ui     = speedUnitIndexNotifier.value;
    final hover  = _hoverIdx != null && _hoverIdx! < chrono.length
        ? chrono[_hoverIdx!]
        : null;

    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Summary stats
        Row(children: List.generate(4, (m) {
          final color = _mc(m);
          final vals  = chrono.map((e) {
            switch (m) {
              case 0:  return e.dl;
              case 1:  return e.ul;
              case 2:  return e.ping.toDouble();
              default: return e.jitter.toDouble();
            }
          }).toList();
          final avg = vals.reduce((a, b) => a + b) / vals.length;
          final mx  = vals.reduce((a, b) => a > b ? a : b);
          final mn  = vals.reduce((a, b) => a < b ? a : b);
          final dispVal = m < 2
              ? formatSpeedValue(avg, ui)
              : avg.toStringAsFixed(0);
          final unit = m < 2 ? kSpeedUnitLabels[ui] : 'ms';
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _metric = m),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                margin: EdgeInsets.only(right: m < 3 ? 8 : 0, bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: m == _metric
                      ? color.withValues(alpha: 0.1)
                      : t.colorScheme.onSurface.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: m == _metric
                        ? color.withValues(alpha: 0.35)
                        : t.colorScheme.onSurface.withValues(alpha: 0.07),
                    width: m == _metric ? 1.5 : 1,
                  ),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(_icons[m], size: 12, color: color.withValues(alpha: 0.7)),
                  const SizedBox(height: 6),
                  Text('⌀ $dispVal', style: t.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800, color: color, height: 1,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  )),
                  Text(unit, style: TextStyle(fontSize: 8, color: color.withValues(alpha: 0.6))),
                  const SizedBox(height: 4),
                  Text(
                    m < 2
                        ? '↑${formatSpeedValue(mx, ui)}  ↓${formatSpeedValue(mn, ui)}'
                        : '↑${mx.toStringAsFixed(0)}  ↓${mn.toStringAsFixed(0)} ms',
                    style: t.textTheme.labelSmall?.copyWith(
                      fontSize: 8.5,
                      color: t.colorScheme.onSurface.withValues(alpha: 0.38),
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ]),
              ),
            ),
          );
        })),

        // Metric selector tabs
        SizedBox(height: 28, child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: 4,
          separatorBuilder: (_, __) => const SizedBox(width: 6),
          itemBuilder: (_, m) {
            final sel   = m == _metric;
            final color = _mc(m);
            return GestureDetector(
              onTap: () => setState(() { _metric = m; _hoverIdx = null; }),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: sel ? color.withValues(alpha: 0.12) : t.colorScheme.onSurface.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: sel ? color.withValues(alpha: 0.4) : t.colorScheme.onSurface.withValues(alpha: 0.08)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(_icons[m], size: 10, color: color.withValues(alpha: sel ? 1.0 : 0.5)),
                  const SizedBox(width: 4),
                  Text(context.tr(_keys[m]), style: t.textTheme.labelSmall?.copyWith(
                    fontSize: 10,
                    fontWeight: sel ? FontWeight.w700 : FontWeight.w400,
                    color: sel ? color : t.colorScheme.onSurface.withValues(alpha: 0.5),
                  )),
                ]),
              ),
            );
          },
        )),
        const SizedBox(height: 10),

        // Hover timestamp
        if (hover != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(hover.timestamp, style: t.textTheme.labelSmall?.copyWith(
              color: t.colorScheme.onSurface.withValues(alpha: 0.45))),
          ),

        // Interactive trend chart
        Container(
          height: 200,
          decoration: BoxDecoration(
            color:        t.colorScheme.onSurface.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: t.colorScheme.onSurface.withValues(alpha: 0.06)),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: _TrendChart(
              entries:     chrono,
              selectedIdx: chrono.length - 1,
              metric:      _metric,
              color:       _mc(_metric),
              t:           t,
              onHover:     (idx) => setState(() => _hoverIdx = idx),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(chrono.first.timestamp.length >= 10 ? chrono.first.timestamp.substring(5, 10) : '',
              style: t.textTheme.labelSmall?.copyWith(fontSize: 9, color: t.colorScheme.onSurface.withValues(alpha: 0.3))),
          Text('${chrono.length} tests',
              style: t.textTheme.labelSmall?.copyWith(fontSize: 9, color: t.colorScheme.onSurface.withValues(alpha: 0.3))),
          Text(chrono.last.timestamp.length >= 10 ? chrono.last.timestamp.substring(5, 10) : '',
              style: t.textTheme.labelSmall?.copyWith(fontSize: 9, color: t.colorScheme.onSurface.withValues(alpha: 0.3))),
        ]),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// ANIMATED POP STAT — numbers slide+scale in when value changes
// ═══════════════════════════════════════════════════════════════════════════════
class _PopStat extends StatefulWidget {
  final IconData  icon;
  final String    label, value, unit;
  final Color     iconColor, valueColor;
  final ThemeData t;
  const _PopStat({
    required this.icon,   required this.label,      required this.value,
    required this.unit,   required this.iconColor,  required this.valueColor,
    required this.t,
  });
  @override
  State<_PopStat> createState() => _PopStatState();
}

class _PopStatState extends State<_PopStat> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double>   _scale;
  late Animation<double>   _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 380));
    _scale   = TweenSequence([
      TweenSequenceItem(tween: Tween(begin: 0.75, end: 1.14)
          .chain(CurveTween(curve: Curves.easeOut)),   weight: 45),
      TweenSequenceItem(tween: Tween(begin: 1.14, end: 1.0)
          .chain(CurveTween(curve: Curves.easeInOut)), weight: 55),
    ]).animate(_ctrl);
    _opacity = Tween(begin: 0.0, end: 1.0)
        .chain(CurveTween(curve: const Interval(0, 0.4, curve: Curves.easeOut)))
        .animate(_ctrl);
  }

  @override
  void didUpdateWidget(_PopStat old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value && widget.value != '0') {
      _ctrl.forward(from: 0);
    }
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(widget.icon, size: 10, color: widget.iconColor.withValues(alpha: 0.7)),
        const SizedBox(width: 3),
        Text(widget.label, style: TextStyle(
          fontSize: 8.5, fontWeight: FontWeight.bold, letterSpacing: 0.8,
          color: widget.iconColor.withValues(alpha: 0.65),
        )),
      ]),
      const SizedBox(height: 4),
      AnimatedBuilder(
        animation: _ctrl,
        builder: (_, child) => Transform.scale(
          scale:   _ctrl.isAnimating ? _scale.value : 1.0,
          child:   Opacity(
            opacity: _ctrl.isAnimating ? _opacity.value.clamp(0.0, 1.0) : 1.0,
            child:   child,
          ),
        ),
        child: RichText(
          text: TextSpan(children: [
            TextSpan(text: widget.value,
              style: t.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800, color: widget.valueColor,
                height: 1.0,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            TextSpan(text: ' ${widget.unit}',
              style: t.textTheme.labelSmall?.copyWith(
                fontSize: 8.5, color: widget.valueColor.withValues(alpha: 0.6),
              ),
            ),
          ]),
        ),
      ),
    ]);
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// ENTRY DETAIL SHEET — trend chart + OSM map
// ═══════════════════════════════════════════════════════════════════════════════
class _EntryDetailSheet extends StatefulWidget {
  final _Entry       entry;
  final List<_Entry> history;
  const _EntryDetailSheet({required this.entry, required this.history});
  @override
  State<_EntryDetailSheet> createState() => _EntryDetailSheetState();
}

class _EntryDetailSheetState extends State<_EntryDetailSheet> {
  int  _metric   = 0;
  int? _hoverIdx;

  List<_Entry> get _chrono => widget.history.reversed.toList();
  int get _selectedIdx {
    final i = _chrono.indexOf(widget.entry);
    return i < 0 ? _chrono.length - 1 : i;
  }
  _Entry get _displayEntry =>
      (_hoverIdx != null && _hoverIdx! < _chrono.length)
          ? _chrono[_hoverIdx!]
          : widget.entry;

  static const _metricIcons = [
    Icons.arrow_downward_rounded, Icons.arrow_upward_rounded,
    Icons.network_ping_rounded,   Icons.waves_rounded,
  ];
  static const _metricKeys = ['down', 'up', 'ping', 'jitter'];

  Color _metricColor(int m, ThemeData t) {
    switch (m) {
      case 0:  return t.colorScheme.primary;
      case 1:  return t.colorScheme.secondary;
      case 2:  return t.colorScheme.tertiary;
      default: return t.colorScheme.error;
    }
  }

  String _displayValue(_Entry e, int m, int ui) {
    switch (m) {
      case 0:  return formatSpeedValue(e.dl, ui);
      case 1:  return formatSpeedValue(e.ul, ui);
      case 2:  return '${e.ping}';
      default: return '${e.jitter}';
    }
  }

  String _displayUnit(int m, int ui) => m < 2 ? kSpeedUnitLabels[ui] : 'ms';

  @override
  Widget build(BuildContext context) {
    final t      = Theme.of(context);
    final chrono = _chrono;
    final e      = _displayEntry;
    final ui     = speedUnitIndexNotifier.value;
    final grade  = _gradeFor(e.dl);
    final hasMap = e.lat != null && e.lng != null;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.92, minChildSize: 0.5, maxChildSize: 0.95,
      builder: (_, sc) => Column(children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Center(child: Container(
            width: 36, height: 4,
            decoration: BoxDecoration(
              color: t.colorScheme.onSurface.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(2),
            ),
          )),
        ),
        Expanded(child: SingleChildScrollView(
          controller: sc,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

            // ── Header ─────────────────────────────────────────────────────
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(context.tr('testDetail'),
                    style: t.textTheme.labelSmall?.copyWith(
                      color: t.colorScheme.primary, fontWeight: FontWeight.bold, letterSpacing: 1.5,
                    )),
                const SizedBox(height: 4),
                Text(e.timestamp,
                    style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Row(children: [
                  Text(e.flag, style: const TextStyle(fontSize: 14)),
                  const SizedBox(width: 5),
                  Flexible(child: Text(
                    '${e.server}  ·  ${e.provider}\n${e.serverLoc}',
                    style: t.textTheme.bodySmall?.copyWith(
                        color: t.colorScheme.onSurface.withValues(alpha: 0.55)),
                  )),
                ]),
                if (e.userLoc.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(children: [
                    Icon(Icons.place_rounded, size: 11,
                        color: t.colorScheme.primary.withValues(alpha: 0.6)),
                    const SizedBox(width: 4),
                    Text(e.userLoc, style: t.textTheme.bodySmall?.copyWith(
                        color: t.colorScheme.primary.withValues(alpha: 0.6))),
                  ]),
                ],
              ])),
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
                    fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.8,
                    color: grade.color,
                  )),
                ]),
              ),
            ]),
            const SizedBox(height: 20),

            // ── 4 metric cards ──────────────────────────────────────────────
            Row(children: List.generate(4, (m) {
              final color = _metricColor(m, t);
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
                        color: sel ? color.withValues(alpha: 0.4)
                            : t.colorScheme.onSurface.withValues(alpha: 0.07),
                        width: sel ? 1.5 : 1,
                      ),
                    ),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(_metricIcons[m], size: 14,
                          color: color.withValues(alpha: sel ? 1.0 : 0.5)),
                      const SizedBox(height: 5),
                      Text(_displayValue(e, m, ui), style: t.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800, color: color, height: 1.0,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      )),
                      Text(_displayUnit(m, ui), style: TextStyle(
                        fontSize: 8, color: color.withValues(alpha: 0.65),
                        fontWeight: FontWeight.w600,
                      )),
                    ]),
                  ),
                ),
              );
            })),
            const SizedBox(height: 24),

            // ── OSM Map (only if GPS coords available) ─────────────────────
            if (hasMap) ...[
              Text(context.tr('mapLocation'),
                  style: t.textTheme.labelSmall?.copyWith(
                    color: t.colorScheme.primary, fontWeight: FontWeight.bold, letterSpacing: 1.5,
                  )),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: SizedBox(
                  height: 200,
                  child: Stack(children: [
                    FlutterMap(
                      options: MapOptions(
                        initialCenter: LatLng(e.lat!, e.lng!),
                        initialZoom:   11,
                        interactionOptions: const InteractionOptions(
                          flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                        ),
                      ),
                      children: [
                        TileLayer(
                          urlTemplate: Theme.of(context).brightness == Brightness.dark
                              ? 'https://a.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png'
                              : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: 'com.jitter.app',
                        ),
                        MarkerLayer(markers: [
                          Marker(
                            point: LatLng(e.lat!, e.lng!),
                            width: 44, height: 56,
                            child: _MapPinWidget(
                              label: formatSpeedValue(e.dl, ui),
                              unit:  kSpeedUnitLabels[ui],
                              color: grade.color,
                            ),
                          ),
                        ]),
                      ],
                    ),
                    // OSM Attribution
                    Positioned(
                      bottom: 2, right: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.75),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(context.tr('osmCredit'),
                            style: const TextStyle(fontSize: 7, color: Colors.black87)),
                      ),
                    ),
                  ]),
                ),
              ),
              const SizedBox(height: 24),
            ],

            // ── VS Average (compared to all history) ─────────────────────────
            if (chrono.length > 1) ...[
              Text(context.tr('vsAverage'), style: t.textTheme.labelSmall?.copyWith(
                color: t.colorScheme.primary, fontWeight: FontWeight.bold, letterSpacing: 1.5,
              )),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color:        t.colorScheme.onSurface.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: t.colorScheme.onSurface.withValues(alpha: 0.06)),
                ),
                child: Column(children: [
                  _vsRow(label: context.tr('down'),   thisVal: e.dl,     allVals: chrono.map((x)=>x.dl).toList(),            color: t.colorScheme.primary,   unitIdx: ui, t: t, isSpeed: true),
                  const SizedBox(height: 12),
                  _vsRow(label: context.tr('up'),     thisVal: e.ul,     allVals: chrono.map((x)=>x.ul).toList(),            color: t.colorScheme.secondary, unitIdx: ui, t: t, isSpeed: true),
                  const SizedBox(height: 12),
                  _vsRow(label: context.tr('ping'),   thisVal: e.ping.toDouble(), allVals: chrono.map((x)=>x.ping.toDouble()).toList(),   color: _pingColor(e.ping,   context), unitIdx: ui, t: t, isSpeed: false),
                  const SizedBox(height: 12),
                  _vsRow(label: context.tr('jitter'), thisVal: e.jitter.toDouble(), allVals: chrono.map((x)=>x.jitter.toDouble()).toList(), color: _jitterColor(e.jitter, context), unitIdx: ui, t: t, isSpeed: false),
                ]),
              ),
            ],
          ]),
        )),
      ]),
    );
  }

  Widget _vsRow({
    required String label, required double thisVal, required List<double> allVals,
    required Color color,   required int unitIdx, required ThemeData t, required bool isSpeed,
  }) {
    final avg  = allVals.reduce((a,b)=>a+b) / allVals.length;
    final mx   = allVals.reduce((a,b)=>a>b?a:b);
    final tf   = mx > 0 ? (thisVal / mx).clamp(0.0, 1.0) : 0.0;
    final af   = mx > 0 ? (avg     / mx).clamp(0.0, 1.0) : 0.0;
    String fmt(double v) => isSpeed
        ? formatSpeedValue(v, unitIdx)
        : (v >= 10 ? v.toStringAsFixed(0) : v.toStringAsFixed(1));
    final unit = isSpeed ? kSpeedUnitLabels[unitIdx] : 'ms';

    Widget bar(double frac, Color c, double h) => Stack(children: [
      Container(height: h, decoration: BoxDecoration(
        color: t.colorScheme.onSurface.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(4),
      )),
      FractionallySizedBox(widthFactor: frac, child: Container(
        height: h, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(4)),
      )),
    ]);

    return Row(children: [
      SizedBox(width: 46, child: Text(label, style: TextStyle(
        fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 0.5,
        color: color.withValues(alpha: 0.7),
      ))),
      Expanded(child: Column(children: [
        Row(children: [
          Expanded(child: bar(tf, color, 6)),
          const SizedBox(width: 8),
          SizedBox(width: 70, child: Text('${fmt(thisVal)} $unit',
              textAlign: TextAlign.right,
              style: t.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w700, color: color, fontSize: 10,
                fontFeatures: const [FontFeature.tabularFigures()],
              ))),
        ]),
        const SizedBox(height: 4),
        Row(children: [
          Expanded(child: bar(af, color.withValues(alpha: 0.35), 4)),
          const SizedBox(width: 8),
          SizedBox(width: 70, child: Text('avg ${fmt(avg)} $unit',
              textAlign: TextAlign.right,
              style: t.textTheme.labelSmall?.copyWith(
                fontSize: 9, color: t.colorScheme.onSurface.withValues(alpha: 0.4),
                fontFeatures: const [FontFeature.tabularFigures()],
              ))),
        ]),
      ])),
    ]);
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MAP PIN WIDGET (used in detail sheet)
// ═══════════════════════════════════════════════════════════════════════════════
class _MapPinWidget extends StatelessWidget {
  final String label, unit;
  final Color  color;
  const _MapPinWidget({required this.label, required this.unit, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        // Constrain max width so long values (e.g. "0.0065 GB/s") stay inside
        constraints: const BoxConstraints(maxWidth: 90),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color:        color,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(color: color.withValues(alpha: 0.55), blurRadius: 14, offset: const Offset(0, 5)),
            BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 4, offset: const Offset(0, 1)),
          ],
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(label,
                style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w800,
                  fontSize: 13, letterSpacing: -0.3,
                )),
            const SizedBox(width: 3),
            Text(unit,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.72),
                  fontSize: 9, fontWeight: FontWeight.w500,
                )),
          ]),
        ),
      ),
      CustomPaint(size: const Size(14, 7), painter: _TrianglePainter(color: color)),
    ]);
  }
}

class _TrianglePainter extends CustomPainter {
  final Color color;
  const _TrianglePainter({required this.color});
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      Path()
        ..moveTo(0, 0)
        ..lineTo(size.width, 0)
        ..lineTo(size.width / 2, size.height)
        ..close(),
      Paint()..color = color,
    );
  }
  @override bool shouldRepaint(_TrianglePainter o) => o.color != color;
}

// ═══════════════════════════════════════════════════════════════════════════════
// MAP SCREEN — full OSM map with all test locations
// ═══════════════════════════════════════════════════════════════════════════════
class _MapScreen extends StatefulWidget {
  final List<_Entry> history;
  const _MapScreen({required this.history});
  @override
  State<_MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<_MapScreen> {
  _Entry? _selected;

  List<_Entry> get _gpsEntries =>
      widget.history.where((e) => e.lat != null && e.lng != null).toList();

  @override
  Widget build(BuildContext context) {
    final t       = Theme.of(context);
    final entries = _gpsEntries;
    final hasData = entries.isNotEmpty;

    final LatLng center = hasData
        ? LatLng(
            entries.map((e) => e.lat!).reduce((a,b)=>a+b) / entries.length,
            entries.map((e) => e.lng!).reduce((a,b)=>a+b) / entries.length,
          )
        : const LatLng(46.6, 2.2); // center of France as default

    final ui = speedUnitIndexNotifier.value;

    return Stack(children: [
      // ── Full-screen map ───────────────────────────────────────────────────
      FlutterMap(
        options: MapOptions(
          initialCenter: center,
          initialZoom:   hasData ? (entries.length == 1 ? 10 : 5) : 4,
          interactionOptions: const InteractionOptions(
            flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
          ),
          onTap: (_, __) => setState(() => _selected = null),
        ),
        children: [
          TileLayer(
            urlTemplate: Theme.of(context).brightness == Brightness.dark
                ? 'https://a.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png'
                : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.jitter.app',
            maxZoom: 19,
          ),
          // Cluster nearby entries
          if (hasData) MarkerLayer(
            markers: entries.map((e) {
              final grade = _gradeFor(e.dl);
              final isSel = _selected == e;
              return Marker(
                point:  LatLng(e.lat!, e.lng!),
                width:  isSel ? 100 : 82,
                height: isSel ? 64  : 54,
                child: GestureDetector(
                  onTap: () => setState(() => _selected = _selected == e ? null : e),
                  child: AnimatedScale(
                    scale:    isSel ? 1.12 : 1.0,
                    duration: const Duration(milliseconds: 200),
                    curve:    Curves.easeOutBack,
                    child: _MapPinWidget(
                      label: formatSpeedValue(e.dl, ui),
                      unit:  kSpeedUnitLabels[ui],
                      color: isSel ? grade.color : grade.color.withValues(alpha: 0.85),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          // OSM attribution
          const RichAttributionWidget(attributions: [
            TextSourceAttribution('OpenStreetMap contributors'),
          ]),
        ],
      ),

      // ── Header overlay ────────────────────────────────────────────────────
      Positioned(
        top: 0, left: 0, right: 0,
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end:   Alignment.bottomCenter,
              colors: [
                t.colorScheme.surface.withValues(alpha: 0.95),
                t.colorScheme.surface.withValues(alpha: 0.0),
              ],
            ),
          ),
          child: Row(children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(context.tr('mapTitle'),
                  style: t.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold, letterSpacing: 1.5,
                  )),
              Text(
                hasData
                    ? '${entries.length} test${entries.length>1?"s":""}'
                      ' · ${_uniqueLocCount(entries)} location${_uniqueLocCount(entries)>1?"s":""}'
                    : context.tr('mapNoGps').split('\n').first,
                style: t.textTheme.bodySmall?.copyWith(
                    color: t.colorScheme.onSurface.withValues(alpha: 0.45)),
              ),
            ]),
          ]),
        ),
      ),

      // ── No data overlay ───────────────────────────────────────────────────
      if (!hasData)
        Center(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 40),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color:        t.colorScheme.surface.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: t.colorScheme.onSurface.withValues(alpha: 0.08)),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.location_off_rounded, size: 40,
                  color: t.colorScheme.onSurface.withValues(alpha: 0.2)),
              const SizedBox(height: 14),
              Text(context.tr('mapNoGps'), textAlign: TextAlign.center,
                  style: t.textTheme.bodyMedium?.copyWith(
                    color: t.colorScheme.onSurface.withValues(alpha: 0.5), height: 1.5,
                  )),
            ]),
          ),
        ),

      // ── Selected entry card ───────────────────────────────────────────────
      if (_selected != null)
        Positioned(
          bottom: 16, left: 16, right: 16,
          child: _SelectedCard(entry: _selected!, t: t, ui: ui,
              onClose: () => setState(() => _selected = null)),
        ),
    ]);
  }

  int _uniqueLocCount(List<_Entry> entries) {
    final seen = <String>{};
    for (final e in entries) {
      seen.add('${e.lat!.toStringAsFixed(2)},${e.lng!.toStringAsFixed(2)}');
    }
    return seen.length;
  }
}

// ── Selected entry card on map ─────────────────────────────────────────────
class _SelectedCard extends StatelessWidget {
  final _Entry    entry;
  final ThemeData t;
  final int       ui;
  final VoidCallback onClose;
  const _SelectedCard({required this.entry, required this.t, required this.ui, required this.onClose});

  @override
  Widget build(BuildContext context) {
    final grade = _gradeFor(entry.dl);
    return AnimatedSlide(
      offset: Offset.zero,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutBack,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color:        t.colorScheme.surface.withValues(alpha: 0.97),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: t.colorScheme.onSurface.withValues(alpha: 0.08)),
          boxShadow: [BoxShadow(
            color:      Colors.black.withValues(alpha: 0.12),
            blurRadius: 20, offset: const Offset(0, 4),
          )],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(entry.flag, style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 8),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(entry.userLoc.isEmpty ? entry.serverLoc : entry.userLoc,
                  style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              Text(entry.timestamp, style: t.textTheme.bodySmall?.copyWith(
                  color: t.colorScheme.onSurface.withValues(alpha: 0.45))),
            ])),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color:        grade.color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: grade.color.withValues(alpha: 0.3)),
              ),
              child: Text(grade.labelFor(context), style: TextStyle(
                fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.6, color: grade.color,
              )),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onClose,
              child: Icon(Icons.close_rounded, size: 18,
                  color: t.colorScheme.onSurface.withValues(alpha: 0.35)),
            ),
          ]),
          const SizedBox(height: 12),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            _miniStat('↓', formatSpeedValue(entry.dl, ui), kSpeedUnitLabels[ui],
                t.colorScheme.primary, t),
            _miniStat('↑', formatSpeedValue(entry.ul, ui), kSpeedUnitLabels[ui],
                t.colorScheme.secondary, t),
            _miniStat('PING', '${entry.ping}', 'ms', t.colorScheme.tertiary, t),
            _miniStat('JITTER', '${entry.jitter}', 'ms', t.colorScheme.error, t),
          ]),
        ]),
      ),
    );
  }

  Widget _miniStat(String label, String value, String unit, Color color, ThemeData t) =>
      Column(mainAxisSize: MainAxisSize.min, children: [
        Text(label, style: TextStyle(
          fontSize: 8, fontWeight: FontWeight.bold, letterSpacing: 0.6,
          color: color.withValues(alpha: 0.65),
        )),
        const SizedBox(height: 3),
        RichText(text: TextSpan(children: [
          TextSpan(text: value, style: t.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w800, color: color, height: 1.0,
            fontFeatures: const [FontFeature.tabularFigures()],
          )),
          TextSpan(text: ' $unit', style: t.textTheme.labelSmall?.copyWith(
            fontSize: 8, color: color.withValues(alpha: 0.6),
          )),
        ])),
      ]);
}

// ═══════════════════════════════════════════════════════════════════════════════
// TREND CHART (interactive)
// ═══════════════════════════════════════════════════════════════════════════════
class _TrendChart extends StatefulWidget {
  final List<_Entry> entries;
  final int          selectedIdx, metric;
  final Color        color;
  final ThemeData    t;
  final ValueChanged<int?> onHover;
  const _TrendChart({
    required this.entries, required this.selectedIdx, required this.metric,
    required this.color,   required this.t,           required this.onHover,
  });
  @override State<_TrendChart> createState() => _TrendChartState();
}

class _TrendChartState extends State<_TrendChart> {
  int?   _hoverIdx;
  double _cachedWidth = 0; // set by LayoutBuilder, used for touch → index mapping

  int _posToIdx(Offset local) {
    if (_cachedWidth <= 0 || widget.entries.length < 2) return 0;
    const padL = 44.0, padR = 12.0;
    final frac = ((local.dx - padL) / (_cachedWidth - padL - padR)).clamp(0.0, 1.0);
    return (frac * (widget.entries.length - 1))
        .round()
        .clamp(0, widget.entries.length - 1);
  }

  void _touch(Offset pos) {
    final idx = _posToIdx(pos);
    if (idx != _hoverIdx) {
      setState(() => _hoverIdx = idx);
      widget.onHover(idx);
    }
  }
  void _end() { setState(() => _hoverIdx = null); widget.onHover(null); }

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTapDown:   (d) => _touch(d.localPosition),
    onTapUp:     (_) => _end(),
    onPanStart:  (d) => _touch(d.localPosition),
    onPanUpdate: (d) => _touch(d.localPosition),
    onPanEnd:    (_) => _end(),
    // LayoutBuilder gives the actual pixel size from the parent Container,
    // which is reliable inside unbounded scroll views (unlike SizedBox.expand).
    child: LayoutBuilder(
      builder: (_, constraints) {
        _cachedWidth = constraints.maxWidth;
        return CustomPaint(
          size: Size(constraints.maxWidth, constraints.maxHeight),
          painter: _TrendChartPainter(
            entries:     widget.entries,
            selectedIdx: widget.selectedIdx,
            hoverIdx:    _hoverIdx,
            metric:      widget.metric,
            color:       widget.color,
            t:           widget.t,
          ),
        );
      },
    ),
  );
}

class _TrendChartPainter extends CustomPainter {
  final List<_Entry> entries;
  final int selectedIdx;
  final int? hoverIdx;
  final int  metric;
  final Color color;
  final ThemeData t;
  const _TrendChartPainter({
    required this.entries, required this.selectedIdx, required this.hoverIdx,
    required this.metric,  required this.color,       required this.t,
  });

  double _val(_Entry e) {
    switch (metric) {
      case 0:  return e.dl;
      case 1:  return e.ul;
      case 2:  return e.ping.toDouble();
      default: return e.jitter.toDouble();
    }
  }
  String _fmtV(double v) => v >= 100 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  @override
  void paint(Canvas canvas, Size size) {
    if (entries.isEmpty) return;
    const padL = 44.0, padR = 14.0, padT = 28.0, padB = 20.0;
    final cw = size.width - padL - padR;
    final ch = size.height - padT - padB;

    final vals = entries.map(_val).toList();
    final maxV = (vals.reduce(max) * 1.15).clamp(1.0, double.infinity);

    double toY(double v) => padT + ch * (1 - v / maxV);
    double toX(int i)    => entries.length <= 1
        ? padL + cw / 2
        : padL + cw * i / (entries.length - 1);

    // Grid
    final gp = Paint()..color = t.colorScheme.onSurface.withValues(alpha: 0.06)..strokeWidth = 1;
    for (int g = 0; g <= 4; g++) {
      final y = padT + ch * g / 4;
      canvas.drawLine(Offset(padL, y), Offset(padL + cw, y), gp);
    }
    // Y labels
    final tp = TextPainter(textDirection: TextDirection.ltr);
    for (int g = 0; g <= 4; g++) {
      final v = maxV * (4 - g) / 4;
      tp.text = TextSpan(
        text: v >= 1000 ? '${(v/1000).toStringAsFixed(1)}G' : _fmtV(v),
        style: TextStyle(fontSize: 8.5, color: t.colorScheme.onSurface.withValues(alpha: 0.3), fontFamily: 'monospace'),
      );
      tp.layout();
      tp.paint(canvas, Offset(padL - tp.width - 4, padT + ch * g / 4 - tp.height / 2));
    }

    if (entries.length < 2) {
      canvas.drawCircle(Offset(toX(0), toY(vals[0])), 5, Paint()..color = color);
      return;
    }

    // Bezier path
    final path = Path()..moveTo(toX(0), toY(vals[0]));
    for (int i = 1; i < entries.length; i++) {
      final cpx = (toX(i-1) + toX(i)) / 2;
      path.cubicTo(cpx, toY(vals[i-1]), cpx, toY(vals[i]), toX(i), toY(vals[i]));
    }

    // Fill
    canvas.drawPath(
      Path.from(path)
        ..lineTo(toX(entries.length-1), size.height - padB)
        ..lineTo(padL, size.height - padB)
        ..close(),
      Paint()..shader = LinearGradient(
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [color.withValues(alpha: 0.28), color.withValues(alpha: 0.0)],
      ).createShader(Rect.fromLTWH(0, padT, size.width, ch)),
    );
    // Stroke
    canvas.drawPath(path, Paint()
      ..style = PaintingStyle.stroke ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round  ..strokeJoin = StrokeJoin.round
      ..color = color.withValues(alpha: 0.9));

    // Dots
    for (int i = 0; i < entries.length; i++) {
      final x = toX(i), y = toY(vals[i]);
      if (i == selectedIdx) {
        canvas.drawCircle(Offset(x,y), 10, Paint()..color = color.withValues(alpha: 0.15));
        canvas.drawCircle(Offset(x,y), 6,  Paint()..color = color);
        canvas.drawCircle(Offset(x,y), 3,  Paint()..color = Colors.white);
      } else if (i == hoverIdx) {
        canvas.drawCircle(Offset(x,y), 7,  Paint()..color = color.withValues(alpha: 0.25));
        canvas.drawCircle(Offset(x,y), 5,  Paint()..color = color);
        canvas.drawCircle(Offset(x,y), 2.5,Paint()..color = Colors.white);
      } else {
        canvas.drawCircle(Offset(x,y), 3,  Paint()..color = color.withValues(alpha: 0.6));
        canvas.drawCircle(Offset(x,y), 1.5,Paint()..color = t.colorScheme.surface);
      }
    }

    // Hover tooltip
    if (hoverIdx != null && hoverIdx! < entries.length) {
      final hi = hoverIdx!;
      final hx = toX(hi), hy = toY(vals[hi]);
      canvas.drawLine(Offset(hx, padT), Offset(hx, size.height - padB),
          Paint()..color = color.withValues(alpha: 0.35)..strokeWidth = 1.2);

      final label = '${_fmtV(vals[hi])}  •  '
          '${entries[hi].timestamp.length >= 16 ? entries[hi].timestamp.substring(5,16) : entries[hi].timestamp}';
      tp.text = TextSpan(text: label,
          style: TextStyle(fontSize: 10.5, color: t.colorScheme.onSurface, fontWeight: FontWeight.w600));
      tp.layout(maxWidth: 200);
      final tx = (hx - tp.width/2 - 8).clamp(padL - 2, size.width - tp.width - 18);
      final rrect = RRect.fromRectAndRadius(
        Rect.fromLTWH(tx, 3, tp.width + 16, tp.height + 8), const Radius.circular(6));
      canvas.drawRRect(rrect, Paint()..color = t.colorScheme.surface.withValues(alpha: 0.97));
      canvas.drawRRect(rrect, Paint()..style = PaintingStyle.stroke
          ..color = color.withValues(alpha: 0.5)..strokeWidth = 1);
      tp.paint(canvas, Offset(tx + 8, 7));
      canvas.drawCircle(Offset(hx, hy), 4, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(_TrendChartPainter o) =>
      o.entries != entries || o.selectedIdx != selectedIdx ||
      o.hoverIdx != hoverIdx || o.metric != metric || o.color != color;
}

// ═══════════════════════════════════════════════════════════════════════════════
// PAINTERS & HELPERS
// ═══════════════════════════════════════════════════════════════════════════════
class _ArcPainter extends CustomPainter {
  final double speedMbps, maxMbps;
  final Color  trackColor, primary;
  const _ArcPainter({required this.speedMbps, required this.maxMbps,
                     required this.trackColor, required this.primary});
  static const _start = 150 * pi / 180, _total = 240 * pi / 180;
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width/2, cy = size.height/2, r = min(cx,cy) - 10;
    final rect = Rect.fromCircle(center: Offset(cx,cy), radius: r);
    canvas.drawArc(rect, _start, _total, false, Paint()
        ..style = PaintingStyle.stroke ..strokeWidth = 9
        ..strokeCap = StrokeCap.round  ..color = trackColor);
    final frac = (speedMbps / maxMbps).clamp(0.0, 1.0);
    if (frac > 0.005) {
      canvas.drawArc(rect, _start, _total * frac, false, Paint()
          ..style = PaintingStyle.stroke ..strokeWidth = 9
          ..strokeCap = StrokeCap.round
          ..shader = SweepGradient(
            startAngle: _start, endAngle: _start + _total * frac,
            colors: [primary.withValues(alpha: 0.55), primary],
            transform: const GradientRotation(_start),
          ).createShader(rect));
    }
  }
  @override bool shouldRepaint(_ArcPainter o) =>
      o.speedMbps != speedMbps || o.primary != primary || o.trackColor != trackColor;
}

class _SegBar extends StatelessWidget {
  final double progress;
  final bool   active, done;
  final Color  color;
  const _SegBar({required this.progress, required this.active, required this.done, required this.color});
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(4),
    child: SizedBox(height: 4, child: Stack(fit: StackFit.expand, children: [
      ColoredBox(color: color.withValues(alpha: 0.1)),
      AnimatedFractionallySizedBox(
        duration: const Duration(milliseconds: 120),
        alignment: Alignment.centerLeft,
        widthFactor: progress.clamp(0.0, 1.0),
        child: ColoredBox(color: done
            ? color.withValues(alpha: 0.5)
            : active ? color : color.withValues(alpha: 0.0)),
      ),
      if (active && progress < 0.05) _ShimmerBar(color: color),
    ])),
  );
}

class _ShimmerBar extends StatefulWidget {
  final Color color;
  const _ShimmerBar({required this.color});
  @override State<_ShimmerBar> createState() => _ShimmerBarState();
}

class _ShimmerBarState extends State<_ShimmerBar> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double>   _anim;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }
  @override void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _anim,
    builder: (_, __) => Align(
      alignment: Alignment(-1.0 + _anim.value * 2, 0),
      child: FractionallySizedBox(widthFactor: 0.3, child: DecoratedBox(
        decoration: BoxDecoration(gradient: LinearGradient(colors: [
          widget.color.withValues(alpha: 0.0),
          widget.color.withValues(alpha: 0.85),
          widget.color.withValues(alpha: 0.0),
        ])),
      )),
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
    canvas.drawRect(Offset.zero & size, Paint()..color = color.withValues(alpha: 0.03));
    if (points.length < 2) return;
    final maxV = points.reduce((a, b) => a > b ? a : b);
    // Scale to 2x current max (min 10) so fluctuations look proportional, not maxed out
    final cap = maxV < 1 ? 1.0 : max(maxV * 2.0, 10.0);

    Offset pt(int i) => Offset(
      size.width * i / (points.length - 1),
      size.height - (points[i] / cap * size.height * 0.88 + size.height * 0.06),
    );

    // Smooth bezier path
    final path = Path()..moveTo(pt(0).dx, pt(0).dy);
    for (int i = 1; i < points.length; i++) {
      final cpx = (pt(i - 1).dx + pt(i).dx) / 2;
      path.cubicTo(cpx, pt(i - 1).dy, cpx, pt(i).dy, pt(i).dx, pt(i).dy);
    }

    canvas.drawPath(
      Path.from(path)
        ..lineTo(size.width, size.height)
        ..lineTo(0, size.height)
        ..close(),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.18), color.withValues(alpha: 0.0)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style       = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeCap   = StrokeCap.round
        ..strokeJoin  = StrokeJoin.round
        ..color       = color.withValues(alpha: 0.8),
    );
  }
  @override bool shouldRepaint(_ChartPainter o) => o.points != points || o.color != color;
}