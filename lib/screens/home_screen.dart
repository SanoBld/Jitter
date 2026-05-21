import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../app_state.dart';
import '../services/internet_speed_service.dart';
import 'settings_screen.dart';

// ── Modèle d'une entrée de log ─────────────────────────────────────────────
class _LogEntry {
  final String timestamp;   // "2024-01-15 14:30"
  final String flag;
  final String server;
  final String provider;
  final String location;
  final double dl;          // Mbps
  final double ul;          // Mbps
  final int    ping;        // ms
  final String unit;        // "Mb/s" | "MB/s"

  const _LogEntry({
    required this.timestamp,
    required this.flag,
    required this.server,
    required this.provider,
    required this.location,
    required this.dl,
    required this.ul,
    required this.ping,
    required this.unit,
  });

  Map<String, dynamic> toJson() => {
    'ts': timestamp, 'flag': flag, 'server': server,
    'provider': provider, 'location': location,
    'dl': dl, 'ul': ul, 'ping': ping, 'unit': unit,
  };

  factory _LogEntry.fromJson(Map<String, dynamic> j) => _LogEntry(
    timestamp: j['ts'] as String,
    flag:      j['flag'] as String,
    server:    j['server'] as String,
    provider:  j['provider'] as String,
    location:  j['location'] as String? ?? '',
    dl:        (j['dl'] as num).toDouble(),
    ul:        (j['ul'] as num).toDouble(),
    ping:      j['ping'] as int,
    unit:      j['unit'] as String,
  );

  /// Migration : tente de parser une ancienne entrée texte brut.
  /// Retourne null si le format n'est pas reconnu.
  static _LogEntry? tryFromLegacyString(String raw) {
    try {
      // Format ancien : "2024-01-15 14:30  |  🇫🇷 Paris  |  🔽 95.2 Mb/s  🔼 12.3 Mb/s  📶 23 ms"
      final parts = raw.split('  |  ');
      if (parts.length < 3) return null;
      final ts      = parts[0].trim();
      final srv     = parts[1].trim();
      final metrics = parts[2].trim();

      // Extrait flag + nom du serveur
      final flag   = srv.split(' ').first;
      final server = srv.substring(flag.length).trim();

      // Extrait les métriques avec regex basique
      final dlMatch   = RegExp(r'🔽\s*([\d.]+)\s*(\S+)').firstMatch(metrics);
      final ulMatch   = RegExp(r'🔼\s*([\d.]+)').firstMatch(metrics);
      final pingMatch = RegExp(r'📶\s*(\d+)').firstMatch(metrics);

      if (dlMatch == null) return null;
      return _LogEntry(
        timestamp: ts,
        flag:      flag,
        server:    server,
        provider:  '',
        location:  '',
        dl:        double.parse(dlMatch.group(1)!),
        ul:        ulMatch != null ? double.parse(ulMatch.group(1)!) : 0,
        ping:      pingMatch != null ? int.parse(pingMatch.group(1)!) : 0,
        unit:      dlMatch.group(2) ?? 'Mb/s',
      );
    } catch (_) {
      return null;
    }
  }
}

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
    _speedNf.dispose();  _pingNf.dispose();
    _dlNf.dispose();     _ulNf.dispose();
    _testingNf.dispose(); _phaseNf.dispose();
    _pointsNf.dispose(); _progressNf.dispose();
    _errorNf.dispose();
    super.dispose();
  }

  // ── Persistence ────────────────────────────────────────────────────────────
  Future<void> _loadHistory() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getStringList('speed_history') ?? [];
    final parsed = <_LogEntry>[];
    for (final s in raw) {
      try {
        parsed.add(_LogEntry.fromJson(json.decode(s) as Map<String, dynamic>));
      } catch (_) {
        // Migration anciens logs texte brut
        final legacy = _LogEntry.tryFromLegacyString(s);
        if (legacy != null) parsed.add(legacy);
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
  double _display(double mbps) =>
      speedUnitMbpsNotifier.value ? mbps : mbps / 8;
  String get _unit     => speedUnitMbpsNotifier.value ? 'Mb/s' : 'MB/s';
  String get _unitLong =>
      speedUnitMbpsNotifier.value ? 'MEGABITS / S' : 'MEGABYTES / S';

  // ── Test ───────────────────────────────────────────────────────────────────
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
      await for (final mbps in _svc.testDownloadSpeed(
          serverIndex: srv, maxMB: sz)) {
        _speedNf.value = mbps;
        _dlNf.value    = mbps;
        final pts = List<double>.from(_pointsNf.value)..add(mbps);
        if (pts.length > 40) pts.removeAt(0);
        _pointsNf.value   = pts;
        _progressNf.value =
            0.08 + 0.57 * (pts.length / 40).clamp(0.0, 1.0);
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
        final entry = _LogEntry(
          timestamp: DateTime.now().toLocal().toString().substring(0, 16),
          flag:      server.flag,
          server:    server.name,
          provider:  server.provider,
          location:  server.location,
          dl:        _dlNf.value,
          ul:        _ulNf.value,
          ping:      _pingNf.value,
          unit:      _unit,
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
        raw.contains('cross-origin') || raw.contains('XMLHttpRequest')) {
      return 'Erreur CORS — ce serveur bloque les requêtes depuis un navigateur.\n'
          'Utilisez un serveur Cloudflare ou lancez l\'APK Android.';
    }
    if (raw.contains('Permission denied') || raw.contains('INTERNET')) {
      return 'Permission réseau manquante.\nVérifiez AndroidManifest.xml.';
    }
    if (raw.contains('Failed host lookup') || raw.contains('No address')) {
      return 'Impossible de résoudre le serveur.\nVérifiez votre connexion.';
    }
    if (raw.contains('SocketException')) return 'Pas de connexion internet.';
    if (raw.contains('timeout') || raw.contains('TimeoutException')) {
      return 'Timeout — le serveur ne répond pas.\nEssayez un autre serveur.';
    }
    if (raw.contains('HandshakeException')) {
      return 'Erreur SSL — vérifiez la date/heure de l\'appareil.';
    }
    return 'Erreur : $raw';
  }

  // ── Build ──────────────────────────────────────────────────────────────────
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
          NavigationDestination(icon: Icon(Icons.speed_outlined),
              selectedIcon: Icon(Icons.speed), label: 'Test'),
          NavigationDestination(icon: Icon(Icons.history_outlined),
              selectedIcon: Icon(Icons.history), label: 'Logs'),
          NavigationDestination(icon: Icon(Icons.tune_outlined),
              selectedIcon: Icon(Icons.tune), label: 'Settings'),
        ],
      ),
    );
  }

  // ── Dashboard ──────────────────────────────────────────────────────────────
  Widget _buildDashboard(ThemeData t) {
    return LayoutBuilder(builder: (ctx, constraints) {
      final gaugeSize = (constraints.maxHeight * 0.30).clamp(150.0, 260.0);
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (kIsWeb) _webBanner(t),
            _header(t),
            Expanded(child: Center(child: _gauge(gaugeSize, t))),
            _chart(t),
            const SizedBox(height: 14),
            _errorBanner(t),
            _statsRow(t),
            const SizedBox(height: 14),
            _startButton(t),
            const SizedBox(height: 6),
          ],
        ),
      );
    });
  }

  Widget _webBanner(ThemeData t) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: t.colorScheme.tertiaryContainer.withOpacity(0.35),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: t.colorScheme.tertiary.withOpacity(0.35)),
    ),
    child: Row(children: [
      Icon(Icons.public_rounded, size: 16, color: t.colorScheme.tertiary),
      const SizedBox(width: 8),
      Expanded(child: Text(
        'Mode navigateur — seuls les serveurs Cloudflare sont disponibles (CORS).',
        style: t.textTheme.labelSmall?.copyWith(
          color: t.colorScheme.onTertiaryContainer, height: 1.4),
      )),
    ]),
  );

  Widget _errorBanner(ThemeData t) => ValueListenableBuilder<String?>(
    valueListenable: _errorNf,
    builder: (_, err, __) {
      if (err == null) return const SizedBox.shrink();
      return Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: t.colorScheme.errorContainer.withOpacity(0.25),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: t.colorScheme.error.withOpacity(0.4)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.wifi_off_rounded, size: 18, color: t.colorScheme.error),
          const SizedBox(width: 10),
          Expanded(child: Text(err, style: t.textTheme.bodySmall?.copyWith(
            color: t.colorScheme.onErrorContainer, height: 1.5))),
        ]),
      );
    },
  );

  Widget _header(ThemeData t) => ValueListenableBuilder<int>(
    valueListenable: selectedServerNotifier,
    builder: (_, si, __) {
      final resolvedIdx = InternetSpeedService.resolveServerIndex(si);
      final srv = InternetSpeedService.servers[resolvedIdx];
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('CORE NODE', style: t.textTheme.labelSmall?.copyWith(
                color: t.colorScheme.primary,
                fontWeight: FontWeight.bold, letterSpacing: 1.5)),
            const SizedBox(height: 2),
            Text('${srv.flag} ${srv.location} (${srv.provider})',
                style: t.textTheme.bodySmall?.copyWith(
                    color: t.colorScheme.onSurface.withOpacity(0.6))),
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

  Widget _gauge(double size, ThemeData t) => ValueListenableBuilder<bool>(
    valueListenable: speedUnitMbpsNotifier,
    builder: (_, isMbps, __) => ValueListenableBuilder<double>(
      valueListenable: _speedNf,
      builder: (_, mbps, __) => ValueListenableBuilder<double>(
        valueListenable: _progressNf,
        builder: (_, progress, __) {
          final displaySpeed = isMbps ? mbps : mbps / 8;
          return Stack(alignment: Alignment.center, children: [
            SizedBox(width: size, height: size,
              child: CircularProgressIndicator(
                value: progress, strokeWidth: 2.5,
                backgroundColor: t.colorScheme.onSurface.withOpacity(0.06),
                valueColor: AlwaysStoppedAnimation<Color>(t.colorScheme.primary),
              ),
            ),
            Column(mainAxisSize: MainAxisSize.min, children: [
              Text(displaySpeed.toStringAsFixed(1),
                style: t.textTheme.displayLarge?.copyWith(
                  fontSize: size * 0.26, fontWeight: FontWeight.w200,
                  fontFeatures: [const FontFeature.tabularFigures()]),
              ),
              const SizedBox(height: 4),
              Text(_unitLong, style: t.textTheme.labelSmall?.copyWith(
                  color: t.colorScheme.onSurface.withOpacity(0.4),
                  letterSpacing: 2.0)),
            ]),
          ]);
        },
      ),
    ),
  );

  Widget _chart(ThemeData t) => SizedBox(
    height: 50,
    child: ValueListenableBuilder<List<double>>(
      valueListenable: _pointsNf,
      builder: (_, pts, __) => CustomPaint(
        painter: _ChartPainter(points: pts, color: t.colorScheme.primary),
        child: const SizedBox.expand(),
      ),
    ),
  );

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
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
        _intStat('LATENCY', _pingNf, 'ms', t),
        div,
        _dblStat('DOWN', _dlNf, t),
        div,
        _dblStat('UP', _ulNf, t),
      ]),
    );
  }

  Widget _intStat(String label, ValueNotifier<int> nf, String unit, ThemeData t) =>
    Column(children: [
      _statLabel(label, t), const SizedBox(height: 4),
      ValueListenableBuilder<int>(valueListenable: nf,
        builder: (_, v, __) => Text('$v $unit',
          style: t.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600,
              fontFeatures: [const FontFeature.tabularFigures()]))),
    ]);

  Widget _dblStat(String label, ValueNotifier<double> nf, ThemeData t) =>
    Column(children: [
      _statLabel(label, t), const SizedBox(height: 4),
      ValueListenableBuilder<double>(valueListenable: nf,
        builder: (_, mbps, __) => ValueListenableBuilder<bool>(
          valueListenable: speedUnitMbpsNotifier,
          builder: (_, isMbps, __) {
            final v = isMbps ? mbps : mbps / 8;
            return Text('${v.toStringAsFixed(1)} $_unit',
              style: t.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600,
                  fontFeatures: [const FontFeature.tabularFigures()]));
          },
        )),
    ]);

  Widget _statLabel(String label, ThemeData t) => Text(label,
    style: t.textTheme.labelSmall?.copyWith(
        color: t.colorScheme.onSurface.withOpacity(0.4),
        fontWeight: FontWeight.bold, letterSpacing: 1.0));

  Widget _startButton(ThemeData t) => ValueListenableBuilder<bool>(
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
      child: Text(testing ? 'RUNNING METRICS...' : 'START TEST',
        style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 2.0,
          color: testing
              ? t.colorScheme.onSurface.withOpacity(0.3)
              : t.colorScheme.primary)),
    ),
  );

  // ── History tab ────────────────────────────────────────────────────────────
  Widget _buildHistory(ThemeData t) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // Header
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('METRICS LOGS', style: t.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold, letterSpacing: 1.5)),
            if (_history.isNotEmpty)
              Text('${_history.length} résultat${_history.length > 1 ? 's' : ''}',
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
              : ListView.builder(
                  itemCount: _history.length,
                  itemBuilder: (_, i) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _LogCard(
                      entry: _history[i],
                      onDelete: () => _deleteEntry(i),
                    ),
                  ),
                ),
        ),
      ]),
    );
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
            color: t.colorScheme.onSurface.withOpacity(0.25)),
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
    final t = Theme.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Effacer les logs'),
        content: const Text('Supprimer tous les résultats ? Action irréversible.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler')),
          TextButton(onPressed: () => Navigator.pop(ctx, true),
              child: Text('Supprimer', style: TextStyle(color: t.colorScheme.error))),
        ],
      ),
    );
    if (ok == true) await _clearHistory();
  }
}

// ── Log Card ──────────────────────────────────────────────────────────────────
class _LogCard extends StatelessWidget {
  final _LogEntry entry;
  final VoidCallback onDelete;

  const _LogCard({required this.entry, required this.onDelete});

  // Couleur du badge de vitesse download
  Color _dlColor(BuildContext context, double mbps) {
    final cs = Theme.of(context).colorScheme;
    if (mbps >= 100) return const Color(0xFF2E7D32); // vert
    if (mbps >= 30)  return const Color(0xFF1565C0); // bleu
    if (mbps >= 10)  return const Color(0xFFE65100); // orange
    return cs.error;                                  // rouge
  }

  // Couleur du badge ping
  Color _pingColor(BuildContext context, int ms) {
    final cs = Theme.of(context).colorScheme;
    if (ms <= 30)  return const Color(0xFF2E7D32);
    if (ms <= 80)  return const Color(0xFF1565C0);
    if (ms <= 150) return const Color(0xFFE65100);
    return cs.error;
  }

  @override
  Widget build(BuildContext context) {
    final t  = Theme.of(context);
    final dl = entry.unit == 'MB/s' ? entry.dl : entry.dl; // déjà en bonne unité
    final ul = entry.ul;

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

          // ── Header ─────────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(children: [

              // Flag + cercle
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: t.colorScheme.primaryContainer.withOpacity(0.35),
                  shape: BoxShape.circle,
                ),
                child: Center(child: Text(entry.flag,
                    style: const TextStyle(fontSize: 18))),
              ),
              const SizedBox(width: 12),

              // Nom serveur + provider + location
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Text(entry.server,
                        style: t.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600)),
                    if (entry.provider.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: t.colorScheme.secondaryContainer
                              .withOpacity(0.5),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(entry.provider,
                            style: t.textTheme.labelSmall?.copyWith(
                                color: t.colorScheme.onSecondaryContainer,
                                fontWeight: FontWeight.w600,
                                fontSize: 10)),
                      ),
                    ],
                  ]),
                  if (entry.location.isNotEmpty)
                    Text(entry.location,
                        style: t.textTheme.bodySmall?.copyWith(
                            color: t.colorScheme.onSurface.withOpacity(0.45))),
                ],
              )),

              // Date + heure
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(_formatDate(entry.timestamp),
                    style: t.textTheme.labelSmall?.copyWith(
                        color: t.colorScheme.onSurface.withOpacity(0.55),
                        fontWeight: FontWeight.w500)),
                Text(_formatTime(entry.timestamp),
                    style: t.textTheme.labelSmall?.copyWith(
                        color: t.colorScheme.onSurface.withOpacity(0.35),
                        fontSize: 11)),
              ]),
            ]),
          ),

          // ── Divider ────────────────────────────────────────────────────────
          Divider(height: 1, color: t.colorScheme.onSurface.withOpacity(0.06)),

          // ── Métriques ──────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            child: Row(children: [

              _MetricChip(
                icon: Icons.arrow_downward_rounded,
                value: dl.toStringAsFixed(1),
                unit: entry.unit,
                label: 'DOWN',
                color: _dlColor(context, dl),
              ),

              const SizedBox(width: 10),

              _MetricChip(
                icon: Icons.arrow_upward_rounded,
                value: ul.toStringAsFixed(1),
                unit: entry.unit,
                label: 'UP',
                color: t.colorScheme.secondary,
              ),

              const Spacer(),

              // Ping pill
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: _pingColor(context, entry.ping).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: _pingColor(context, entry.ping).withOpacity(0.25)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.network_ping_rounded, size: 12,
                          color: _pingColor(context, entry.ping)),
                      const SizedBox(width: 4),
                      Text('${entry.ping} ms',
                          style: t.textTheme.bodySmall?.copyWith(
                              color: _pingColor(context, entry.ping),
                              fontWeight: FontWeight.w700,
                              fontFeatures: [
                                const FontFeature.tabularFigures()
                              ])),
                    ]),
                    Text('PING',
                        style: t.textTheme.labelSmall?.copyWith(
                            color: _pingColor(context, entry.ping)
                                .withOpacity(0.65),
                            fontSize: 9, letterSpacing: 0.8)),
                  ],
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  String _formatDate(String ts) {
    // ts = "2024-01-15 14:30"
    try {
      final d = DateTime.parse(ts.length == 16 ? '${ts}:00' : ts);
      const months = ['jan', 'fév', 'mar', 'avr', 'mai', 'jun',
                      'jul', 'aoû', 'sep', 'oct', 'nov', 'déc'];
      return '${d.day} ${months[d.month - 1]}. ${d.year}';
    } catch (_) {
      return ts.substring(0, 10);
    }
  }

  String _formatTime(String ts) {
    try { return ts.substring(11, 16); } catch (_) { return ''; }
  }
}

// ── Metric Chip ───────────────────────────────────────────────────────────────
class _MetricChip extends StatelessWidget {
  final IconData icon;
  final String value;
  final String unit;
  final String label;
  final Color color;

  const _MetricChip({
    required this.icon, required this.value,
    required this.unit,  required this.label, required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.09),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.22)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 5),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('$value $unit',
              style: t.textTheme.bodySmall?.copyWith(
                  color: color, fontWeight: FontWeight.w700,
                  fontFeatures: [const FontFeature.tabularFigures()])),
          Text(label, style: t.textTheme.labelSmall?.copyWith(
              color: color.withOpacity(0.65), fontSize: 9, letterSpacing: 0.8)),
        ]),
      ]),
    );
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
    final maxV  = points.reduce(max).clamp(1.0, double.infinity);
    final stepX = size.width / (points.length - 1);
    double y(double v) => size.height - (v / maxV * size.height * 0.88);

    final line = Path()..moveTo(0, y(points[0]));
    for (int i = 1; i < points.length; i++) {
      final x = i * stepX, prevX = (i - 1) * stepX, cpX = (prevX + x) / 2;
      line.cubicTo(cpX, y(points[i-1]), cpX, y(points[i]), x, y(points[i]));
    }

    final fill = Path.from(line)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)..close();
    canvas.drawPath(fill,
        Paint()..color = color.withOpacity(0.07)..style = PaintingStyle.fill);
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