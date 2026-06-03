import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../app_state.dart';
import '../services/internet_speed_service.dart';
import '../services/location_service.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      children: [
        Text('SETTINGS',
            style: t.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold, letterSpacing: 1.5)),
        const SizedBox(height: 22),

        _section('LOCATION', [
          const _GpsTile(),
          const Divider(height: 1),
          const _IpLocationTile(),
        ], t),
        const SizedBox(height: 14),

        _section('APPEARANCE', [
          const _ThemePicker(),
          const Divider(height: 1),
          const _DynamicColorTile(),
          const Divider(height: 1),
          const _ColorPickerTile(),
        ], t),
        const SizedBox(height: 14),

        _section('TEST SERVER', [
          const _ServerList(),
          const Divider(height: 1),
          const _AutoFallbackTile(),
        ], t),
        const SizedBox(height: 14),

        _section('TEST DURATION', [const _DurationSlider()], t),
        const SizedBox(height: 14),

        _section('UNIT', [const _UnitPicker()], t),
        const SizedBox(height: 14),

        _section('HISTORY', [
          const _AutoSaveTile(),
          const Divider(height: 1),
          const _ClearHistoryTile(),
        ], t),
        const SizedBox(height: 36),

        Center(
          child: Text('Jitter v1.0.0  ·  Made with Flutter',
              style: t.textTheme.bodySmall?.copyWith(
                  color: t.colorScheme.onSurface.withOpacity(0.26))),
        ),
      ],
    );
  }

  static Widget _section(String title, List<Widget> children, ThemeData t) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(title,
              style: t.textTheme.labelSmall?.copyWith(
                color:         t.colorScheme.primary,
                fontWeight:    FontWeight.bold,
                letterSpacing: 1.5,
              )),
        ),
        Container(
          decoration: BoxDecoration(
            color:        t.colorScheme.onSurface.withOpacity(0.04),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: t.colorScheme.onSurface.withOpacity(0.06)),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Column(children: children),
          ),
        ),
      ]);
}

// ── GPS location tile ──────────────────────────────────────────────────────
class _GpsTile extends StatelessWidget {
  const _GpsTile();

  Future<void> _requestGps(BuildContext context) async {
    gpsFetchingNotifier.value = true;
    try {
      final result = await LocationService.getGpsLocation();
      if (result.city.isNotEmpty) {
        await setGpsLocation(result.city, result.lat, result.lng);
      } else if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('GPS unavailable — check location permissions.'),
          ),
        );
      }
    } finally {
      gpsFetchingNotifier.value = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return ValueListenableBuilder<bool>(
      valueListenable: useGpsLocationNotifier,
      builder: (_, useGps, __) => ValueListenableBuilder<bool>(
        valueListenable: gpsFetchingNotifier,
        builder: (_, fetching, __) => ValueListenableBuilder<String>(
          valueListenable: gpsLocationNotifier,
          builder: (_, city, __) => ValueListenableBuilder<double?>(
            valueListenable: gpsLatNotifier,
            builder: (_, lat, __) => ValueListenableBuilder<double?>(
              valueListenable: gpsLngNotifier,
              builder: (_, lng, __) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SwitchListTile(
                    title: const Text('GPS location'),
                    subtitle: const Text(
                        'Use device sensor for your real city name'),
                    value:     useGps,
                    onChanged: setUseGps,
                    secondary: Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: t.colorScheme.tertiaryContainer.withOpacity(0.5),
                      ),
                      child: Icon(Icons.gps_fixed_rounded,
                          size: 16, color: t.colorScheme.tertiary),
                    ),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  ),
                  // Show GPS result when enabled
                  if (useGps)
                    Padding(
                      padding:
                          const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: Row(children: [
                        const SizedBox(width: 46),
                        Expanded(
                          child: Text(
                            fetching
                                ? 'Detecting GPS location…'
                                : city.isEmpty
                                    ? 'Not detected — tap to try'
                                    : '📍  $city${lat != null ? '  (${lat.toStringAsFixed(2)}, ${lng?.toStringAsFixed(2)})' : ''}',
                            style: t.textTheme.bodySmall?.copyWith(
                              color: city.isNotEmpty && !fetching
                                  ? t.colorScheme.tertiary
                                  : t.colorScheme.onSurface.withOpacity(0.4),
                              fontWeight: city.isNotEmpty && !fetching
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                          ),
                        ),
                        if (!fetching)
                          IconButton(
                            icon: const Icon(Icons.refresh_rounded, size: 16),
                            onPressed: () => _requestGps(context),
                            tooltip: 'Refresh GPS location',
                            color: t.colorScheme.tertiary,
                            visualDensity: VisualDensity.compact,
                          )
                        else
                          Padding(
                            padding: const EdgeInsets.all(8),
                            child: SizedBox(
                              width: 14, height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: t.colorScheme.tertiary,
                              ),
                            ),
                          ),
                      ]),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── IP location tile ───────────────────────────────────────────────────────
class _IpLocationTile extends StatelessWidget {
  const _IpLocationTile();

  Future<void> _refresh() async {
    locationFetchingNotifier.value = true;
    try {
      final info = await InternetSpeedService.getLocationAndIsp();
      if (info.location.isNotEmpty) await setIpLocation(info.location);
      if (info.isp.isNotEmpty)      await setIspName(info.isp);
    } finally {
      locationFetchingNotifier.value = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return ValueListenableBuilder<bool>(
      valueListenable: locationFetchingNotifier,
      builder: (_, fetching, __) => ValueListenableBuilder<String>(
        valueListenable: ipLocationNotifier,
        builder: (_, loc, __) => ValueListenableBuilder<String>(
          valueListenable: ispNameNotifier,
          builder: (_, isp, __) => ListTile(
            leading: Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: t.colorScheme.secondaryContainer.withOpacity(0.5),
              ),
              child: fetching
                  ? Padding(
                      padding: const EdgeInsets.all(9),
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: t.colorScheme.secondary))
                  : Icon(Icons.language_rounded,
                      size: 16, color: t.colorScheme.secondary),
            ),
            title: const Text('IP-based location'),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fetching
                      ? 'Detecting…'
                      : loc.isEmpty
                          ? 'Not detected'
                          : loc,
                  style: t.textTheme.bodySmall?.copyWith(
                    color: loc.isNotEmpty && !fetching
                        ? t.colorScheme.secondary
                        : t.colorScheme.onSurface.withOpacity(0.38),
                    fontWeight: loc.isNotEmpty && !fetching
                        ? FontWeight.w600
                        : FontWeight.normal,
                  ),
                ),
                if (isp.isNotEmpty && !fetching)
                  Text(isp,
                      style: t.textTheme.bodySmall?.copyWith(
                          fontSize: 11,
                          color: t.colorScheme.onSurface.withOpacity(0.45))),
              ],
            ),
            trailing: IconButton(
              icon: const Icon(Icons.refresh_rounded, size: 17),
              onPressed: fetching ? null : _refresh,
              tooltip: 'Refresh IP location',
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            isThreeLine: isp.isNotEmpty && !fetching,
          ),
        ),
      ),
    );
  }
}

// ── Theme picker ───────────────────────────────────────────────────────────
class _ThemePicker extends StatelessWidget {
  const _ThemePicker();
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Theme',
            style:
                t.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
        const SizedBox(height: 12),
        ValueListenableBuilder<ThemeMode>(
          valueListenable: themeModeNotifier,
          builder: (_, cur, __) => SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment(
                  value: ThemeMode.system,
                  label: Text('System'),
                  icon:  Icon(Icons.brightness_auto, size: 14)),
              ButtonSegment(
                  value: ThemeMode.light,
                  label: Text('Light'),
                  icon:  Icon(Icons.light_mode, size: 14)),
              ButtonSegment(
                  value: ThemeMode.dark,
                  label: Text('Dark'),
                  icon:  Icon(Icons.dark_mode, size: 14)),
            ],
            selected:           {cur},
            onSelectionChanged: (s) => setThemeMode(s.first),
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ),
      ]),
    );
  }
}

// ── Dynamic color toggle ───────────────────────────────────────────────────
class _DynamicColorTile extends StatelessWidget {
  const _DynamicColorTile();
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: useDynamicColorNotifier,
    builder: (_, v, __) => SwitchListTile(
      title:    const Text('Dynamic color'),
      subtitle: const Text('Follows your wallpaper colors (Android 12+)'),
      value:    v,
      onChanged: setDynamicColor,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    ),
  );
}

// ── Accent color picker ────────────────────────────────────────────────────
class _ColorPickerTile extends StatelessWidget {
  const _ColorPickerTile();
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return ValueListenableBuilder<bool>(
      valueListenable: useDynamicColorNotifier,
      builder: (_, isDynamic, __) => AnimatedOpacity(
        opacity:  isDynamic ? 0.35 : 1.0,
        duration: const Duration(milliseconds: 200),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Accent color',
                style: t.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w500)),
            const SizedBox(height: 12),
            ValueListenableBuilder<Color>(
              valueListenable: seedColorNotifier,
              builder: (_, cur, __) => Wrap(
                spacing: 10, runSpacing: 10,
                children: List.generate(kPresetColors.length, (i) {
                  final c   = kPresetColors[i];
                  final sel = cur == c;
                  return GestureDetector(
                    onTap: isDynamic ? null : () => setSeedColor(i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 32, height: 32,
                      decoration: BoxDecoration(
                        color:  c,
                        shape:  BoxShape.circle,
                        border: Border.all(
                          color: sel ? Colors.white : Colors.transparent,
                          width: 2.5,
                        ),
                        boxShadow: sel
                            ? [BoxShadow(color: c.withOpacity(0.5), blurRadius: 6)]
                            : null,
                      ),
                      child: sel
                          ? const Icon(Icons.check_rounded,
                              size: 14, color: Colors.white)
                          : null,
                    ),
                  );
                }),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// ── Server list ────────────────────────────────────────────────────────────
class _ServerList extends StatelessWidget {
  const _ServerList();
  @override
  Widget build(BuildContext context) {
    final t       = Theme.of(context);
    final servers = InternetSpeedService.availableServers;
    return ValueListenableBuilder<int>(
      valueListenable: selectedServerNotifier,
      builder: (_, selected, __) => Column(
        children: List.generate(servers.length, (i) {
          final s = servers[i];
          return Column(children: [
            RadioListTile<int>(
              value:      i,
              groupValue: selected,
              onChanged:  (v) => setServer(v!),
              title: Text('${s.flag}  ${s.name}',
                  style: t.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w500)),
              subtitle: Text('${s.location} — ${s.provider}',
                  style: t.textTheme.bodySmall?.copyWith(
                      color: t.colorScheme.onSurface.withOpacity(0.45))),
              dense:          true,
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 2),
            ),
            if (i < servers.length - 1)
              Divider(height: 1, indent: 16,
                  color: t.colorScheme.onSurface.withOpacity(0.06)),
          ]);
        }),
      ),
    );
  }
}

// ── Auto-fallback toggle ───────────────────────────────────────────────────
class _AutoFallbackTile extends StatelessWidget {
  const _AutoFallbackTile();
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: autoFallbackNotifier,
    builder: (_, v, __) => SwitchListTile(
      title:    const Text('Auto-fallback'),
      subtitle: const Text(
          'Automatically try the next server if the current one fails'),
      value:     v,
      onChanged: setAutoFallback,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    ),
  );
}

// ── Duration slider ────────────────────────────────────────────────────────
class _DurationSlider extends StatelessWidget {
  const _DurationSlider();

  // 0 = infinite (runs until STOP)
  static const _steps = [5, 10, 15, 30, 60, 0];

  static int _idx(int secs) {
    if (secs == 0) return _steps.length - 1;
    int best = 0;
    for (int i = 0; i < _steps.length - 1; i++) {
      if ((_steps[i] - secs).abs() < (_steps[best] - secs).abs()) best = i;
    }
    return best;
  }

  static String _label(int s) {
    if (s == 0)  return '∞';
    if (s == 60) return '1 min';
    return '$s s';
  }

  static String _hint(int s) {
    if (s == 0)    return 'Runs until you press STOP  (max 10 min)';
    final pd = (s == 0 ? 0 : s ~/ 2).clamp(3, 60);
    return '${pd}s ↓ download  +  ${pd}s ↑ upload';
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return ValueListenableBuilder<int>(
      valueListenable: testDurationSecsNotifier,
      builder: (_, cur, __) {
        final idx  = _idx(cur);
        final secs = _steps[idx];
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
              Text('Duration per test',
                  style: t.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w500)),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color:        t.colorScheme.primaryContainer.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(_label(secs),
                    style: t.textTheme.labelMedium?.copyWith(
                        color:      t.colorScheme.primary,
                        fontWeight: FontWeight.bold)),
              ),
            ]),
            const SizedBox(height: 4),
            Text(_hint(secs),
                style: t.textTheme.bodySmall?.copyWith(
                    color: t.colorScheme.onSurface.withOpacity(0.45))),
            const SizedBox(height: 10),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight:  3,
                thumbShape:
                    const RoundSliderThumbShape(enabledThumbRadius: 8),
                overlayShape:
                    const RoundSliderOverlayShape(overlayRadius: 18),
              ),
              child: Slider(
                min:       0,
                max:       (_steps.length - 1).toDouble(),
                divisions: _steps.length - 1,
                value:     idx.toDouble(),
                onChanged: (v) => setTestDuration(_steps[v.round()]),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: _steps.map((s) {
                  final sel = s == secs;
                  return Text(_label(s),
                      style: t.textTheme.labelSmall?.copyWith(
                        fontSize:   10,
                        color: sel
                            ? t.colorScheme.primary
                            : t.colorScheme.onSurface.withOpacity(0.3),
                        fontWeight:
                            sel ? FontWeight.bold : FontWeight.normal,
                      ));
                }).toList(),
              ),
            ),
          ]),
        );
      },
    );
  }
}

// ── Unit picker ────────────────────────────────────────────────────────────
class _UnitPicker extends StatelessWidget {
  const _UnitPicker();
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Speed unit',
            style: t.textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.w500)),
        const SizedBox(height: 2),
        Text('Mb/s = megabits/s  ·  MB/s = megabytes/s  (= Mb/s ÷ 8)',
            style: t.textTheme.bodySmall?.copyWith(
                color: t.colorScheme.onSurface.withOpacity(0.45))),
        const SizedBox(height: 12),
        ValueListenableBuilder<bool>(
          valueListenable: speedUnitMbpsNotifier,
          builder: (_, isMbps, __) => SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: true,  label: Text('Mb/s  (bits)')),
              ButtonSegment(value: false, label: Text('MB/s  (bytes)')),
            ],
            selected:           {isMbps},
            onSelectionChanged: (s) => setSpeedUnit(s.first),
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ),
      ]),
    );
  }
}

// ── Auto-save toggle ───────────────────────────────────────────────────────
class _AutoSaveTile extends StatelessWidget {
  const _AutoSaveTile();
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: autoSaveHistoryNotifier,
    builder: (_, v, __) => SwitchListTile(
      title:     const Text('Auto-save results'),
      subtitle:  const Text('Automatically add each test to the logs'),
      value:     v,
      onChanged: setAutoSave,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    ),
  );
}

// ── Clear history tile ─────────────────────────────────────────────────────
class _ClearHistoryTile extends StatelessWidget {
  const _ClearHistoryTile();
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return ListTile(
      leading: Icon(Icons.delete_sweep_outlined, color: t.colorScheme.error),
      title: Text('Clear all logs',
          style: TextStyle(color: t.colorScheme.error)),
      subtitle: Text('Permanently delete all saved results',
          style: t.textTheme.bodySmall?.copyWith(
              color: t.colorScheme.onSurface.withOpacity(0.45))),
      onTap: () async {
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title:   const Text('Clear logs'),
            content: const Text(
                'Delete all results? This cannot be undone.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel')),
              TextButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text('Delete',
                      style: TextStyle(
                          color: t.colorScheme.error))),
            ],
          ),
        );
        if (ok == true) {
          final p = await SharedPreferences.getInstance();
          await p.remove('speed_history');
        }
      },
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    );
  }
}