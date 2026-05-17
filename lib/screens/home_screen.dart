import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../app_state.dart';
import '../services/internet_speed_service.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  final _svc = InternetSpeedService();
  int _tabIndex = 0;

  // ── Reactive state ────────────────────────────────────────────────────────
  final _speedNf    = ValueNotifier<double>(0.0);
  final _pingNf     = ValueNotifier<int>(0);
  final _dlNf       = ValueNotifier<double>(0.0);
  final _ulNf       = ValueNotifier<double>(0.0);
  final _testingNf  = ValueNotifier<bool>(false);
  final _phaseNf    = ValueNotifier<String>('READY');
  final _pointsNf   = ValueNotifier<List<double>>([]);
  final _progressNf = ValueNotifier<double>(0.0);

  late AnimationController _pulse;
  List<String> _history = [];

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
    _speedNf.dispose();
    _pingNf.dispose();
    _dlNf.dispose();
    _ulNf.dispose();
    _testingNf.dispose();
    _phaseNf.dispose();
    _pointsNf.dispose();
    _progressNf.dispose();
    super.dispose();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  Future<void> _loadHistory() async {
    final p = await SharedPreferences.getInstance();
    if (mounted) setState(() => _history = p.getStringList('speed_history') ?? []);
  }

  double _display(double mbps) =>
      speedUnitMbpsNotifier.value ? mbps : mbps / 8;

  String get _unit => speedUnitMbpsNotifier.value ? 'Mb/s' : 'MB/s';
  String get _unitLong => speedUnitMbpsNotifier.value ? 'MEGABITS / S' : 'MEGABYTES / S';

  // ── Test logic ────────────────────────────────────────────────────────────
  Future<void> _runTest() async {
    final srv = selectedServerNotifier.value;
    final sz  = downloadSizeMBNotifier.value;

    _testingNf.value  = true;
    _speedNf.value    = 0;
    _dlNf.value       = 0;
    _ulNf.value       = 0;
    _pingNf.value     = 0;
    _pointsNf.value   = [];
    _progressNf.value = 0;

    // Ping
    _phaseNf.value    = 'PING';
    _pingNf.value     = await _svc.testPing(srv);
    _progressNf.value = 0.08;

    // Download
    _phaseNf.value = 'DOWNLOAD';
    try {
      await for (final mbps in _svc.testDownloadSpeed(serverIndex: srv, maxMB: sz)) {
        _speedNf.value = mbps;
        _dlNf.value    = mbps;
        final pts = List<double>.from(_pointsNf.value)..add(mbps);
        if (pts.length > 40) pts.removeAt(0);
        _pointsNf.value   = pts;
        _progressNf.value = 0.08 + 0.57 * (pts.length / 40).clamp(0.0, 1.0);
      }
    } catch (_) {}

    _progressNf.value = 0.65;
    _pointsNf.value   = [];

    // Upload
    _phaseNf.value = 'UPLOAD';
    final ul = await _svc.testUploadSpeed();
    _speedNf.value    = ul;
    _ulNf.value       = ul;
    _pointsNf.value   = [ul * 0.3, ul * 0.55, ul * 0.8, ul];
    _progressNf.value = 1.0;

    _phaseNf.value   = 'COMPLETED';
    _testingNf.value = false;

    // Save to history
    if (autoSaveHistoryNotifier.value) {
      final server = InternetSpeedService.servers[srv];
      final dl = _display(_dlNf.value);
      final ul2 = _display(_ulNf.value);
      final entry =
          '${DateTime.now().toLocal().toString().substring(0, 16)}  |  '
          '${server.flag} ${server.name}  |  '
          '🔽 ${dl.toStringAsFixed(1)} $_unit  '
          '🔼 ${ul2.toStringAsFixed(1)} $_unit  '
          '📶 ${_pingNf.value} ms';
      _history.insert(0, entry);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('speed_history', _history);
      if (mounted) setState(() {});
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tabs = [
      _buildDashboard(theme),
      _buildHistory(theme),
      const SettingsScreen(),
    ];

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(child: tabs[_tabIndex]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (i) => setState(() => _tabIndex = i),
        backgroundColor: theme.colorScheme.surface,
        indicatorColor: theme.colorScheme.primaryContainer.withOpacity(0.5),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.speed_outlined),
            selectedIcon: Icon(Icons.speed),
            label: 'Test',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_outlined),
            selectedIcon: Icon(Icons.history),
            label: 'Logs',
          ),
          NavigationDestination(
            icon: Icon(Icons.tune_outlined),
            selectedIcon: Icon(Icons.tune),
            label: 'Settings',
          ),
        ],
      ),
    );
  }

  // ── Dashboard ─────────────────────────────────────────────────────────────
  Widget _buildDashboard(ThemeData t) {
    return LayoutBuilder(
      builder: (ctx, constraints) {
        // Gauge adapts to available height → no overflow
        final gaugeSize = (constraints.maxHeight * 0.30).clamp(150.0, 260.0);
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(t),
              // Gauge fills remaining vertical space
              Expanded(child: Center(child: _gauge(gaugeSize, t))),
              _chart(t),
              const SizedBox(height: 14),
              _statsRow(t),
              const SizedBox(height: 14),
              _startButton(t),
              const SizedBox(height: 6),
            ],
          ),
        );
      },
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────
  Widget _header(ThemeData t) {
    return ValueListenableBuilder<int>(
      valueListenable: selectedServerNotifier,
      builder: (_, si, __) {
        final srv = InternetSpeedService
            .servers[si.clamp(0, InternetSpeedService.servers.length - 1)];
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('CORE NODE',
                  style: t.textTheme.labelSmall?.copyWith(
                      color: t.colorScheme.primary,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5)),
              const SizedBox(height: 2),
              Text('${srv.flag} ${srv.location} (${srv.provider})',
                  style: t.textTheme.bodySmall
                      ?.copyWith(color: t.colorScheme.onSurface.withOpacity(0.6))),
            ]),
            ValueListenableBuilder<bool>(
              valueListenable: _testingNf,
              builder: (_, testing, __) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: testing
                      ? t.colorScheme.errorContainer.withOpacity(0.2)
                      : t.colorScheme.primaryContainer.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(children: [
                  AnimatedBuilder(
                    animation: _pulse,
                    builder: (_, __) => Container(
                      width: 8, height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: testing
                            ? t.colorScheme.error.withOpacity(_pulse.value)
                            : t.colorScheme.primary.withOpacity(_pulse.value),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ValueListenableBuilder<String>(
                    valueListenable: _phaseNf,
                    builder: (_, phase, __) => Text(phase,
                        style: t.textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.bold, letterSpacing: 1.0)),
                  ),
                ]),
              ),
            ),
          ],
        );
      },
    );
  }

  // ── Gauge ─────────────────────────────────────────────────────────────────
  Widget _gauge(double size, ThemeData t) {
    return ValueListenableBuilder<bool>(
      valueListenable: speedUnitMbpsNotifier,
      builder: (_, isMbps, __) => ValueListenableBuilder<double>(
        valueListenable: _speedNf,
        builder: (_, mbps, __) => ValueListenableBuilder<double>(
          valueListenable: _progressNf,
          builder: (_, progress, __) {
            final displaySpeed = isMbps ? mbps : mbps / 8;
            return Stack(alignment: Alignment.center, children: [
              SizedBox(
                width: size, height: size,
                child: CircularProgressIndicator(
                  value: progress,
                  strokeWidth: 2.5,
                  backgroundColor: t.colorScheme.onSurface.withOpacity(0.06),
                  valueColor: AlwaysStoppedAnimation<Color>(t.colorScheme.primary),
                ),
              ),
              Column(mainAxisSize: MainAxisSize.min, children: [
                Text(
                  displaySpeed.toStringAsFixed(1),
                  style: t.textTheme.displayLarge?.copyWith(
                    fontSize: size * 0.26,
                    fontWeight: FontWeight.w200,
                    fontFeatures: [const FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 4),
                Text(_unitLong,
                    style: t.textTheme.labelSmall?.copyWith(
                        color: t.colorScheme.onSurface.withOpacity(0.4),
                        letterSpacing: 2.0)),
              ]),
            ]);
          },
        ),
      ),
    );
  }

  // ── Chart ─────────────────────────────────────────────────────────────────
  Widget _chart(ThemeData t) {
    return SizedBox(
      height: 50,
      child: ValueListenableBuilder<List<double>>(
        valueListenable: _pointsNf,
        builder: (_, pts, __) => CustomPaint(
          painter: _ChartPainter(points: pts, color: t.colorScheme.primary),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }

  // ── Stats row ─────────────────────────────────────────────────────────────
  Widget _statsRow(ThemeData t) {
    final div = Container(
        width: 1, height: 28, color: t.colorScheme.onSurface.withOpacity(0.1));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: t.colorScheme.onSurface.withOpacity(0.04),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: t.colorScheme.onSurface.withOpacity(0.06)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _intStat('LATENCY', _pingNf, 'ms', t),
          div,
          _dblStat('DOWN', _dlNf, t),
          div,
          _dblStat('UP', _ulNf, t),
        ],
      ),
    );
  }

  Widget _intStat(String label, ValueNotifier<int> nf, String unit, ThemeData t) {
    return Column(children: [
      _statLabel(label, t),
      const SizedBox(height: 4),
      ValueListenableBuilder<int>(
        valueListenable: nf,
        builder: (_, v, __) => Text('$v $unit',
            style: t.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                fontFeatures: [const FontFeature.tabularFigures()])),
      ),
    ]);
  }

  Widget _dblStat(String label, ValueNotifier<double> nf, ThemeData t) {
    return Column(children: [
      _statLabel(label, t),
      const SizedBox(height: 4),
      ValueListenableBuilder<double>(
        valueListenable: nf,
        builder: (_, mbps, __) => ValueListenableBuilder<bool>(
          valueListenable: speedUnitMbpsNotifier,
          builder: (_, isMbps, __) {
            final v = isMbps ? mbps : mbps / 8;
            return Text('${v.toStringAsFixed(1)} $_unit',
                style: t.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    fontFeatures: [const FontFeature.tabularFigures()]));
          },
        ),
      ),
    ]);
  }

  Widget _statLabel(String label, ThemeData t) => Text(label,
      style: t.textTheme.labelSmall?.copyWith(
          color: t.colorScheme.onSurface.withOpacity(0.4),
          fontWeight: FontWeight.bold,
          letterSpacing: 1.0));

  // ── Start button ──────────────────────────────────────────────────────────
  Widget _startButton(ThemeData t) {
    return ValueListenableBuilder<bool>(
      valueListenable: _testingNf,
      builder: (_, testing, __) => OutlinedButton(
        onPressed: testing ? null : _runTest,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 18),
          side: BorderSide(
            color: testing
                ? t.colorScheme.onSurface.withOpacity(0.12)
                : t.colorScheme.primary,
            width: 1.5,
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
        ),
        child: Text(
          testing ? 'RUNNING METRICS...' : 'START TEST',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            letterSpacing: 2.0,
            color: testing
                ? t.colorScheme.onSurface.withOpacity(0.3)
                : t.colorScheme.primary,
          ),
        ),
      ),
    );
  }

  // ── History tab ───────────────────────────────────────────────────────────
  Widget _buildHistory(ThemeData t) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('METRICS LOGS',
              style: t.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold, letterSpacing: 1.5)),
          if (_history.isNotEmpty)
            TextButton.icon(
              onPressed: _clearHistory,
              icon: const Icon(Icons.delete_outline, size: 16),
              label: const Text('Clear'),
              style: TextButton.styleFrom(
                foregroundColor: t.colorScheme.error,
                visualDensity: VisualDensity.compact,
              ),
            ),
        ]),
        const SizedBox(height: 16),
        Expanded(
          child: _history.isEmpty
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.history, size: 48,
                        color: t.colorScheme.onSurface.withOpacity(0.18)),
                    const SizedBox(height: 12),
                    Text('No telemetry saved.',
                        style: TextStyle(
                            color: t.colorScheme.onSurface.withOpacity(0.4))),
                  ]),
                )
              : ListView.separated(
                  itemCount: _history.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: t.colorScheme.onSurface.withOpacity(0.04),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: t.colorScheme.onSurface.withOpacity(0.06)),
                    ),
                    child: Text(_history[i],
                        style: t.textTheme.bodySmall?.copyWith(
                            height: 1.6,
                            fontFeatures: [const FontFeature.tabularFigures()])),
                  ),
                ),
        ),
      ]),
    );
  }

  Future<void> _clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('speed_history');
    if (mounted) setState(() => _history = []);
  }
}

// ── Chart Painter ─────────────────────────────────────────────────────────────
class _ChartPainter extends CustomPainter {
  final List<double> points;
  final Color color;

  const _ChartPainter({required this.points, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;

    final maxV = points.reduce(max).clamp(1.0, double.infinity);
    final stepX = size.width / (points.length - 1);

    double y(double v) => size.height - (v / maxV * size.height * 0.88);

    final line = Path()
      ..moveTo(0, y(points[0]));

    for (int i = 1; i < points.length; i++) {
      final x = i * stepX;
      final prevX = (i - 1) * stepX;
      final cpX = (prevX + x) / 2;
      line.cubicTo(cpX, y(points[i - 1]), cpX, y(points[i]), x, y(points[i]));
    }

    // Fill
    final fill = Path.from(line)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(fill,
        Paint()..color = color.withOpacity(0.07)..style = PaintingStyle.fill);

    // Stroke
    canvas.drawPath(
        line,
        Paint()
          ..color = color.withOpacity(0.85)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round);
  }

  @override
  bool shouldRepaint(covariant _ChartPainter old) => old.points != points;
}
