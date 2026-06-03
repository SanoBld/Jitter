import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../app_state.dart';
import '../services/internet_speed_service.dart';
import 'settings_screen.dart';

// Performance grade based on download speed
enum _PerfGrade { excellent, veryGood, good, fair, slow, poor }

extension _PerfGradeX on _PerfGrade {
  String get label {
    switch (this) {
      case _PerfGrade.excellent: return 'EXCELLENT';
      case _PerfGrade.veryGood:  return 'VERY GOOD';
      case _PerfGrade.good:      return 'GOOD';
      case _PerfGrade.fair:      return 'FAIR';
      case _PerfGrade.slow:      return 'SLOW';
      case _PerfGrade.poor:      return 'VERY SLOW';
    }
  }

  Color get color {
    switch (this) {
      case _PerfGrade.excellent: return const Color(0xFF1B5E20);
      case _PerfGrade.veryGood:  return const Color(0xFF2E7D32);
      case _PerfGrade.good:      return const Color(0xFF1565C0);
      case _PerfGrade.fair:      return const Color(0xFFE65100);
      case _PerfGrade.slow:      return const Color(0xFFBF360C);
      case _PerfGrade.poor:      return const Color(0xFFC62828);
    }
  }

  IconData get icon {
    switch (this) {
      case _PerfGrade.excellent: return Icons.rocket_launch_rounded;
      case _PerfGrade.veryGood:  return Icons.speed_rounded;
      case _PerfGrade.good:      return Icons.check_circle_outline_rounded;
      case _PerfGrade.fair:      return Icons.remove_circle_outline_rounded;
      case _PerfGrade.slow:      return Icons.hourglass_bottom_rounded;
      case _PerfGrade.poor:      return Icons.signal_cellular_off_rounded;
    }
  }
}

_PerfGrade _gradeDl(double mbps) {
  if (mbps >= 500) return _PerfGrade.excellent;
  if (mbps >= 200) return _PerfGrade.veryGood;
  if (mbps >= 100) return _PerfGrade.good;
  if (mbps >= 30)  return _PerfGrade.fair;
  if (mbps >= 10)  return _PerfGrade.slow;
  return _PerfGrade.poor;
}

// Green = low latency, red = high latency
Color _pingColorFor(int ms, BuildContext context) {
  if (ms == 0) return Theme.of(context).colorScheme.onSurface.withOpacity(0.3);
  if (ms <= 30)  return const Color(0xFF2E7D32);
  if (ms <= 80)  return const Color(0xFF1565C0);
  if (ms <= 150) return const Color(0xFFE65100);
  return Theme.of(context).colorScheme.error;
}

// Green = stable, red = unstable
Color _jitterColorFor(int ms, BuildContext context) {
  if (ms == 0)  return Theme.of(context).colorScheme.onSurface.withOpacity(0.3);
  if (ms <= 10) return const Color(0xFF2E7D32);
  if (ms <= 30) return const Color(0xFF1565C0);
  if (ms <= 60) return const Color(0xFFE65100);
  return Theme.of(context).colorScheme.error;
}

// One entry saved to history
class _LogEntry {
  final String timestamp;
  final String flag;
  final String server;
  final String provider;
  final String serverLocation;
  final String userLocation;
  final double dl;
  final double ul;
  final int    ping;
  final int    jitter;
  final String unit;

  const _LogEntry({
    required this.timestamp,
    required this.flag,
    required this.server,
    required this.provider,
    required this.serverLocation,
    required this.userLocation,
    required this.dl,
    required this.ul,
    required this.ping,
    required this.jitter,
    required this.unit,
  });

  Map<String, dynamic> toJson() => {
    'ts':           timestamp,
    'flag':         flag,
    'server':       server,
    'provider':     provider,
    'location':     serverLocation,
    'userLocation': userLocation,
    'dl':           dl,
    'ul':           ul,
    'ping':         ping,
    'jitter':       jitter,
    'unit':         unit,
  };

  factory _LogEntry.fromJson(Map<String, dynamic> j) => _LogEntry(
    timestamp:      j['ts']           as String,
    flag:           j['flag']         as String,
    server:         j['server']       as String,
    provider:       j['provider']     as String,
    serverLocation: j['location']     as String? ?? '',
    userLocation:   j['userLocation'] as String? ?? '',
    dl:             (j['dl']   as num).toDouble(),
    ul:             (j['ul']   as num).toDouble(),
    ping:           j['ping']         as int,
    jitter:         j['jitter']       as int? ?? 0,
    unit:           j['unit']         as String,
  );

  // Parse old plain-text log format for backwards compatibility
  static _LogEntry? tryFromLegacyString(String raw) {
    try {
      final parts = raw.split('  |  ');
      if (parts.length < 3) return null;
      final ts      = parts[0].trim();
      final srv     = parts[1].trim();
      final metrics = parts[2].trim();
      final flag    = srv.split(' ').first;
      final server  = srv.substring(flag.length).trim();
      final dlMatch   = RegExp(r'🔽\s*([\d.]+)\s*(\S+)').firstMatch(metrics);
      final ulMatch   = RegExp(r'🔼\s*([\d.]+)').firstMatch(metrics);
      final pingMatch = RegExp(r'📶\s*(\d+)').firstMatch(metrics);
      if (dlMatch == null) return null;
      return _LogEntry(
        timestamp:      ts,
        flag:           flag,
        server:         server,
        provider:       '',
        serverLocation: '',
        userLocation:   '',
        dl:             double.parse(dlMatch.group(1)!),
        ul:             ulMatch != null ? double.parse(ulMatch.group(1)!) : 0,
        ping:           pingMatch != null ? int.parse(pingMatch.group(1)!) : 0,
        jitter:         0,
        unit:           dlMatch.group(2) ?? 'Mb/s',
      );
    } catch (_) {
      return null;
    }
  }
}

class _IndexedEntry {
  final _LogEntry entry;
  final int index;
  const _IndexedEntry(this.entry, this.index);
}

// Available duration steps in seconds. 0 = infinite (runs until stopped)
const _kDurationSteps = [5, 10, 15, 20, 30, 60, 0];

// ═══════════════════════════════════════════════════════════════════════════
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {

  final _svc = InternetSpeedService();
  int _tabIndex = 0;

  // Live test values
  final _speedNf    = ValueNotifier<double>(0.0);
  final _pingNf     = ValueNotifier<int>(0);
  final _jitterNf   = ValueNotifier<int>(0);
  final _dlNf       = ValueNotifier<double>(0.0);
  final _ulNf       = ValueNotifier<double>(0.0);
  final _testingNf  = ValueNotifier<bool>(false);
  final _phaseNf    = ValueNotifier<String>('READY');
  final _pointsNf   = ValueNotifier<List<double>>([]);
  final _progressNf = ValueNotifier<double>(0.0);
  final _errorNf    = ValueNotifier<String?>(null);

  // Set to true to abort the current test at the next loop iteration
  bool _stopRequested = false;

  late AnimationController _pulse;
  List<_LogEntry> _history = [];

  @override
  void initState() {
    super.initState();
    _loadHistory();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _fetchAndUpdateLocation();
  }

  @override
  void dispose() {
    _pulse.dispose();
    _speedNf.dispose();
    _pingNf.dispose();
    _jitterNf.dispose();
    _dlNf.dispose();
    _ulNf.dispose();
    _testingNf.dispose();
    _phaseNf.dispose();
    _pointsNf.dispose();
    _progressNf.dispose();
    _errorNf.dispose();
    super.dispose();
  }

  // Load history from disk
  Future<void> _loadHistory() async {
    final p   = await SharedPreferences.getInstance();
    final raw = p.getStringList('speed_history') ?? [];
    final parsed = <_LogEntry>[];
    for (final s in raw) {
      try {
        parsed.add(_LogEntry.fromJson(json.decode(s) as Map<String, dynamic>));
      } catch (_) {
        final leg = _LogEntry.tryFromLegacyString(s);
        if (leg != null) parsed.add(leg);
      }
    }
    if (mounted) setState(() => _history = parsed);
  }

  Future<void> _saveHistory() async {
    final p = await SharedPreferences.getInstance();
    await p.setStringList(
      'speed_history',
      _history.map((e) => json.encode(e.toJson())).toList(),
    );
  }

  Future<void> _deleteEntry(int index) async {
    setState(() => _history.removeAt(index));
    await _saveHistory();
  }

  Future<void> _clearHistory() async {
    setState(() => _history = []);
    final p = await SharedPreferences.getInstance();
    await p.remove('speed_history');
  }

  // Fetch city and ISP from the public IP and update notifiers
  Future<void> _fetchAndUpdateLocation() async {
    locationFetchingNotifier.value = true;
    try {
      final info = await InternetSpeedService.getLocationAndIsp();
      if (info.location.isNotEmpty) await setUserLocation(info.location);
      if (info.isp.isNotEmpty)      await setIspName(info.isp);
    } finally {
      locationFetchingNotifier.value = false;
    }
  }

  String get _unit => speedUnitMbpsNotifier.value ? 'Mb/s' : 'MB/s';

  // ── Run full speed test ────────────────────────────────────────────────────
  Future<void> _runTest() async {
    _stopRequested    = false;
    _testingNf.value  = true;
    _errorNf.value    = null;
    _speedNf.value    = 0;
    _dlNf.value       = 0;
    _ulNf.value       = 0;
    _pingNf.value     = 0;
    _jitterNf.value   = 0;
    _pointsNf.value   = [];
    _progressNf.value = 0;
    _phaseNf.value    = 'LOCATING';

    try {
      await _fetchAndUpdateLocation();
      _progressNf.value = 0.04;
      if (_stopRequested) { _phaseNf.value = 'STOPPED'; return; }

      // Build the ordered list of server indices to try
      final rawIdx   = selectedServerNotifier.value;
      final startSrv = InternetSpeedService.resolveServerIndex(rawIdx);
      final total    = InternetSpeedService.servers.length;
      // All indices starting from the selected server, wrapping around
      final allOrder = List.generate(total, (i) => (startSrv + i) % total);
      // On web, skip servers without CORS support
      final filtered = kIsWeb
          ? allOrder.where(
              (i) => InternetSpeedService.servers[i].corsCompatible).toList()
          : allOrder;

      // If fallback is off, only try the first candidate
      final candidates = autoFallbackNotifier.value
          ? filtered
          : (filtered.isEmpty ? [startSrv] : [filtered.first]);

      bool   success   = false;
      String lastError = 'No server available';

      for (final srv in candidates) {
        if (_stopRequested) break;

        // Quick reachability check before committing to a full test.
        // This allows fast skipping of dead servers (3 s timeout).
        if (autoFallbackNotifier.value && candidates.length > 1) {
          _phaseNf.value = 'CHECKING…';
          final reachable = await _svc.quickReachable(srv);
          if (!reachable) continue; // skip to next server
          if (_stopRequested) break;
        }

        try {
          await _runPhases(srv);
          success = true;
          break;
        } catch (e) {
          lastError = e.toString();
          // If more servers to try, show a brief transition phase
          if (candidates.last != srv && !_stopRequested) {
            _phaseNf.value = 'SWITCHING…';
            await Future.delayed(const Duration(milliseconds: 400));
          }
        }
      }

      if (_stopRequested) {
        _phaseNf.value    = 'STOPPED';
        _progressNf.value = 0;
      } else if (!success) {
        _phaseNf.value    = 'ERROR';
        _errorNf.value    = _friendlyError(lastError);
        _progressNf.value = 0;
      }
    } catch (e) {
      _phaseNf.value    = 'ERROR';
      _errorNf.value    = _friendlyError(e.toString());
      _progressNf.value = 0;
    } finally {
      _testingNf.value = false;
    }
  }

  // Run ping → download → upload for one server.
  // Throws on network errors so the caller can try the next server.
  Future<void> _runPhases(int srv) async {
    final durSecs   = testDurationSecsNotifier.value; // 0 = infinite
    final isInfinite = durSecs == 0;

    // ── Ping + jitter ────────────────────────────────────────────────────────
    _phaseNf.value = 'PING';
    final pingResult = await _svc.testPingWithJitter(srv);
    if (_stopRequested) return;
    if (pingResult.ping == 999) throw Exception('Server unreachable (ping timeout)');
    _pingNf.value   = pingResult.ping;
    _jitterNf.value = pingResult.jitter;
    _progressNf.value = 0.20;

    // ── Download ─────────────────────────────────────────────────────────────
    _phaseNf.value  = 'DOWNLOAD';
    _pointsNf.value = [];
    final dlStart   = DateTime.now();
    Timer? progTimer;

    if (!isInfinite) {
      // Advance progress bar proportionally to elapsed time
      progTimer = Timer.periodic(const Duration(milliseconds: 300), (_) {
        if (_stopRequested) { progTimer?.cancel(); return; }
        final elapsed = DateTime.now().difference(dlStart).inMilliseconds;
        _progressNf.value =
            (0.20 + 0.50 * (elapsed / (durSecs * 1000))).clamp(0.20, 0.70);
      });
    }

    await for (final mbps in _svc.testDownloadSpeed(
        serverIndex: srv, durationSecs: durSecs)) {
      if (_stopRequested) break;
      _speedNf.value = mbps;
      _dlNf.value    = mbps;
      final pts = List<double>.from(_pointsNf.value)..add(mbps);
      if (pts.length > 60) pts.removeAt(0);
      _pointsNf.value = pts;
      // In infinite mode, pulse progress bar back and forth between 20–70 %
      if (isInfinite) {
        _progressNf.value = 0.20 + 0.50 * _pulse.value;
      }
    }
    progTimer?.cancel();
    if (_stopRequested) return;
    _progressNf.value = 0.70;

    // ── Upload ───────────────────────────────────────────────────────────────
    _phaseNf.value  = 'UPLOAD';
    _speedNf.value  = 0;
    _pointsNf.value = [];
    final ulStart   = DateTime.now();
    Timer? ulProgTimer;

    if (!isInfinite) {
      ulProgTimer = Timer.periodic(const Duration(milliseconds: 300), (_) {
        if (_stopRequested) { ulProgTimer?.cancel(); return; }
        final elapsed = DateTime.now().difference(ulStart).inMilliseconds;
        _progressNf.value =
            (0.70 + 0.30 * (elapsed / (durSecs * 1000))).clamp(0.70, 1.0);
      });
    }

    await for (final mbps in _svc.testUploadSpeed(durationSecs: durSecs)) {
      if (_stopRequested) break;
      _speedNf.value = mbps;
      _ulNf.value    = mbps;
      final pts = List<double>.from(_pointsNf.value)..add(mbps);
      if (pts.length > 60) pts.removeAt(0);
      _pointsNf.value = pts;
      if (isInfinite) {
        _progressNf.value = 0.70 + 0.30 * _pulse.value;
      }
    }
    ulProgTimer?.cancel();
    if (_stopRequested) return;

    _progressNf.value = 1.0;
    _phaseNf.value    = 'COMPLETED';

    // Save result to history if auto-save is on
    if (autoSaveHistoryNotifier.value) {
      final server = InternetSpeedService.servers[srv];
      final entry  = _LogEntry(
        timestamp:      DateTime.now().toLocal().toString().substring(0, 16),
        flag:           server.flag,
        server:         server.name,
        provider:       server.provider,
        serverLocation: server.location,
        userLocation:   userLocationNotifier.value,
        dl:             _dlNf.value,
        ul:             _ulNf.value,
        ping:           _pingNf.value,
        jitter:         _jitterNf.value,
        unit:           _unit,
      );
      setState(() => _history.insert(0, entry));
      await _saveHistory();
    }
  }

  // Convert raw error messages to user-friendly text
  String _friendlyError(String raw) {
    if (raw.contains('Failed to fetch') || raw.contains('CORS') ||
        raw.contains('cross-origin') || raw.contains('XMLHttpRequest'))
      return 'CORS error — this server blocks browser requests.\n'
          'Use a Cloudflare server or run the Android APK.';
    if (raw.contains('Permission denied') || raw.contains('INTERNET'))
      return 'Missing network permission.\nCheck AndroidManifest.xml.';
    if (raw.contains('Failed host lookup') || raw.contains('No address'))
      return 'Cannot resolve server.\nCheck your connection.';
    if (raw.contains('SocketException')) return 'No internet connection.';
    if (raw.contains('timeout') || raw.contains('TimeoutException'))
      return 'Timeout — server not responding.\nTry a different server.';
    if (raw.contains('HandshakeException'))
      return 'SSL error — check your device date/time.';
    if (raw.contains('unreachable'))
      return 'Server unreachable.\nEnable auto-fallback or pick another server.';
    return 'Error: $raw';
  }

  // ── Root build ─────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      backgroundColor: t.colorScheme.surface,
      body: SafeArea(
        child: IndexedStack(
          index: _tabIndex,
          children: [
            _buildDashboard(t),
            _buildHistory(t),
            const SettingsScreen(),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (i) => setState(() => _tabIndex = i),
        backgroundColor: t.colorScheme.surface,
        indicatorColor: t.colorScheme.primaryContainer.withOpacity(0.5),
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

  // ══════════════════════════════════════════════════════════════════════════
  // DASHBOARD TAB
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildDashboard(ThemeData t) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildTopBar(t),
          if (kIsWeb) ...[const SizedBox(height: 6), _webBanner(t)],
          _errorBanner(t),
          Expanded(child: _buildGaugeArea(t)),
          _buildPhasePills(t),
          const SizedBox(height: 10),
          _buildProgressBar(t),
          const SizedBox(height: 10),
          _buildLiveChart(t),
          const SizedBox(height: 12),
          _buildStatsRow(t),
          const SizedBox(height: 10),
          _buildDurationChips(t),
          const SizedBox(height: 8),
          _buildQuickOptions(t),   // server picker + unit toggle
          const SizedBox(height: 10),
          _buildStartButton(t),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  // ── Top bar — app name, location chip, status badge ─────────────────────
  Widget _buildTopBar(ThemeData t) {
    return Row(children: [
      Text('JITTER', style: t.textTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.w900,
        letterSpacing: 3.5,
        color: t.colorScheme.primary,
      )),
      const Spacer(),

      // Location chip — tap to refresh
      ValueListenableBuilder<bool>(
        valueListenable: locationFetchingNotifier,
        builder: (_, fetching, __) => ValueListenableBuilder<String>(
          valueListenable: userLocationNotifier,
          builder: (_, loc, __) => ValueListenableBuilder<String>(
            valueListenable: ispNameNotifier,
            builder: (_, isp, __) => GestureDetector(
              onTap: fetching ? null : _fetchAndUpdateLocation,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: fetching
                      ? t.colorScheme.secondaryContainer.withOpacity(0.28)
                      : t.colorScheme.secondaryContainer.withOpacity(0.45),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: t.colorScheme.secondary.withOpacity(0.22)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  SizedBox(
                    width: 12, height: 12,
                    child: fetching
                        ? CircularProgressIndicator(
                            strokeWidth: 1.5,
                            color: t.colorScheme.secondary,
                          )
                        : Icon(Icons.place_rounded, size: 12,
                            color: t.colorScheme.secondary),
                  ),
                  const SizedBox(width: 4),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(
                      fetching
                          ? 'Detecting…'
                          : loc.isEmpty
                              ? 'Unknown location'
                              : loc,
                      style: t.textTheme.labelSmall?.copyWith(
                        color: (fetching || loc.isEmpty)
                            ? t.colorScheme.onSurface.withOpacity(0.38)
                            : t.colorScheme.onSecondaryContainer,
                        fontWeight: FontWeight.w600,
                        fontSize: 11,
                      ),
                    ),
                    if (isp.isNotEmpty && !fetching)
                      Text(isp,
                          style: t.textTheme.labelSmall?.copyWith(
                            fontSize: 9,
                            color: t.colorScheme.onSurface.withOpacity(0.4),
                          )),
                  ]),
                  const SizedBox(width: 3),
                  if (!fetching)
                    Icon(Icons.refresh_rounded, size: 10,
                        color: t.colorScheme.onSurface.withOpacity(0.28)),
                ]),
              ),
            ),
          ),
        ),
      ),

      const SizedBox(width: 8),

      // Status badge with pulsing dot
      ValueListenableBuilder<bool>(
        valueListenable: _testingNf,
        builder: (_, testing, __) => ValueListenableBuilder<String>(
          valueListenable: _phaseNf,
          builder: (_, phase, __) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: testing
                  ? t.colorScheme.errorContainer.withOpacity(0.18)
                  : t.colorScheme.primaryContainer.withOpacity(0.18),
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
                            .withOpacity(0.4 + _pulse.value * 0.6)
                        : t.colorScheme.primary
                            .withOpacity(0.4 + _pulse.value * 0.6),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(phase,
                  style: t.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.bold, letterSpacing: 0.8)),
            ]),
          ),
        ),
      ),
    ]);
  }

  // ── Gauge — arc + center speed display ───────────────────────────────────
  Widget _buildGaugeArea(ThemeData t) {
    return Center(
      child: LayoutBuilder(builder: (_, box) {
        final size = min(box.maxWidth, box.maxHeight).clamp(160.0, 270.0);
        return ValueListenableBuilder<double>(
          valueListenable: _speedNf,
          builder: (_, mbps, __) => ValueListenableBuilder<bool>(
            valueListenable: speedUnitMbpsNotifier,
            builder: (_, isMbps, __) {
              final displayVal = isMbps ? mbps : mbps / 8;
              return Stack(alignment: Alignment.center, children: [
                SizedBox(
                  width: size, height: size,
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.0, end: mbps),
                    duration: const Duration(milliseconds: 350),
                    curve: Curves.easeOut,
                    builder: (_, animMbps, __) => CustomPaint(
                      painter: _ArcGaugePainter(
                        speedMbps:    animMbps,
                        maxSpeedMbps: 1000.0,
                        trackColor:   t.colorScheme.onSurface.withOpacity(0.08),
                        accentColor:  t.colorScheme.primary,
                      ),
                    ),
                  ),
                ),
                Column(mainAxisSize: MainAxisSize.min, children: [
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.0, end: displayVal),
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOut,
                    builder: (_, v, __) => Text(
                      v >= 100 ? v.toStringAsFixed(0) : v.toStringAsFixed(1),
                      style: t.textTheme.displayMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        letterSpacing: -2,
                        height: 1.0,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(isMbps ? 'Mb/s' : 'MB/s',
                      style: t.textTheme.labelMedium?.copyWith(
                        color:         t.colorScheme.primary,
                        fontWeight:    FontWeight.bold,
                        letterSpacing: 1.5,
                      )),
                  const SizedBox(height: 8),
                  ValueListenableBuilder<int>(
                    valueListenable: selectedServerNotifier,
                    builder: (_, si, __) {
                      final srv = InternetSpeedService.servers[
                          InternetSpeedService.resolveServerIndex(si)];
                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 3),
                        decoration: BoxDecoration(
                          color: t.colorScheme.onSurface.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${srv.flag}  ${srv.location}  ·  ${srv.provider}',
                          style: t.textTheme.labelSmall?.copyWith(
                            color:    t.colorScheme.onSurface.withOpacity(0.42),
                            fontSize: 10,
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 4),
                  ValueListenableBuilder<String>(
                    valueListenable: ispNameNotifier,
                    builder: (_, isp, __) {
                      if (isp.isEmpty) return const SizedBox.shrink();
                      return Text(
                        '📶  $isp',
                        style: t.textTheme.labelSmall?.copyWith(
                          color:    t.colorScheme.onSurface.withOpacity(0.32),
                          fontSize: 10,
                        ),
                      );
                    },
                  ),
                ]),
              ]);
            },
          ),
        );
      }),
    );
  }

  // ── Phase pills — PING / DOWNLOAD / UPLOAD ───────────────────────────────
  Widget _buildPhasePills(ThemeData t) {
    const phases = ['PING', 'DOWNLOAD', 'UPLOAD'];
    return ValueListenableBuilder<String>(
      valueListenable: _phaseNf,
      builder: (_, phase, __) {
        final activeIdx = phases.indexOf(phase);
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(phases.length, (i) {
            final isActive = phase == phases[i];
            final isDone   = activeIdx > i;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 5),
                decoration: BoxDecoration(
                  color: isActive
                      ? t.colorScheme.primaryContainer.withOpacity(0.55)
                      : isDone
                          ? t.colorScheme.primary.withOpacity(0.07)
                          : t.colorScheme.onSurface.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isActive
                        ? t.colorScheme.primary.withOpacity(0.35)
                        : Colors.transparent,
                  ),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (isDone) ...[
                    Icon(Icons.check_rounded, size: 10,
                        color: t.colorScheme.primary.withOpacity(0.7)),
                    const SizedBox(width: 3),
                  ],
                  Text(phases[i],
                      style: t.textTheme.labelSmall?.copyWith(
                        fontWeight: isActive ? FontWeight.w800 : FontWeight.w400,
                        letterSpacing: 0.6,
                        color: isActive
                            ? t.colorScheme.primary
                            : isDone
                                ? t.colorScheme.primary.withOpacity(0.5)
                                : t.colorScheme.onSurface.withOpacity(0.28),
                      )),
                ]),
              ),
            );
          }),
        );
      },
    );
  }

  // ── Progress bar — indeterminate in infinite mode ────────────────────────
  Widget _buildProgressBar(ThemeData t) {
    return ValueListenableBuilder<double>(
      valueListenable: _progressNf,
      builder: (_, progress, __) => ValueListenableBuilder<bool>(
        valueListenable: _testingNf,
        builder: (_, testing, __) => ValueListenableBuilder<String>(
          valueListenable: _phaseNf,
          builder: (_, phase, __) {
            // Use indeterminate bar during active phases in infinite mode
            final isInfinite = testDurationSecsNotifier.value == 0;
            final activePhase =
                phase == 'DOWNLOAD' || phase == 'UPLOAD' || phase == 'PING';
            final indeterminate = isInfinite && testing && activePhase;
            return ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: indeterminate
                  ? LinearProgressIndicator(
                      minHeight:       5,
                      backgroundColor: t.colorScheme.onSurface.withOpacity(0.07),
                      valueColor:      AlwaysStoppedAnimation(t.colorScheme.primary),
                    )
                  : TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0.0, end: progress),
                      duration: const Duration(milliseconds: 500),
                      curve: Curves.easeOut,
                      builder: (_, anim, __) => LinearProgressIndicator(
                        value:           anim,
                        minHeight:       5,
                        backgroundColor: t.colorScheme.onSurface.withOpacity(0.07),
                        valueColor:
                            AlwaysStoppedAnimation(t.colorScheme.primary),
                      ),
                    ),
            );
          },
        ),
      ),
    );
  }

  // ── Live speed chart ──────────────────────────────────────────────────────
  Widget _buildLiveChart(ThemeData t) {
    return SizedBox(
      height: 46,
      child: ValueListenableBuilder<List<double>>(
        valueListenable: _pointsNf,
        builder: (_, pts, __) => ValueListenableBuilder<String>(
          valueListenable: _phaseNf,
          builder: (_, phase, __) {
            final color = phase == 'UPLOAD'
                ? t.colorScheme.secondary
                : t.colorScheme.primary;
            return ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: CustomPaint(
                painter: _ChartPainter(points: pts, color: color),
              ),
            );
          },
        ),
      ),
    );
  }

  // ── Stats row — DL / UL / PING / JITTER ──────────────────────────────────
  Widget _buildStatsRow(ThemeData t) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color:  t.colorScheme.onSurface.withOpacity(0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.colorScheme.onSurface.withOpacity(0.07)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _statBlock(
            icon:      Icons.arrow_downward_rounded,
            label:     'DOWN',
            iconColor: t.colorScheme.primary,
            child: ValueListenableBuilder<double>(
              valueListenable: _dlNf,
              builder: (_, v, __) => ValueListenableBuilder<bool>(
                valueListenable: speedUnitMbpsNotifier,
                builder: (_, isMbps, __) {
                  final disp = isMbps ? v : v / 8;
                  return _SpeedText(
                    value: disp >= 100 ? disp.toStringAsFixed(0) : disp.toStringAsFixed(1),
                    unit:  isMbps ? 'Mb/s' : 'MB/s',
                    color: t.colorScheme.primary,
                    t:     t,
                  );
                },
              ),
            ),
            t: t,
          ),
          _vDivider(t),
          _statBlock(
            icon:      Icons.arrow_upward_rounded,
            label:     'UP',
            iconColor: t.colorScheme.secondary,
            child: ValueListenableBuilder<double>(
              valueListenable: _ulNf,
              builder: (_, v, __) => ValueListenableBuilder<bool>(
                valueListenable: speedUnitMbpsNotifier,
                builder: (_, isMbps, __) {
                  final disp = isMbps ? v : v / 8;
                  return _SpeedText(
                    value: disp >= 100 ? disp.toStringAsFixed(0) : disp.toStringAsFixed(1),
                    unit:  isMbps ? 'Mb/s' : 'MB/s',
                    color: t.colorScheme.secondary,
                    t:     t,
                  );
                },
              ),
            ),
            t: t,
          ),
          _vDivider(t),
          _statBlock(
            icon:      Icons.network_ping_rounded,
            label:     'PING',
            iconColor: t.colorScheme.tertiary,
            child: ValueListenableBuilder<int>(
              valueListenable: _pingNf,
              builder: (_, v, __) {
                final color = _pingColorFor(v, context);
                return _SpeedText(value: '$v', unit: 'ms', color: color, t: t);
              },
            ),
            t: t,
          ),
          _vDivider(t),
          _statBlock(
            icon:      Icons.waves_rounded,
            label:     'JITTER',
            iconColor: t.colorScheme.error,
            child: ValueListenableBuilder<int>(
              valueListenable: _jitterNf,
              builder: (_, v, __) {
                final color = _jitterColorFor(v, context);
                return _SpeedText(value: '$v', unit: 'ms', color: color, t: t);
              },
            ),
            t: t,
          ),
        ],
      ),
    );
  }

  Widget _statBlock({
    required IconData icon,
    required String label,
    required Color iconColor,
    required Widget child,
    required ThemeData t,
  }) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 11, color: iconColor.withOpacity(0.65)),
        const SizedBox(width: 3),
        Text(label, style: TextStyle(
          fontSize:      9,
          fontWeight:    FontWeight.bold,
          letterSpacing: 0.8,
          color:         iconColor.withOpacity(0.65),
        )),
      ]),
      const SizedBox(height: 4),
      child,
    ]);
  }

  Widget _vDivider(ThemeData t) => Container(
    height: 30, width: 1,
    color: t.colorScheme.onSurface.withOpacity(0.07),
  );

  // ── Duration chips ────────────────────────────────────────────────────────
  Widget _buildDurationChips(ThemeData t) {
    return ValueListenableBuilder<int>(
      valueListenable: testDurationSecsNotifier,
      builder: (_, cur, __) => ValueListenableBuilder<bool>(
        valueListenable: _testingNf,
        builder: (_, testing, __) => Row(children: [
          Text('Duration:', style: t.textTheme.labelSmall?.copyWith(
            color:      t.colorScheme.onSurface.withOpacity(0.4),
            fontWeight: FontWeight.w500,
          )),
          const SizedBox(width: 8),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _kDurationSteps.map((secs) {
                  final sel   = secs == cur;
                  final label = secs == 0
                      ? '∞'
                      : secs == 60
                          ? '1 min'
                          : '${secs}s';
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: GestureDetector(
                      onTap: testing ? null : () => setTestDuration(secs),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 11, vertical: 5),
                        decoration: BoxDecoration(
                          color: sel
                              ? t.colorScheme.primary.withOpacity(0.12)
                              : t.colorScheme.onSurface.withOpacity(0.04),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: sel
                                ? t.colorScheme.primary.withOpacity(0.4)
                                : t.colorScheme.onSurface.withOpacity(0.08),
                          ),
                        ),
                        child: Text(
                          label,
                          style: t.textTheme.labelSmall?.copyWith(
                            fontWeight: sel ? FontWeight.w800 : FontWeight.w400,
                            color: sel
                                ? t.colorScheme.primary
                                : t.colorScheme.onSurface.withOpacity(
                                    testing ? 0.18 : 0.5),
                          ),
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

  // ── Quick options row — server chip + unit toggle ─────────────────────────
  Widget _buildQuickOptions(ThemeData t) {
    return ValueListenableBuilder<bool>(
      valueListenable: _testingNf,
      builder: (_, testing, __) => Row(children: [
        // Server chip — opens bottom sheet picker
        ValueListenableBuilder<int>(
          valueListenable: selectedServerNotifier,
          builder: (_, si, __) {
            final srv = InternetSpeedService.servers[
                InternetSpeedService.resolveServerIndex(si)];
            return GestureDetector(
              onTap: testing ? null : _showServerSheet,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: t.colorScheme.onSurface.withOpacity(testing ? 0.03 : 0.06),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: t.colorScheme.onSurface.withOpacity(0.09)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(srv.flag, style: const TextStyle(fontSize: 13)),
                  const SizedBox(width: 5),
                  Text(srv.name,
                      style: t.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: t.colorScheme.onSurface
                            .withOpacity(testing ? 0.25 : 0.7),
                      )),
                  const SizedBox(width: 3),
                  Icon(Icons.expand_more_rounded,
                      size: 13,
                      color: t.colorScheme.onSurface
                          .withOpacity(testing ? 0.2 : 0.4)),
                ]),
              ),
            );
          },
        ),
        const Spacer(),
        // Unit toggle — Mb/s vs MB/s
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

  // Small toggle chip used for the unit selector
  Widget _unitChip(
      String label, bool selected, VoidCallback? onTap, ThemeData t) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected
              ? t.colorScheme.primary.withOpacity(0.12)
              : t.colorScheme.onSurface.withOpacity(0.04),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? t.colorScheme.primary.withOpacity(0.4)
                : t.colorScheme.onSurface.withOpacity(0.08),
          ),
        ),
        child: Text(label,
            style: t.textTheme.labelSmall?.copyWith(
              fontWeight: selected ? FontWeight.w800 : FontWeight.w400,
              color: selected
                  ? t.colorScheme.primary
                  : t.colorScheme.onSurface.withOpacity(onTap == null ? 0.2 : 0.5),
            )),
      ),
    );
  }

  // Bottom sheet with the full server list
  void _showServerSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final t       = Theme.of(ctx);
        final servers = InternetSpeedService.availableServers;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Text('Server', style: t.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold, letterSpacing: 1)),
                  const Spacer(),
                  // Auto-fallback toggle inline in the sheet
                  ValueListenableBuilder<bool>(
                    valueListenable: autoFallbackNotifier,
                    builder: (_, v, __) => Row(children: [
                      Text('Auto-fallback',
                          style: t.textTheme.labelSmall?.copyWith(
                              color: t.colorScheme.onSurface.withOpacity(0.55))),
                      const SizedBox(width: 6),
                      Switch(
                        value:     v,
                        onChanged: setAutoFallback,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ]),
                  ),
                ]),
                const SizedBox(height: 12),
                ...List.generate(servers.length, (i) {
                  final srv     = servers[i];
                  // Map back to the full servers list index
                  final realIdx = InternetSpeedService.servers.indexOf(srv);
                  return ValueListenableBuilder<int>(
                    valueListenable: selectedServerNotifier,
                    builder: (_, si, __) {
                      final selected = si == realIdx;
                      return ListTile(
                        leading: Text(srv.flag,
                            style: const TextStyle(fontSize: 20)),
                        title: Text(srv.name),
                        subtitle: Text('${srv.location}  —  ${srv.provider}',
                            style: t.textTheme.bodySmall?.copyWith(
                                color: t.colorScheme.onSurface.withOpacity(0.5))),
                        trailing: selected
                            ? Icon(Icons.check_rounded,
                                color: t.colorScheme.primary)
                            : null,
                        selected: selected,
                        selectedTileColor:
                            t.colorScheme.primary.withOpacity(0.06),
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
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── Start / Stop button ───────────────────────────────────────────────────
  Widget _buildStartButton(ThemeData t) {
    return ValueListenableBuilder<bool>(
      valueListenable: _testingNf,
      builder: (_, testing, __) => SizedBox(
        height: 54,
        child: testing
            ? OutlinedButton(
                // Tap to request stop — the test loop checks this flag
                onPressed: () => setState(() => _stopRequested = true),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(
                      color: t.colorScheme.error.withOpacity(0.4), width: 1.5),
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
                      color: t.colorScheme.error.withOpacity(0.5),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text('STOP', style: TextStyle(
                    fontWeight:    FontWeight.bold,
                    letterSpacing: 2.0,
                    color: t.colorScheme.error.withOpacity(0.8),
                  )),
                ]),
              )
            : FilledButton(
                onPressed: _runTest,
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(100)),
                  backgroundColor: t.colorScheme.primary,
                ),
                child: const Text('START TEST', style: TextStyle(
                  fontWeight:    FontWeight.bold,
                  letterSpacing: 2.0,
                )),
              ),
      ),
    );
  }

  // ── Web mode notice ───────────────────────────────────────────────────────
  Widget _webBanner(ThemeData t) => Container(
    margin:  const EdgeInsets.only(bottom: 6),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
    decoration: BoxDecoration(
      color:        t.colorScheme.tertiaryContainer.withOpacity(0.35),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: t.colorScheme.tertiary.withOpacity(0.35)),
    ),
    child: Row(children: [
      Icon(Icons.public_rounded, size: 15, color: t.colorScheme.tertiary),
      const SizedBox(width: 8),
      Expanded(child: Text(
        'Browser mode — only Cloudflare servers are available.',
        style: t.textTheme.labelSmall?.copyWith(
            color: t.colorScheme.onTertiaryContainer, height: 1.4),
      )),
    ]),
  );

  // ── Error banner ──────────────────────────────────────────────────────────
  Widget _errorBanner(ThemeData t) => ValueListenableBuilder<String?>(
    valueListenable: _errorNf,
    builder: (_, err, __) {
      if (err == null) return const SizedBox.shrink();
      return Container(
        margin:  const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color:        t.colorScheme.errorContainer.withOpacity(0.22),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: t.colorScheme.error.withOpacity(0.4)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.wifi_off_rounded, size: 17, color: t.colorScheme.error),
          const SizedBox(width: 10),
          Expanded(child: Text(err, style: t.textTheme.bodySmall?.copyWith(
            color: t.colorScheme.onErrorContainer, height: 1.5))),
        ]),
      );
    },
  );

  // ══════════════════════════════════════════════════════════════════════════
  // HISTORY TAB
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildHistory(ThemeData t) {
    // Group entries by user location
    final grouped = <String, List<_IndexedEntry>>{};
    for (int i = 0; i < _history.length; i++) {
      final loc = _history[i].userLocation.isEmpty
          ? '📍 Unknown location'
          : _history[i].userLocation;
      grouped.putIfAbsent(loc, () => []).add(_IndexedEntry(_history[i], i));
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('METRICS LOGS', style: t.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold, letterSpacing: 1.5)),
            if (_history.isNotEmpty)
              Text(
                '${_history.length} test${_history.length > 1 ? 's' : ''}'
                '  ·  ${grouped.length} location${grouped.length > 1 ? 's' : ''}',
                style: t.textTheme.bodySmall?.copyWith(
                    color: t.colorScheme.onSurface.withOpacity(0.4))),
          ]),
          if (_history.isNotEmpty)
            TextButton.icon(
              onPressed: _confirmClearHistory,
              icon:  const Icon(Icons.delete_sweep_outlined, size: 16),
              label: const Text('Clear all'),
              style: TextButton.styleFrom(
                foregroundColor: t.colorScheme.error,
                visualDensity:   VisualDensity.compact,
              ),
            ),
        ]),
        const SizedBox(height: 16),
        Expanded(
          child: _history.isEmpty
              ? _emptyLogs(t)
              : ListView(
                  children: [
                    for (final group in grouped.entries)
                      _buildLocationGroup(group.key, group.value, t),
                    const SizedBox(height: 12),
                  ],
                ),
        ),
      ]),
    );
  }

  Widget _buildLocationGroup(
      String location, List<_IndexedEntry> entries, ThemeData t) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 10),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color:        t.colorScheme.primaryContainer.withOpacity(0.45),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.place_rounded, size: 12, color: t.colorScheme.primary),
              const SizedBox(width: 5),
              Text(location, style: t.textTheme.labelSmall?.copyWith(
                color:         t.colorScheme.primary,
                fontWeight:    FontWeight.w800,
                letterSpacing: 0.4,
              )),
            ]),
          ),
          const SizedBox(width: 8),
          Expanded(child: Divider(
              color: t.colorScheme.onSurface.withOpacity(0.09))),
          const SizedBox(width: 8),
          Text(
            '${entries.length} test${entries.length > 1 ? 's' : ''}',
            style: t.textTheme.labelSmall?.copyWith(
                color: t.colorScheme.onSurface.withOpacity(0.28)),
          ),
        ]),
      ),
      for (final ie in entries)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _LogCard(
            entry:    ie.entry,
            onDelete: () => _deleteEntry(ie.index),
          ),
        ),
      const SizedBox(height: 6),
    ]);
  }

  Widget _emptyLogs(ThemeData t) => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 72, height: 72,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: t.colorScheme.onSurface.withOpacity(0.06),
        ),
        child: Icon(Icons.wifi_tethering_outlined, size: 32,
            color: t.colorScheme.onSurface.withOpacity(0.22)),
      ),
      const SizedBox(height: 16),
      Text('No tests recorded',
          style: t.textTheme.bodyMedium?.copyWith(
              color:      t.colorScheme.onSurface.withOpacity(0.4),
              fontWeight: FontWeight.w500)),
      const SizedBox(height: 4),
      Text('Run a test to see results here.',
          style: t.textTheme.bodySmall?.copyWith(
              color: t.colorScheme.onSurface.withOpacity(0.27))),
    ]),
  );

  Future<void> _confirmClearHistory() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title:   const Text('Clear logs'),
        content: const Text('Delete all results? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Delete',
                style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
          ),
        ],
      ),
    );
    if (ok == true) await _clearHistory();
  }

  // Date and time helpers for log cards
  static String _fmtDate(String ts) {
    try {
      final d = DateTime.parse(ts.length == 16 ? '${ts}:00' : ts);
      const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      return '${d.day} ${months[d.month - 1]}. ${d.year}';
    } catch (_) {
      return ts.substring(0, min(10, ts.length));
    }
  }

  static String _fmtTime(String ts) {
    try { return ts.substring(11, 16); } catch (_) { return ''; }
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// REUSABLE WIDGETS
// ══════════════════════════════════════════════════════════════════════════════

// Speed value + unit label aligned on baseline
class _SpeedText extends StatelessWidget {
  final String value;
  final String unit;
  final Color color;
  final ThemeData t;
  const _SpeedText({
    required this.value, required this.unit,
    required this.color, required this.t,
  });

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.baseline,
    textBaseline: TextBaseline.alphabetic,
    children: [
      Text(value, style: t.textTheme.bodyMedium?.copyWith(
        color:        color,
        fontWeight:   FontWeight.w800,
        fontFeatures: const [FontFeature.tabularFigures()],
      )),
      const SizedBox(width: 2),
      Text(unit, style: t.textTheme.labelSmall?.copyWith(
        color:      color.withOpacity(0.7),
        fontWeight: FontWeight.w600,
      )),
    ],
  );
}

// History log card — swipe left to delete
class _LogCard extends StatelessWidget {
  final _LogEntry entry;
  final VoidCallback onDelete;
  const _LogCard({required this.entry, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final t     = Theme.of(context);
    final grade = _gradeDl(entry.dl);
    final gc    = grade.color;

    return Dismissible(
      key:       ValueKey('${entry.timestamp}_${entry.server}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color:        t.colorScheme.errorContainer.withOpacity(0.6),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Icon(Icons.delete_outline, color: t.colorScheme.error),
      ),
      onDismissed: (_) => onDelete(),
      child: Container(
        decoration: BoxDecoration(
          color:        t.colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: t.colorScheme.onSurface.withOpacity(0.08)),
          boxShadow: [
            BoxShadow(
              color:      t.colorScheme.shadow.withOpacity(0.04),
              blurRadius: 8,
              offset:     const Offset(0, 2),
            ),
          ],
        ),
        child: Column(children: [

          // Performance grade banner
          Container(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
            decoration: BoxDecoration(
              color: gc.withOpacity(0.07),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(children: [
              Icon(grade.icon, size: 13, color: gc),
              const SizedBox(width: 6),
              Text(grade.label, style: t.textTheme.labelSmall?.copyWith(
                color:         gc,
                fontWeight:    FontWeight.w800,
                letterSpacing: 1.0,
              )),
              const Spacer(),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                SizedBox(
                  width: 64, height: 4,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value:           (entry.dl / 1000).clamp(0.0, 1.0),
                      backgroundColor: gc.withOpacity(0.13),
                      valueColor:      AlwaysStoppedAnimation(gc),
                      minHeight:       4,
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${entry.dl.toStringAsFixed(0)} ${entry.unit}',
                  style: TextStyle(
                    fontSize:     9,
                    color:        gc.withOpacity(0.75),
                    fontWeight:   FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ]),
            ]),
          ),

          // Server info + timestamp
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
            child: Row(children: [
              Container(
                width: 38, height: 38,
                decoration: BoxDecoration(
                  color:  t.colorScheme.primaryContainer.withOpacity(0.28),
                  shape:  BoxShape.circle,
                ),
                child: Center(child: Text(entry.flag,
                    style: const TextStyle(fontSize: 17))),
              ),
              const SizedBox(width: 10),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Flexible(child: Text(entry.server,
                        style: t.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700),
                        overflow: TextOverflow.ellipsis)),
                    if (entry.provider.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: t.colorScheme.secondaryContainer
                              .withOpacity(0.5),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(entry.provider,
                            style: t.textTheme.labelSmall?.copyWith(
                              color:      t.colorScheme.onSecondaryContainer,
                              fontWeight: FontWeight.w700,
                              fontSize:   9,
                            )),
                      ),
                    ],
                  ]),
                  if (entry.serverLocation.isNotEmpty)
                    Text(entry.serverLocation,
                        style: t.textTheme.bodySmall?.copyWith(
                            color: t.colorScheme.onSurface.withOpacity(0.4))),
                ],
              )),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(_fmtDate(entry.timestamp),
                    style: t.textTheme.labelSmall?.copyWith(
                        color:      t.colorScheme.onSurface.withOpacity(0.55),
                        fontWeight: FontWeight.w500)),
                Text(_fmtTime(entry.timestamp),
                    style: t.textTheme.labelSmall?.copyWith(
                        color:    t.colorScheme.onSurface.withOpacity(0.3),
                        fontSize: 10)),
              ]),
            ]),
          ),

          const SizedBox(height: 10),
          Divider(height: 1, color: t.colorScheme.onSurface.withOpacity(0.06)),

          // Metrics row
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            child: Row(children: [
              _MetricChip(
                icon:  Icons.arrow_downward_rounded,
                value: entry.dl.toStringAsFixed(1),
                unit:  entry.unit,
                label: 'DOWN',
                color: _dlColorFor(entry.dl, context),
              ),
              const SizedBox(width: 6),
              _MetricChip(
                icon:  Icons.arrow_upward_rounded,
                value: entry.ul.toStringAsFixed(1),
                unit:  entry.unit,
                label: 'UP',
                color: Theme.of(context).colorScheme.secondary,
              ),
              const Spacer(),
              _PingJitterPill(
                icon:  Icons.network_ping_rounded,
                label: 'PING',
                value: entry.ping,
                color: _pingColorFor(entry.ping, context),
                t:     t,
              ),
              const SizedBox(width: 6),
              _PingJitterPill(
                icon:  Icons.waves_rounded,
                label: 'JITTER',
                value: entry.jitter,
                color: _jitterColorFor(entry.jitter, context),
                t:     t,
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  static Color _dlColorFor(double mbps, BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (mbps >= 500) return const Color(0xFF1B5E20);
    if (mbps >= 200) return const Color(0xFF2E7D32);
    if (mbps >= 100) return const Color(0xFF1565C0);
    if (mbps >= 30)  return const Color(0xFFE65100);
    return cs.error;
  }

  static String _fmtDate(String ts) {
    try {
      final d = DateTime.parse(ts.length == 16 ? '${ts}:00' : ts);
      const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      return '${d.day} ${months[d.month - 1]}. ${d.year}';
    } catch (_) {
      return ts.substring(0, min(10, ts.length));
    }
  }

  static String _fmtTime(String ts) {
    try { return ts.substring(11, 16); } catch (_) { return ''; }
  }
}

// ── Ping / jitter pill widget ──────────────────────────────────────────────
class _PingJitterPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final int value;
  final Color color;
  final ThemeData t;
  const _PingJitterPill({
    required this.icon, required this.label,
    required this.value, required this.color, required this.t,
  });
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color:        color.withOpacity(0.09),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: color.withOpacity(0.22)),
    ),
    child: Column(children: [
      Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 11, color: color),
        const SizedBox(width: 4),
        Text('$value ms',
            style: t.textTheme.bodySmall?.copyWith(
              color:        color,
              fontWeight:   FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            )),
      ]),
      Text(label, style: t.textTheme.labelSmall?.copyWith(
          color:    color.withOpacity(0.6),
          fontSize: 9,
          letterSpacing: 0.8)),
    ]),
  );
}

// ── DL / UL metric chip ────────────────────────────────────────────────────
class _MetricChip extends StatelessWidget {
  final IconData icon;
  final String value, unit, label;
  final Color color;
  const _MetricChip({
    required this.icon,  required this.value,
    required this.unit,  required this.label,
    required this.color,
  });
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color:        color.withOpacity(0.09),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.22)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 5),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('$value $unit', style: t.textTheme.bodySmall?.copyWith(
            color:        color,
            fontWeight:   FontWeight.w700,
            fontFeatures: const [FontFeature.tabularFigures()],
          )),
          Text(label, style: t.textTheme.labelSmall?.copyWith(
              color:         color.withOpacity(0.6),
              fontSize:      9,
              letterSpacing: 0.8)),
        ]),
      ]),
    );
  }
}

// ── Arc gauge painter ──────────────────────────────────────────────────────
class _ArcGaugePainter extends CustomPainter {
  final double speedMbps;
  final double maxSpeedMbps;
  final Color trackColor;
  final Color accentColor;

  const _ArcGaugePainter({
    required this.speedMbps,
    required this.maxSpeedMbps,
    required this.trackColor,
    required this.accentColor,
  });

  static const double _startDeg = 150.0;
  static const double _sweepDeg = 240.0;

  @override
  void paint(Canvas canvas, Size size) {
    final cx     = size.width / 2;
    final cy     = size.height / 2;
    final radius = min(cx, cy) - 20;
    final rect   = Rect.fromCircle(center: Offset(cx, cy), radius: radius);

    const startRad = _startDeg * pi / 180;
    const sweepRad = _sweepDeg * pi / 180;
    const strokeW  = 16.0;

    // Background track
    canvas.drawArc(rect, startRad, sweepRad, false,
      Paint()
        ..color       = trackColor
        ..style       = PaintingStyle.stroke
        ..strokeWidth = strokeW
        ..strokeCap   = StrokeCap.round,
    );

    final progress = (speedMbps / maxSpeedMbps).clamp(0.0, 1.0);
    if (progress < 0.001) return;

    final (Color c1, Color c2) = _speedColors(speedMbps);
    final sweepActual = sweepRad * progress;

    // Colored arc with gradient
    canvas.drawArc(rect, startRad, sweepActual, false,
      Paint()
        ..style       = PaintingStyle.stroke
        ..strokeWidth = strokeW + 1
        ..strokeCap   = StrokeCap.round
        ..shader      = SweepGradient(
          colors:    [c1, c2],
          startAngle: startRad,
          endAngle:   startRad + sweepRad,
          tileMode:   TileMode.clamp,
        ).createShader(rect),
    );

    // Dot at the end of the arc
    final endAngle = startRad + sweepActual;
    final dx = cx + radius * cos(endAngle);
    final dy = cy + radius * sin(endAngle);
    canvas.drawCircle(Offset(dx, dy), 8,
        Paint()..color = c2..style = PaintingStyle.fill);
    canvas.drawCircle(Offset(dx, dy), 8,
        Paint()
          ..color       = Colors.white.withOpacity(0.55)
          ..style       = PaintingStyle.stroke
          ..strokeWidth = 2.5);

    // Scale tick marks
    final tickPaint = Paint()
      ..color       = trackColor.withOpacity(0.8)
      ..strokeWidth = 1.5
      ..style       = PaintingStyle.stroke;

    for (int i = 0; i <= 10; i++) {
      final a      = startRad + sweepRad * i / 10;
      final rOuter = radius - strokeW / 2 - 1;
      final rInner = rOuter - (i % 5 == 0 ? 9 : 5);
      canvas.drawLine(
        Offset(cx + rOuter * cos(a), cy + rOuter * sin(a)),
        Offset(cx + rInner * cos(a), cy + rInner * sin(a)),
        tickPaint,
      );
    }
  }

  static (Color, Color) _speedColors(double mbps) {
    if (mbps >= 200) return (const Color(0xFF1B5E20), const Color(0xFF66BB6A));
    if (mbps >= 50)  return (const Color(0xFF1565C0), const Color(0xFF42A5F5));
    if (mbps >= 10)  return (const Color(0xFFE65100), const Color(0xFFFFCA28));
    return (const Color(0xFFC62828), const Color(0xFFEF9A9A));
  }

  @override
  bool shouldRepaint(covariant _ArcGaugePainter old) =>
      old.speedMbps != speedMbps || old.accentColor != accentColor;
}

// ── Live speed chart painter ───────────────────────────────────────────────
class _ChartPainter extends CustomPainter {
  final List<double> points;
  final Color color;
  const _ChartPainter({required this.points, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    final maxV  = points.reduce(max).clamp(1.0, double.infinity);
    final stepX = size.width / (points.length - 1);
    double y(double v) => size.height - (v / maxV * size.height * 0.88);

    // Smooth curve through all data points
    final line = Path()..moveTo(0, y(points[0]));
    for (int i = 1; i < points.length; i++) {
      final x = i * stepX, px = (i - 1) * stepX, cx = (px + x) / 2;
      line.cubicTo(cx, y(points[i - 1]), cx, y(points[i]), x, y(points[i]));
    }

    // Filled area under the curve
    final fill = Path.from(line)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    canvas.drawPath(fill,
        Paint()..color = color.withOpacity(0.08)..style = PaintingStyle.fill);
    canvas.drawPath(line, Paint()
      ..color       = color.withOpacity(0.85)
      ..style       = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap   = StrokeCap.round
      ..strokeJoin  = StrokeJoin.round);
  }

  @override
  bool shouldRepaint(covariant _ChartPainter old) => old.points != points;
}