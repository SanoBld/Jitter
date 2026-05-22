import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../app_state.dart';
import '../services/internet_speed_service.dart';
import 'settings_screen.dart';

// ─── Performance grade ────────────────────────────────────────────────────────
enum _PerfGrade { excellent, veryGood, good, fair, slow, poor }

extension _PerfGradeX on _PerfGrade {
  String get label {
    switch (this) {
      case _PerfGrade.excellent: return 'EXCELLENT';
      case _PerfGrade.veryGood:  return 'TRÈS BON';
      case _PerfGrade.good:      return 'BON';
      case _PerfGrade.fair:      return 'MOYEN';
      case _PerfGrade.slow:      return 'LENT';
      case _PerfGrade.poor:      return 'TRÈS LENT';
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

Color _pingColorFor(int ms, BuildContext context) {
  if (ms == 0) return Theme.of(context).colorScheme.onSurface.withOpacity(0.3);
  if (ms <= 30)  return const Color(0xFF2E7D32);
  if (ms <= 80)  return const Color(0xFF1565C0);
  if (ms <= 150) return const Color(0xFFE65100);
  return Theme.of(context).colorScheme.error;
}

// ─── Log entry ────────────────────────────────────────────────────────────────
class _LogEntry {
  final String timestamp;
  final String flag;
  final String server;
  final String provider;
  final String serverLocation; // localisation du serveur
  final String userLocation;   // où était l'utilisateur
  final double dl;
  final double ul;
  final int    ping;
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
    required this.unit,
  });

  Map<String, dynamic> toJson() => {
    'ts': timestamp, 'flag': flag, 'server': server,
    'provider': provider, 'location': serverLocation,
    'userLocation': userLocation,
    'dl': dl, 'ul': ul, 'ping': ping, 'unit': unit,
  };

  factory _LogEntry.fromJson(Map<String, dynamic> j) => _LogEntry(
    timestamp:      j['ts'] as String,
    flag:           j['flag'] as String,
    server:         j['server'] as String,
    provider:       j['provider'] as String,
    serverLocation: j['location'] as String? ?? '',
    userLocation:   j['userLocation'] as String? ?? '',
    dl:             (j['dl'] as num).toDouble(),
    ul:             (j['ul'] as num).toDouble(),
    ping:           j['ping'] as int,
    unit:           j['unit'] as String,
  );

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
        timestamp:      ts, flag: flag, server: server,
        provider: '', serverLocation: '', userLocation: '',
        dl:    double.parse(dlMatch.group(1)!),
        ul:    ulMatch != null ? double.parse(ulMatch.group(1)!) : 0,
        ping:  pingMatch != null ? int.parse(pingMatch.group(1)!) : 0,
        unit:  dlMatch.group(2) ?? 'Mb/s',
      );
    } catch (_) { return null; }
  }
}

// ─── Index helper for grouped list ────────────────────────────────────────────
class _IndexedEntry {
  final _LogEntry entry;
  final int index;
  const _IndexedEntry(this.entry, this.index);
}

// ─── Duration steps ───────────────────────────────────────────────────────────
const _kDurationSteps = [10, 25, 50, 100, 200, 500];

// ═════════════════════════════════════════════════════════════════════════════
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {

  final _svc = InternetSpeedService();
  int _tabIndex = 0;

  final _speedNf    = ValueNotifier<double>(0.0);
  final _pingNf     = ValueNotifier<int>(0);
  final _dlNf       = ValueNotifier<double>(0.0);
  final _ulNf       = ValueNotifier<double>(0.0);
  final _testingNf  = ValueNotifier<bool>(false);
  final _phaseNf    = ValueNotifier<String>('READY');
  final _pointsNf   = ValueNotifier<List<double>>([]);
  final _progressNf = ValueNotifier<double>(0.0);
  final _errorNf    = ValueNotifier<String?>(null);

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
  }

  @override
  void dispose() {
    _pulse.dispose();
    _speedNf.dispose(); _pingNf.dispose();
    _dlNf.dispose();    _ulNf.dispose();
    _testingNf.dispose(); _phaseNf.dispose();
    _pointsNf.dispose(); _progressNf.dispose();
    _errorNf.dispose();
    super.dispose();
  }

  // ── Persistence ────────────────────────────────────────────────────────────
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

  // ── Helpers ────────────────────────────────────────────────────────────────
  String get _unit => speedUnitMbpsNotifier.value ? 'Mb/s' : 'MB/s';

  // ── Location dialog ─────────────────────────────────────────────────────────
  Future<void> _editLocation() async {
    final ctrl = TextEditingController(text: userLocationNotifier.value);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ma localisation'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
            hintText: 'Ex: Lyon, FR',
            prefixIcon: Icon(Icons.place_outlined),
            border: OutlineInputBorder(),
          ),
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (result != null) await setUserLocation(result);
  }

  // ── Run test ────────────────────────────────────────────────────────────────
  Future<void> _runTest() async {
    final rawIdx = selectedServerNotifier.value;
    final srv    = InternetSpeedService.resolveServerIndex(rawIdx);
    final sz     = downloadSizeMBNotifier.value;

    _testingNf.value  = true;
    _errorNf.value    = null;
    _speedNf.value    = 0;
    _dlNf.value       = 0;
    _ulNf.value       = 0;
    _pingNf.value     = 0;
    _pointsNf.value   = [];
    _progressNf.value = 0;

    try {
      _phaseNf.value    = 'PING';
      _pingNf.value     = await _svc.testPing(srv);
      _progressNf.value = 0.08;

      _phaseNf.value = 'DOWNLOAD';
      await for (final mbps in _svc.testDownloadSpeed(serverIndex: srv, maxMB: sz)) {
        _speedNf.value = mbps;
        _dlNf.value    = mbps;
        final pts = List<double>.from(_pointsNf.value)..add(mbps);
        if (pts.length > 50) pts.removeAt(0);
        _pointsNf.value   = pts;
        _progressNf.value = 0.08 + 0.57 * (pts.length / 50).clamp(0.0, 1.0);
      }

      _progressNf.value = 0.65;
      _pointsNf.value   = [];

      _phaseNf.value = 'UPLOAD';
      final ul          = await _svc.testUploadSpeed();
      _speedNf.value    = ul;
      _ulNf.value       = ul;
      _pointsNf.value   = [ul * 0.3, ul * 0.55, ul * 0.8, ul];
      _progressNf.value = 1.0;
      _phaseNf.value    = 'COMPLETED';

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
          unit:           _unit,
        );
        setState(() => _history.insert(0, entry));
        await _saveHistory();
      }
    } catch (e) {
      _phaseNf.value    = 'ERROR';
      _errorNf.value    = _friendlyError(e.toString());
      _progressNf.value = 0;
    } finally {
      _testingNf.value = false;
    }
  }

  String _friendlyError(String raw) {
    if (raw.contains('Failed to fetch') || raw.contains('CORS') ||
        raw.contains('cross-origin') || raw.contains('XMLHttpRequest'))
      return 'Erreur CORS — ce serveur bloque les requêtes navigateur.\n'
          'Utilisez un serveur Cloudflare ou lancez l\'APK Android.';
    if (raw.contains('Permission denied') || raw.contains('INTERNET'))
      return 'Permission réseau manquante.\nVérifiez AndroidManifest.xml.';
    if (raw.contains('Failed host lookup') || raw.contains('No address'))
      return 'Impossible de résoudre le serveur.\nVérifiez votre connexion.';
    if (raw.contains('SocketException')) return 'Pas de connexion internet.';
    if (raw.contains('timeout') || raw.contains('TimeoutException'))
      return 'Timeout — le serveur ne répond pas.\nEssayez un autre serveur.';
    if (raw.contains('HandshakeException'))
      return 'Erreur SSL — vérifiez la date/heure de l\'appareil.';
    return 'Erreur : $raw';
  }

  // ── Root build ──────────────────────────────────────────────────────────────
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
              icon: Icon(Icons.speed_outlined),
              selectedIcon: Icon(Icons.speed),
              label: 'Test'),
          NavigationDestination(
              icon: Icon(Icons.bar_chart_outlined),
              selectedIcon: Icon(Icons.bar_chart),
              label: 'Logs'),
          NavigationDestination(
              icon: Icon(Icons.tune_outlined),
              selectedIcon: Icon(Icons.tune),
              label: 'Settings'),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // DASHBOARD — Speed Test Screen
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
          // Gauge — flex fills available space
          Expanded(child: _buildGaugeArea(t)),
          // Phase pills
          _buildPhasePills(t),
          const SizedBox(height: 10),
          // Progress bar
          _buildProgressBar(t),
          const SizedBox(height: 10),
          // Live chart
          _buildLiveChart(t),
          const SizedBox(height: 12),
          // Stats row
          _buildStatsRow(t),
          const SizedBox(height: 12),
          // Duration chips
          _buildDurationChips(t),
          const SizedBox(height: 12),
          // Start button
          _buildStartButton(t),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  // ── Top bar ─────────────────────────────────────────────────────────────────
  Widget _buildTopBar(ThemeData t) {
    return Row(children: [
      // App brand
      Text('JITTER', style: t.textTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.w900,
        letterSpacing: 3.5,
        color: t.colorScheme.primary,
      )),
      const Spacer(),

      // Location chip — tappable
      ValueListenableBuilder<String>(
        valueListenable: userLocationNotifier,
        builder: (_, loc, __) => GestureDetector(
          onTap: _editLocation,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: t.colorScheme.secondaryContainer.withOpacity(0.45),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: t.colorScheme.secondary.withOpacity(0.22)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.place_rounded, size: 12,
                  color: t.colorScheme.secondary),
              const SizedBox(width: 4),
              Text(
                loc.isEmpty ? 'Ajouter lieu…' : loc,
                style: t.textTheme.labelSmall?.copyWith(
                  color: loc.isEmpty
                      ? t.colorScheme.onSurface.withOpacity(0.38)
                      : t.colorScheme.onSecondaryContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 3),
              Icon(Icons.edit_rounded, size: 10,
                  color: t.colorScheme.onSurface.withOpacity(0.28)),
            ]),
          ),
        ),
      ),

      const SizedBox(width: 8),

      // Status badge
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
                        ? t.colorScheme.error.withOpacity(0.4 + _pulse.value * 0.6)
                        : t.colorScheme.primary.withOpacity(0.4 + _pulse.value * 0.6),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(phase, style: t.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.bold, letterSpacing: 0.8)),
            ]),
          ),
        ),
      ),
    ]);
  }

  // ── Gauge ────────────────────────────────────────────────────────────────────
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
                // Arc gauge
                SizedBox(
                  width: size, height: size,
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.0, end: mbps),
                    duration: const Duration(milliseconds: 350),
                    curve: Curves.easeOut,
                    builder: (_, animMbps, __) => CustomPaint(
                      painter: _ArcGaugePainter(
                        speedMbps: animMbps,
                        maxSpeedMbps: 1000.0,
                        trackColor: t.colorScheme.onSurface.withOpacity(0.08),
                        accentColor: t.colorScheme.primary,
                      ),
                    ),
                  ),
                ),
                // Center display
                Column(mainAxisSize: MainAxisSize.min, children: [
                  // Speed number
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.0, end: displayVal),
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOut,
                    builder: (_, v, __) => Text(
                      v >= 100
                          ? v.toStringAsFixed(0)
                          : v.toStringAsFixed(1),
                      style: t.textTheme.displayMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        letterSpacing: -2,
                        height: 1.0,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  // Unit
                  Text(isMbps ? 'Mb/s' : 'MB/s',
                      style: t.textTheme.labelMedium?.copyWith(
                        color: t.colorScheme.primary,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.5,
                      )),
                  const SizedBox(height: 8),
                  // Server chip
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
                            color: t.colorScheme.onSurface.withOpacity(0.42),
                            fontSize: 10,
                          ),
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

  // ── Phase pills ──────────────────────────────────────────────────────────────
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

  // ── Progress bar ─────────────────────────────────────────────────────────────
  Widget _buildProgressBar(ThemeData t) {
    return ValueListenableBuilder<double>(
      valueListenable: _progressNf,
      builder: (_, progress, __) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.0, end: progress),
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOut,
        builder: (_, anim, __) => ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: anim,
            minHeight: 5,
            backgroundColor: t.colorScheme.onSurface.withOpacity(0.07),
            valueColor: AlwaysStoppedAnimation(t.colorScheme.primary),
          ),
        ),
      ),
    );
  }

  // ── Live chart ────────────────────────────────────────────────────────────────
  Widget _buildLiveChart(ThemeData t) {
    return SizedBox(
      height: 46,
      child: ValueListenableBuilder<List<double>>(
        valueListenable: _pointsNf,
        builder: (_, pts, __) => ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: CustomPaint(
            painter: _ChartPainter(points: pts, color: t.colorScheme.primary),
          ),
        ),
      ),
    );
  }

  // ── Stats row ─────────────────────────────────────────────────────────────────
  Widget _buildStatsRow(ThemeData t) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: t.colorScheme.onSurface.withOpacity(0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.colorScheme.onSurface.withOpacity(0.07)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          // Download
          _statBlock(
            icon: Icons.arrow_downward_rounded,
            label: 'DOWN',
            iconColor: t.colorScheme.primary,
            child: ValueListenableBuilder<double>(
              valueListenable: _dlNf,
              builder: (_, v, __) => ValueListenableBuilder<bool>(
                valueListenable: speedUnitMbpsNotifier,
                builder: (_, isMbps, __) {
                  final disp = isMbps ? v : v / 8;
                  return _SpeedText(
                    value: disp >= 100
                        ? disp.toStringAsFixed(0)
                        : disp.toStringAsFixed(1),
                    unit: isMbps ? 'Mb/s' : 'MB/s',
                    color: t.colorScheme.primary,
                    t: t,
                  );
                },
              ),
            ),
            t: t,
          ),

          _vDivider(t),

          // Upload
          _statBlock(
            icon: Icons.arrow_upward_rounded,
            label: 'UP',
            iconColor: t.colorScheme.secondary,
            child: ValueListenableBuilder<double>(
              valueListenable: _ulNf,
              builder: (_, v, __) => ValueListenableBuilder<bool>(
                valueListenable: speedUnitMbpsNotifier,
                builder: (_, isMbps, __) {
                  final disp = isMbps ? v : v / 8;
                  return _SpeedText(
                    value: disp >= 100
                        ? disp.toStringAsFixed(0)
                        : disp.toStringAsFixed(1),
                    unit: isMbps ? 'Mb/s' : 'MB/s',
                    color: t.colorScheme.secondary,
                    t: t,
                  );
                },
              ),
            ),
            t: t,
          ),

          _vDivider(t),

          // Ping
          _statBlock(
            icon: Icons.network_ping_rounded,
            label: 'PING',
            iconColor: t.colorScheme.tertiary,
            child: ValueListenableBuilder<int>(
              valueListenable: _pingNf,
              builder: (_, v, __) {
                final color = _pingColorFor(v, context);
                return _SpeedText(
                  value: '$v',
                  unit: 'ms',
                  color: color,
                  t: t,
                );
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
          fontSize: 9,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.8,
          color: iconColor.withOpacity(0.65),
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

  // ── Duration chips ────────────────────────────────────────────────────────────
  Widget _buildDurationChips(ThemeData t) {
    return ValueListenableBuilder<int>(
      valueListenable: downloadSizeMBNotifier,
      builder: (_, cur, __) => ValueListenableBuilder<bool>(
        valueListenable: _testingNf,
        builder: (_, testing, __) => Row(children: [
          Text('Volume :', style: t.textTheme.labelSmall?.copyWith(
            color: t.colorScheme.onSurface.withOpacity(0.4),
            fontWeight: FontWeight.w500,
          )),
          const SizedBox(width: 8),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _kDurationSteps.map((mb) {
                  final sel = mb == cur;
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: GestureDetector(
                      onTap: testing ? null : () => setDownloadSize(mb),
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
                          mb >= 1000 ? '${mb ~/ 1000} GB' : '$mb MB',
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

  // ── Start button ──────────────────────────────────────────────────────────────
  Widget _buildStartButton(ThemeData t) {
    return ValueListenableBuilder<bool>(
      valueListenable: _testingNf,
      builder: (_, testing, __) => SizedBox(
        height: 54,
        child: testing
            ? OutlinedButton(
                onPressed: null,
                style: OutlinedButton.styleFrom(
                  side: BorderSide(
                      color: t.colorScheme.onSurface.withOpacity(0.10),
                      width: 1.5),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(100)),
                ),
                child: Row(mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                  SizedBox(
                    width: 14, height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: t.colorScheme.onSurface.withOpacity(0.25),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text('TEST EN COURS…', style: TextStyle(
                    fontWeight: FontWeight.bold, letterSpacing: 2.0,
                    color: t.colorScheme.onSurface.withOpacity(0.25),
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
                child: const Text('LANCER LE TEST', style: TextStyle(
                  fontWeight: FontWeight.bold, letterSpacing: 2.0)),
              ),
      ),
    );
  }

  // ── Web banner ────────────────────────────────────────────────────────────────
  Widget _webBanner(ThemeData t) => Container(
    margin: const EdgeInsets.only(bottom: 6),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
    decoration: BoxDecoration(
      color: t.colorScheme.tertiaryContainer.withOpacity(0.35),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: t.colorScheme.tertiary.withOpacity(0.35)),
    ),
    child: Row(children: [
      Icon(Icons.public_rounded, size: 15, color: t.colorScheme.tertiary),
      const SizedBox(width: 8),
      Expanded(child: Text(
        'Mode navigateur — seuls les serveurs Cloudflare sont disponibles.',
        style: t.textTheme.labelSmall?.copyWith(
            color: t.colorScheme.onTertiaryContainer, height: 1.4),
      )),
    ]),
  );

  // ── Error banner ──────────────────────────────────────────────────────────────
  Widget _errorBanner(ThemeData t) => ValueListenableBuilder<String?>(
    valueListenable: _errorNf,
    builder: (_, err, __) {
      if (err == null) return const SizedBox.shrink();
      return Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: t.colorScheme.errorContainer.withOpacity(0.22),
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
  // HISTORY TAB — grouped by user location
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildHistory(ThemeData t) {
    // Group entries by userLocation (preserve insertion order)
    final grouped = <String, List<_IndexedEntry>>{};
    for (int i = 0; i < _history.length; i++) {
      final loc = _history[i].userLocation.isEmpty
          ? '📍 Lieu inconnu'
          : _history[i].userLocation;
      grouped.putIfAbsent(loc, () => []).add(_IndexedEntry(_history[i], i));
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header row
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('METRICS LOGS', style: t.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold, letterSpacing: 1.5)),
            if (_history.isNotEmpty)
              Text(
                  '${_history.length} test${_history.length > 1 ? 's' : ''}'
                  '  ·  ${grouped.length} lieu${grouped.length > 1 ? 'x' : ''}',
                  style: t.textTheme.bodySmall?.copyWith(
                      color: t.colorScheme.onSurface.withOpacity(0.4))),
          ]),
          if (_history.isNotEmpty)
            TextButton.icon(
              onPressed: _confirmClearHistory,
              icon: const Icon(Icons.delete_sweep_outlined, size: 16),
              label: const Text('Tout effacer'),
              style: TextButton.styleFrom(
                foregroundColor: t.colorScheme.error,
                visualDensity: VisualDensity.compact,
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
      // Location header
      Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 10),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: t.colorScheme.primaryContainer.withOpacity(0.45),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.place_rounded, size: 12, color: t.colorScheme.primary),
              const SizedBox(width: 5),
              Text(location, style: t.textTheme.labelSmall?.copyWith(
                color: t.colorScheme.primary,
                fontWeight: FontWeight.w800,
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

      // Cards
      for (final ie in entries)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _LogCard(
            entry: ie.entry,
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
      Text('Aucun test enregistré',
          style: t.textTheme.bodyMedium?.copyWith(
              color: t.colorScheme.onSurface.withOpacity(0.4),
              fontWeight: FontWeight.w500)),
      const SizedBox(height: 4),
      Text('Lancez un test pour voir les résultats ici.',
          style: t.textTheme.bodySmall?.copyWith(
              color: t.colorScheme.onSurface.withOpacity(0.27))),
    ]),
  );

  Future<void> _confirmClearHistory() async {
    final t  = Theme.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Effacer les logs'),
        content:
            const Text('Supprimer tous les résultats ? Action irréversible.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Supprimer',
                style: TextStyle(color: t.colorScheme.error)),
          ),
        ],
      ),
    );
    if (ok == true) await _clearHistory();
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// WIDGETS
// ══════════════════════════════════════════════════════════════════════════════

// ─── Speed text ───────────────────────────────────────────────────────────────
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
      Text(value, style: t.textTheme.titleMedium?.copyWith(
        color: color, fontWeight: FontWeight.w800, height: 1.0,
        fontFeatures: const [FontFeature.tabularFigures()],
      )),
      const SizedBox(width: 2),
      Text(unit, style: t.textTheme.labelSmall?.copyWith(
        color: color.withOpacity(0.7), fontWeight: FontWeight.w600)),
    ],
  );
}

// ─── Log Card ──────────────────────────────────────────────────────────────────
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
      key: ValueKey('${entry.timestamp}_${entry.server}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: t.colorScheme.errorContainer.withOpacity(0.6),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Icon(Icons.delete_outline, color: t.colorScheme.error),
      ),
      onDismissed: (_) => onDelete(),
      child: Container(
        decoration: BoxDecoration(
          color: t.colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: t.colorScheme.onSurface.withOpacity(0.08)),
          boxShadow: [
            BoxShadow(
              color: t.colorScheme.shadow.withOpacity(0.04),
              blurRadius: 8, offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(children: [

          // ── Performance banner ──────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
            decoration: BoxDecoration(
              color: gc.withOpacity(0.07),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(children: [
              Icon(grade.icon, size: 13, color: gc),
              const SizedBox(width: 6),
              Text(grade.label, style: t.textTheme.labelSmall?.copyWith(
                color: gc, fontWeight: FontWeight.w800, letterSpacing: 1.0,
              )),
              const Spacer(),
              // Mini speed bar
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                SizedBox(
                  width: 64, height: 4,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: (entry.dl / 1000).clamp(0.0, 1.0),
                      backgroundColor: gc.withOpacity(0.13),
                      valueColor: AlwaysStoppedAnimation(gc),
                      minHeight: 4,
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${entry.dl.toStringAsFixed(0)} ${entry.unit}',
                  style: TextStyle(
                    fontSize: 9, color: gc.withOpacity(0.75),
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ]),
            ]),
          ),

          // ── Server header ───────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
            child: Row(children: [
              // Flag circle
              Container(
                width: 38, height: 38,
                decoration: BoxDecoration(
                  color: t.colorScheme.primaryContainer.withOpacity(0.28),
                  shape: BoxShape.circle,
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
                              color: t.colorScheme.onSecondaryContainer,
                              fontWeight: FontWeight.w700, fontSize: 9,
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

              // Date / time
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(_fmtDate(entry.timestamp),
                    style: t.textTheme.labelSmall?.copyWith(
                        color: t.colorScheme.onSurface.withOpacity(0.55),
                        fontWeight: FontWeight.w500)),
                Text(_fmtTime(entry.timestamp),
                    style: t.textTheme.labelSmall?.copyWith(
                        color: t.colorScheme.onSurface.withOpacity(0.3),
                        fontSize: 10)),
              ]),
            ]),
          ),

          const SizedBox(height: 10),
          Divider(height: 1, color: t.colorScheme.onSurface.withOpacity(0.06)),

          // ── Metrics row ─────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            child: Row(children: [
              _MetricChip(
                icon: Icons.arrow_downward_rounded,
                value: entry.dl.toStringAsFixed(1),
                unit: entry.unit, label: 'DOWN',
                color: _dlColorFor(entry.dl, context),
              ),
              const SizedBox(width: 8),
              _MetricChip(
                icon: Icons.arrow_upward_rounded,
                value: entry.ul.toStringAsFixed(1),
                unit: entry.unit, label: 'UP',
                color: Theme.of(context).colorScheme.secondary,
              ),
              const Spacer(),
              // Ping pill
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: _pingColorFor(entry.ping, context).withOpacity(0.09),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: _pingColorFor(entry.ping, context)
                          .withOpacity(0.22)),
                ),
                child: Column(children: [
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.network_ping_rounded, size: 11,
                        color: _pingColorFor(entry.ping, context)),
                    const SizedBox(width: 4),
                    Text('${entry.ping} ms',
                        style: t.textTheme.bodySmall?.copyWith(
                          color: _pingColorFor(entry.ping, context),
                          fontWeight: FontWeight.w700,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        )),
                  ]),
                  Text('PING', style: t.textTheme.labelSmall?.copyWith(
                      color: _pingColorFor(entry.ping, context).withOpacity(0.6),
                      fontSize: 9, letterSpacing: 0.8)),
                ]),
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
      const months = ['jan', 'fév', 'mar', 'avr', 'mai', 'jun',
                      'jul', 'aoû', 'sep', 'oct', 'nov', 'déc'];
      return '${d.day} ${months[d.month - 1]}. ${d.year}';
    } catch (_) { return ts.substring(0, min(10, ts.length)); }
  }

  static String _fmtTime(String ts) {
    try { return ts.substring(11, 16); } catch (_) { return ''; }
  }
}

// ─── Metric Chip ──────────────────────────────────────────────────────────────
class _MetricChip extends StatelessWidget {
  final IconData icon;
  final String value, unit, label;
  final Color color;
  const _MetricChip({
    required this.icon, required this.value,
    required this.unit, required this.label, required this.color,
  });
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withOpacity(0.09),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.22)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 5),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('$value $unit', style: t.textTheme.bodySmall?.copyWith(
            color: color, fontWeight: FontWeight.w700,
            fontFeatures: const [FontFeature.tabularFigures()],
          )),
          Text(label, style: t.textTheme.labelSmall?.copyWith(
              color: color.withOpacity(0.6), fontSize: 9, letterSpacing: 0.8)),
        ]),
      ]),
    );
  }
}

// ─── Arc Gauge Painter ────────────────────────────────────────────────────────
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

    // ── Background track ───────────────────────────────────────────────────
    canvas.drawArc(
      rect, startRad, sweepRad, false,
      Paint()
        ..color = trackColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeW
        ..strokeCap = StrokeCap.round,
    );

    final progress = (speedMbps / maxSpeedMbps).clamp(0.0, 1.0);
    if (progress < 0.001) return;

    // ── Gradient arc ───────────────────────────────────────────────────────
    final (Color c1, Color c2) = _speedColors(speedMbps);
    final sweepActual = sweepRad * progress;

    canvas.drawArc(
      rect, startRad, sweepActual, false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeW + 1
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          colors: [c1, c2],
          startAngle: startRad,
          endAngle: startRad + sweepRad,
          tileMode: TileMode.clamp,
        ).createShader(rect),
    );

    // ── Thumb dot ──────────────────────────────────────────────────────────
    final endAngle = startRad + sweepActual;
    final dx = cx + radius * cos(endAngle);
    final dy = cy + radius * sin(endAngle);
    canvas.drawCircle(Offset(dx, dy), 8,
        Paint()..color = c2..style = PaintingStyle.fill);
    canvas.drawCircle(Offset(dx, dy), 8,
        Paint()
          ..color = Colors.white.withOpacity(0.55)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5);

    // ── Tick marks ─────────────────────────────────────────────────────────
    final tickPaint = Paint()
      ..color = trackColor.withOpacity(0.8)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    for (int i = 0; i <= 10; i++) {
      final a   = startRad + sweepRad * i / 10;
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

// ─── Chart Painter ────────────────────────────────────────────────────────────
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

    final line = Path()..moveTo(0, y(points[0]));
    for (int i = 1; i < points.length; i++) {
      final x = i * stepX, px = (i - 1) * stepX, cx = (px + x) / 2;
      line.cubicTo(cx, y(points[i - 1]), cx, y(points[i]), x, y(points[i]));
    }

    final fill = Path.from(line)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    canvas.drawPath(fill,
        Paint()..color = color.withOpacity(0.08)..style = PaintingStyle.fill);
    canvas.drawPath(line, Paint()
      ..color = color.withOpacity(0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round);
  }

  @override
  bool shouldRepaint(covariant _ChartPainter old) => old.points != points;
}