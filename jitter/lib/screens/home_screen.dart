import 'dart:async';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/internet_speed_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  final _speedService = InternetSpeedService();
  int _currentIndex = 0;

  final ValueNotifier<double> _currentSpeedNotifier = ValueNotifier<double>(0.0);
  final ValueNotifier<int>    _pingNotifier         = ValueNotifier<int>(0);
  final ValueNotifier<double> _downloadFinalNotifier = ValueNotifier<double>(0.0);
  final ValueNotifier<double> _uploadFinalNotifier   = ValueNotifier<double>(0.0);
  final ValueNotifier<bool>   _isTestingNotifier     = ValueNotifier<bool>(false);
  final ValueNotifier<String> _phaseNotifier         = ValueNotifier<String>('READY');
  final ValueNotifier<List<double>> _chartPointsNotifier = ValueNotifier<List<double>>([]);

  late AnimationController _pulseController;
  List<String> _history = [];

  @override
  void initState() {
    super.initState();
    _loadHistory();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _history = prefs.getStringList('speed_history') ?? [];
    });
  }

  Future<void> _runAdvancedTest() async {
    _isTestingNotifier.value = true;
    _currentSpeedNotifier.value = 0.0;
    _downloadFinalNotifier.value = 0.0;
    _uploadFinalNotifier.value = 0.0;
    _pingNotifier.value = 0;
    _chartPointsNotifier.value = [];

    _phaseNotifier.value = 'PING';
    _pingNotifier.value = await _speedService.testPing();

    _phaseNotifier.value = 'DOWNLOAD';
    try {
      await for (double speed in _speedService.testDownloadSpeed()) {
        _currentSpeedNotifier.value = speed;
        _downloadFinalNotifier.value = speed;
        var updatedPoints = List<double>.from(_chartPointsNotifier.value)..add(speed);
        if (updatedPoints.length > 30) updatedPoints.removeAt(0);
        _chartPointsNotifier.value = updatedPoints;
      }
    } catch (_) {}

    _phaseNotifier.value = 'UPLOAD';
    _chartPointsNotifier.value = [];
    final double uploadResult = await _speedService.testUploadSpeed();
    _currentSpeedNotifier.value = uploadResult;
    _uploadFinalNotifier.value = uploadResult;
    _chartPointsNotifier.value = [uploadResult * 0.4, uploadResult * 0.7, uploadResult];

    _phaseNotifier.value = 'COMPLETED';
    _isTestingNotifier.value = false;

    final prefs = await SharedPreferences.getInstance();
    final resultString = '${DateTime.now().toLocal().toString().substring(11, 16)} | 🔽 ${_downloadFinalNotifier.value.toStringAsFixed(1)} Mb/s | 🔼 ${_uploadFinalNotifier.value.toStringAsFixed(1)} Mb/s';
    _history.insert(0, resultString);
    await prefs.setStringList('speed_history', _history);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final List<Widget> tabs = [_buildMainDashboard(theme), _buildHistoryTab(theme)];

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(child: tabs[_currentIndex]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) => setState(() => _currentIndex = index),
        backgroundColor: theme.colorScheme.surface,
        indicatorColor: theme.colorScheme.primaryContainer.withOpacity(0.5),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.analytics_outlined), selectedIcon: Icon(Icons.analytics), label: 'Jitter'),
          NavigationDestination(icon: Icon(Icons.blur_on_rounded), selectedIcon: Icon(Icons.blur_circular_rounded), label: 'Logs'),
        ],
      ),
    );
  }

  Widget _buildMainDashboard(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28.0, vertical: 20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('CORE NODE', style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                  const SizedBox(height: 4),
                  Text('Paris, FR (Hetzner)', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface.withOpacity(0.6))),
                ],
              ),
              ValueListenableBuilder<bool>(
                valueListenable: _isTestingNotifier,
                builder: (context, isTesting, _) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: isTesting ? theme.colorScheme.errorContainer.withOpacity(0.2) : theme.colorScheme.primaryContainer.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    children: [
                      AnimatedBuilder(
                        animation: _pulseController,
                        builder: (context, child) => Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isTesting ? theme.colorScheme.error.withOpacity(_pulseController.value) : theme.colorScheme.primary.withOpacity(_pulseController.value),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ValueListenableBuilder<String>(
                        valueListenable: _phaseNotifier,
                        builder: (context, phase, _) => Text(phase, style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.bold, letterSpacing: 1.0)),
                      ),
                    ],
                  ),
                ),
              )
            ],
          ),
          const Spacer(),
          Center(
            child: ValueListenableBuilder<double>(
              valueListenable: _currentSpeedNotifier,
              builder: (context, speed, _) => Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 240,
                    height: 240,
                    child: CircularProgressIndicator(
                      value: (speed / 1000).clamp(0.0, 1.0),
                      strokeWidth: 3,
                      backgroundColor: theme.colorScheme.onSurface.withOpacity(0.05),
                      valueColor: AlwaysStoppedAnimation<Color>(theme.colorScheme.primary),
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        speed.toStringAsFixed(1),
                        style: theme.textTheme.displayLarge?.copyWith(fontSize: 64, fontWeight: FontWeight.w200, fontFeatures: [const FontFeature.tabularFigures()]),
                      ),
                      const SizedBox(height: 4),
                      Text('MEGABITS / S', style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurface.withOpacity(0.4), letterSpacing: 2.0)),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const Spacer(),
          SizedBox(
            height: 60,
            child: ValueListenableBuilder<List<double>>(
              valueListenable: _chartPointsNotifier,
              builder: (context, points, _) => CustomPaint(
                painter: _RealTimeChartPainter(points: points, color: theme.colorScheme.primary),
                child: Container(),
              ),
            ),
          ),
          const SizedBox(height: 40),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: theme.colorScheme.onSurface.withOpacity(0.05),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: theme.colorScheme.onSurface.withOpacity(0.05)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildAdvancedStat('LATENCY', _pingNotifier, 'ms', theme),
                Container(width: 1, height: 32, color: theme.colorScheme.onSurface.withOpacity(0.1)),
                _buildAdvancedStat('DOWN', _downloadFinalNotifier, 'Mb/s', theme),
                Container(width: 1, height: 32, color: theme.colorScheme.onSurface.withOpacity(0.1)),
                _buildAdvancedStat('UP', _uploadFinalNotifier, 'Mb/s', theme),
              ],
            ),
          ),
          const SizedBox(height: 32),
          ValueListenableBuilder<bool>(
            valueListenable: _isTestingNotifier,
            builder: (context, isTesting, _) => OutlinedButton(
              onPressed: isTesting ? null : _runAdvancedTest,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 20),
                side: BorderSide(color: isTesting ? theme.colorScheme.onSurface.withOpacity(0.1) : theme.colorScheme.primary, width: 1.5),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
              ),
              child: Text(
                isTesting ? 'RUNNING METRICS...' : 'START PULSE',
                style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 2.0, color: isTesting ? theme.colorScheme.onSurface.withOpacity(0.3) : theme.colorScheme.primary),
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _buildAdvancedStat<T extends num>(String label, ValueNotifier<T> notifier, String unit, ThemeData theme) {
    return Column(
      children: [
        Text(label, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurface.withOpacity(0.4), fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        ValueListenableBuilder<T>(
          valueListenable: notifier,
          builder: (context, value, _) {
            final output = value is double ? value.toStringAsFixed(1) : value.toString();
            return Text('$output $unit', style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600, fontFeatures: [const FontFeature.tabularFigures()]));
          },
        ),
      ],
    );
  }

  Widget _buildHistoryTab(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.all(28.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('METRICS LOGS', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, letterSpacing: 1.5)),
          const SizedBox(height: 24),
          Expanded(
            child: _history.isEmpty
                ? Center(child: Text('No telemetry saved locally.', style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.4))))
                : ListView.builder(
                    itemCount: _history.length,
                    itemBuilder: (context, index) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6.0),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(color: theme.colorScheme.onSurface.withOpacity(0.05), borderRadius: BorderRadius.circular(12)),
                        child: Text(_history[index], style: theme.textTheme.bodySmall?.copyWith(fontFeatures: [const FontFeature.tabularFigures()])),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _RealTimeChartPainter extends CustomPainter {
  final List<double> points;
  final Color color;
  _RealTimeChartPainter({required this.points, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    final paint = Paint()..color = color.withOpacity(0.8)..style = PaintingStyle.stroke..strokeWidth = 2.0..strokeCap = StrokeCap.round;
    final fillPaint = Paint()..color = color.withOpacity(0.05)..style = PaintingStyle.fill;
    final path = Path();
    final double maxSpeed = points.reduce(max).clamp(10.0, double.infinity);
    final double stepX = size.width / (points.length > 1 ? points.length - 1 : 1);
    path.moveTo(0, size.height - (points[0] / maxSpeed * size.height));
    for (int i = 1; i < points.length; i++) {
      path.lineTo(i * stepX, size.height - (points[i] / maxSpeed * size.height));
    }
    final fillPath = Path()
      ..addPath(path, Offset.zero)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _RealTimeChartPainter oldDelegate) => oldDelegate.points != points;
}