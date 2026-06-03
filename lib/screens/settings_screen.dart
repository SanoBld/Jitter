import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../app_state.dart';
import '../services/internet_speed_service.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      children: [
        Text('SETTINGS', style: t.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold, letterSpacing: 1.5)),
        const SizedBox(height: 24),

        _section('LOCATION', [const _LocationTile()], t),
        const SizedBox(height: 16),

        _section('APPEARANCE', [
          const _ThemePicker(),
          const Divider(height: 1),
          const _DynamicColorTile(),
          const Divider(height: 1),
          const _ColorPickerTile(),
        ], t),
        const SizedBox(height: 16),

        // Server section includes the auto-fallback toggle
        _section('TEST SERVER', [
          const _ServerList(),
          const Divider(height: 1),
          const _AutoFallbackTile(),
        ], t),
        const SizedBox(height: 16),

        _section('TEST DURATION', [const _DurationSlider()], t),
        const SizedBox(height: 16),

        _section('UNIT', [const _UnitPicker()], t),
        const SizedBox(height: 16),

        _section('HISTORY', [
          const _AutoSaveTile(),
          const Divider(height: 1),
          const _ClearHistoryTile(),
        ], t),
        const SizedBox(height: 40),

        Center(child: Text('Jitter v1.0.0  ·  Made with Flutter',
            style: t.textTheme.bodySmall?.copyWith(
                color: t.colorScheme.onSurface.withOpacity(0.28)))),
      ],
    );
  }

  Widget _section(String title, List<Widget> children, ThemeData t) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(title, style: t.textTheme.labelSmall?.copyWith(
              color:         t.colorScheme.primary,
              fontWeight:    FontWeight.bold,
              letterSpacing: 1.5)),
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

// ── Location tile ──────────────────────────────────────────────────────────
class _LocationTile extends StatelessWidget {
  const _LocationTile();

  Future<void> _refresh() async {
    locationFetchingNotifier.value = true;
    try {
      final info = await InternetSpeedService.getLocationAndIsp();
      if (info.location.isNotEmpty) await setUserLocation(info.location);
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
        valueListenable: userLocationNotifier,
        builder: (_, loc, __) => ValueListenableBuilder<String>(
          valueListenable: ispNameNotifier,
          builder: (_, isp, __) => ListTile(
            leading: Container(
              width: 38, height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: t.colorScheme.primaryContainer.withOpacity(0.5),
              ),
              child: fetching
                  ? Padding(
                      padding: const EdgeInsets.all(10),
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: t.colorScheme.primary,
                      ),
                    )
                  : Icon(Icons.place_rounded, size: 18,
                      color: t.colorScheme.primary),
            ),
            title: const Text('Auto-detected location'),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fetching
                      ? 'Detecting…'
                      : loc.isEmpty
                          ? 'Not detected yet'
                          : loc,
                  style: t.textTheme.bodySmall?.copyWith(
                    color: (fetching || loc.isEmpty)
                        ? t.colorScheme.onSurface.withOpacity(0.38)
                        : t.colorScheme.primary,
                    fontWeight:
                        (fetching || loc.isEmpty) ? FontWeight.w400 : FontWeight.w600,
                  ),
                ),
                if (isp.isNotEmpty && !fetching)
                  Text(isp,
                      style: t.textTheme.bodySmall?.copyWith(
                        color:    t.colorScheme.onSurface.withOpacity(0.5),
                        fontSize: 11,
                      )),
              ],
            ),
            trailing: IconButton(
              icon: fetching
                  ? SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: t.colorScheme.primary.withOpacity(0.5),
                      ),
                    )
                  : const Icon(Icons.refresh_rounded, size: 18),
              onPressed: fetching ? null : _refresh,
              tooltip: 'Refresh location',
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
        Text('Theme', style: t.textTheme.bodyMedium
            ?.copyWith(fontWeight: FontWeight.w500)),
        const SizedBox(height: 12),
        ValueListenableBuilder<ThemeMode>(
          valueListenable: themeModeNotifier,
          builder: (_, cur, __) => SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment(
                  value: ThemeMode.system,
                  label: Text('System'),
                  icon:  Icon(Icons.brightness_auto, size: 15)),
              ButtonSegment(
                  value: ThemeMode.light,
                  label: Text('Light'),
                  icon:  Icon(Icons.light_mode, size: 15)),
              ButtonSegment(
                  value: ThemeMode.dark,
                  label: Text('Dark'),
                  icon:  Icon(Icons.dark_mode, size: 15)),
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
      subtitle: const Text('Follows your wallpaper colors'),
      value:    v,
      onChanged: setDynamicColor,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
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
        opacity:  isDynamic ? 0.38 : 1.0,
        duration: const Duration(milliseconds: 200),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Accent color', style: t.textTheme.bodyMedium
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
                        boxShadow: sel ? [
                          BoxShadow(color: c.withOpacity(0.5), blurRadius: 6)
                        ] : null,
                      ),
                      child: sel
                          ? const Icon(Icons.check_rounded, size: 14,
                              color: Colors.white)
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
                      color: t.colorScheme.onSurface.withOpacity(0.5))),
              dense:          true,
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 2),
            ),
            if (i < servers.length - 1) const Divider(height: 1, indent: 16),
          ]);
        }),
      ),
    );
  }
}

// ── Auto-fallback toggle ───────────────────────────────────────────────────
// When enabled, the app tries the next server if the current one fails
class _AutoFallbackTile extends StatelessWidget {
  const _AutoFallbackTile();
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: autoFallbackNotifier,
    builder: (_, v, __) => SwitchListTile(
      title:    const Text('Auto-fallback'),
      subtitle: const Text('Switch to next server if current one fails'),
      value:    v,
      onChanged: setAutoFallback,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    ),
  );
}

// ── Duration slider ────────────────────────────────────────────────────────
class _DurationSlider extends StatelessWidget {
  const _DurationSlider();

  // 0 = infinite (runs until user stops, max 10 min)
  static const _steps = [5, 10, 15, 20, 30, 60, 0];

  static int _secsToStep(int secs) {
    int closest = 0;
    for (int i = 0; i < _steps.length; i++) {
      if (secs == 0 && _steps[i] == 0) return i;
      if (secs != 0 && (_steps[i] - secs).abs() < (_steps[closest] - secs).abs()
          && _steps[i] != 0) {
        closest = i;
      }
    }
    return secs == 0 ? _steps.length - 1 : closest;
  }

  static String _secsLabel(int secs) {
    if (secs == 0)  return '∞';
    if (secs == 60) return '1 min';
    return '$secs s';
  }

  static String _accuracyHint(int secs) {
    if (secs == 0)  return 'Runs until you press Stop (max 10 min)';
    if (secs <= 5)  return 'Fast — less accurate';
    if (secs <= 15) return 'Good speed / accuracy balance';
    if (secs <= 30) return 'Accurate — recommended';
    return 'Very accurate — like nPerf';
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return ValueListenableBuilder<int>(
      valueListenable: testDurationSecsNotifier,
      builder: (_, cur, __) {
        final stepIdx = _secsToStep(cur);
        final secs    = _steps[stepIdx];
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('Duration per phase',
                  style: t.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w500)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color:        t.colorScheme.primaryContainer.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(_secsLabel(secs),
                    style: t.textTheme.labelMedium?.copyWith(
                        color:      t.colorScheme.primary,
                        fontWeight: FontWeight.bold)),
              ),
            ]),
            const SizedBox(height: 4),

            Text(
              _accuracyHint(secs),
              style: t.textTheme.bodySmall?.copyWith(
                  color: t.colorScheme.onSurface.withOpacity(0.5)),
            ),
            const SizedBox(height: 12),

            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight:  3,
                thumbShape:   const RoundSliderThumbShape(enabledThumbRadius: 8),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
              ),
              child: Slider(
                min:       0,
                max:       (_steps.length - 1).toDouble(),
                divisions: _steps.length - 1,
                value:     stepIdx.toDouble(),
                onChanged: (v) => setTestDuration(_steps[v.round()]),
              ),
            ),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: _steps.map((s) {
                  final selected = s == secs;
                  return Text(
                    s == 0 ? '∞' : s == 60 ? '1m' : '${s}s',
                    style: t.textTheme.labelSmall?.copyWith(
                      color: selected
                          ? t.colorScheme.primary
                          : t.colorScheme.onSurface.withOpacity(0.35),
                      fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                    ),
                  );
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
        Text('Speed unit', style: t.textTheme.bodyMedium
            ?.copyWith(fontWeight: FontWeight.w500)),
        const SizedBox(height: 2),
        Text('Mbps = megabits/s  ·  MB/s = megabytes/s  (÷ 8)',
            style: t.textTheme.bodySmall?.copyWith(
                color: t.colorScheme.onSurface.withOpacity(0.5))),
        const SizedBox(height: 12),
        ValueListenableBuilder<bool>(
          valueListenable: speedUnitMbpsNotifier,
          builder: (_, isMbps, __) => SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: true,  label: Text('Mbps')),
              ButtonSegment(value: false, label: Text('MB/s')),
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
      title:    const Text('Auto-save'),
      subtitle: const Text('Save every test to history'),
      value:    v,
      onChanged: setAutoSave,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
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
      subtitle: Text(
          'Permanently delete all saved results',
          style: t.textTheme.bodySmall?.copyWith(
              color: t.colorScheme.onSurface.withOpacity(0.5))),
      onTap: () async {
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
                    style: TextStyle(color: t.colorScheme.error)),
              ),
            ],
          ),
        );
        if (ok == true) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.remove('speed_history');
        }
      },
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    );
  }
}