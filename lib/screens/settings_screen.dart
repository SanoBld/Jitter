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

        _section('APPEARANCE', [
          const _ThemePicker(),
          const Divider(height: 1),
          const _DynamicColorTile(),
          const Divider(height: 1),
          const _ColorPickerTile(),
        ], t),
        const SizedBox(height: 16),

        _section('TEST SERVER', [const _ServerList()], t),
        const SizedBox(height: 16),

        // Durée du test avec slider personnalisable
        _section('TEST DURATION', [const _DurationSlider()], t),
        const SizedBox(height: 16),

        _section('UNITS', [const _UnitPicker()], t),
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
            color: t.colorScheme.primary,
            fontWeight: FontWeight.bold, letterSpacing: 1.5)),
      ),
      Container(
        decoration: BoxDecoration(
          color: t.colorScheme.onSurface.withOpacity(0.04),
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

// ── Theme picker ──────────────────────────────────────────────────────────────
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
              ButtonSegment(value: ThemeMode.system, label: Text('System'),
                  icon: Icon(Icons.brightness_auto, size: 15)),
              ButtonSegment(value: ThemeMode.light,  label: Text('Light'),
                  icon: Icon(Icons.light_mode, size: 15)),
              ButtonSegment(value: ThemeMode.dark,   label: Text('Dark'),
                  icon: Icon(Icons.dark_mode, size: 15)),
            ],
            selected: {cur},
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

// ── Dynamic color toggle ──────────────────────────────────────────────────────
class _DynamicColorTile extends StatelessWidget {
  const _DynamicColorTile();
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: useDynamicColorNotifier,
    builder: (_, v, __) => SwitchListTile(
      title: const Text('Dynamic Color'),
      subtitle: const Text('Follow system wallpaper color'),
      value: v,
      onChanged: setDynamicColor,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    ),
  );
}

// ── Accent colour picker ──────────────────────────────────────────────────────
class _ColorPickerTile extends StatelessWidget {
  const _ColorPickerTile();
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return ValueListenableBuilder<bool>(
      valueListenable: useDynamicColorNotifier,
      builder: (_, isDynamic, __) => AnimatedOpacity(
        opacity: isDynamic ? 0.38 : 1.0,
        duration: const Duration(milliseconds: 200),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Accent Color', style: t.textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.w500)),
            const SizedBox(height: 2),
            Text('Used when Dynamic Color is off',
                style: t.textTheme.bodySmall?.copyWith(
                    color: t.colorScheme.onSurface.withOpacity(0.5))),
            const SizedBox(height: 14),
            ValueListenableBuilder<Color>(
              valueListenable: seedColorNotifier,
              builder: (_, current, __) => Wrap(
                spacing: 10,
                children: List.generate(kPresetColors.length, (i) {
                  final c   = kPresetColors[i];
                  final sel = c.value == current.value;
                  return GestureDetector(
                    onTap: isDynamic ? null : () => setSeedColor(i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 34, height: 34,
                      decoration: BoxDecoration(
                        color: c, shape: BoxShape.circle,
                        border: Border.all(
                          color: sel ? Colors.white : Colors.transparent,
                          width: 2.5,
                        ),
                        boxShadow: sel ? [BoxShadow(
                          color: c.withOpacity(0.5), blurRadius: 8, spreadRadius: 1,
                        )] : [],
                      ),
                      child: sel
                          ? const Icon(Icons.check, color: Colors.white, size: 16)
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

// ── Server list ───────────────────────────────────────────────────────────────
class _ServerList extends StatelessWidget {
  const _ServerList();
  @override
  Widget build(BuildContext context) {
    final t       = Theme.of(context);
    const servers = InternetSpeedService.servers;
    return ValueListenableBuilder<int>(
      valueListenable: selectedServerNotifier,
      builder: (_, selected, __) => Column(
        children: List.generate(servers.length, (i) {
          final s = servers[i];
          return Column(children: [
            RadioListTile<int>(
              value: i, groupValue: selected,
              onChanged: (v) => setServer(v!),
              title: Text('${s.flag}  ${s.name}',
                  style: t.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w500)),
              subtitle: Text('${s.location} — ${s.provider}',
                  style: t.textTheme.bodySmall?.copyWith(
                      color: t.colorScheme.onSurface.withOpacity(0.5))),
              dense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            ),
            if (i < servers.length - 1)
              const Divider(height: 1, indent: 16),
          ]);
        }),
      ),
    );
  }
}

// ── Duration slider ───────────────────────────────────────────────────────────
// Remplace l'ancien SegmentedButton 3 options.
// Valeurs disponibles : 10, 25, 50, 100, 200, 500 MB.
// Le slider affiche une estimation de durée en secondes à 100 Mb/s.
class _DurationSlider extends StatelessWidget {
  const _DurationSlider();

  static const _steps = [10, 25, 50, 100, 200, 500];

  static int _mbToStep(int mb) {
    int closest = 0;
    for (int i = 0; i < _steps.length; i++) {
      if ((_steps[i] - mb).abs() < (_steps[closest] - mb).abs()) closest = i;
    }
    return closest;
  }

  /// Estimation durée en secondes à 100 Mb/s
  static String _estDuration(int mb) {
    final secs = (mb * 8) / 100; // secondes à 100 Mb/s
    if (secs < 60) return '~${secs.round()}s';
    return '~${(secs / 60).toStringAsFixed(1)}min';
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return ValueListenableBuilder<int>(
      valueListenable: downloadSizeMBNotifier,
      builder: (_, cur, __) {
        final stepIdx = _mbToStep(cur);
        final mb      = _steps[stepIdx];
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

            // Titre + valeur courante
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('Volume de test',
                  style: t.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w500)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: t.colorScheme.primaryContainer.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('$mb MB',
                    style: t.textTheme.labelMedium?.copyWith(
                        color: t.colorScheme.primary,
                        fontWeight: FontWeight.bold)),
              ),
            ]),
            const SizedBox(height: 2),

            // Sous-titre dynamique
            Text(
              'Durée estimée : ${_estDuration(mb)} à 100 Mb/s'
              '  ·  Plus grand = plus précis, plus lent',
              style: t.textTheme.bodySmall?.copyWith(
                  color: t.colorScheme.onSurface.withOpacity(0.5)),
            ),
            const SizedBox(height: 12),

            // Slider
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                thumbShape:
                    const RoundSliderThumbShape(enabledThumbRadius: 8),
                overlayShape:
                    const RoundSliderOverlayShape(overlayRadius: 18),
              ),
              child: Slider(
                min: 0,
                max: (_steps.length - 1).toDouble(),
                divisions: _steps.length - 1,
                value: stepIdx.toDouble(),
                onChanged: (v) => setDownloadSize(_steps[v.round()]),
              ),
            ),

            // Labels sous le slider
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: _steps.map((s) {
                  final selected = s == mb;
                  return Text(
                    s >= 1000 ? '${s ~/ 1000}G' : '${s}M',
                    style: t.textTheme.labelSmall?.copyWith(
                      color: selected
                          ? t.colorScheme.primary
                          : t.colorScheme.onSurface.withOpacity(0.35),
                      fontWeight: selected
                          ? FontWeight.bold
                          : FontWeight.normal,
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

// ── Unit picker ───────────────────────────────────────────────────────────────
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
            selected: {isMbps},
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

// ── Auto-save toggle ──────────────────────────────────────────────────────────
class _AutoSaveTile extends StatelessWidget {
  const _AutoSaveTile();
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: autoSaveHistoryNotifier,
    builder: (_, v, __) => SwitchListTile(
      title: const Text('Auto-save results'),
      subtitle: const Text('Save each completed test to Logs'),
      value: v,
      onChanged: setAutoSave,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    ),
  );
}

// ── Clear history tile ────────────────────────────────────────────────────────
class _ClearHistoryTile extends StatelessWidget {
  const _ClearHistoryTile();
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return ListTile(
      leading: Icon(Icons.delete_sweep_outlined, color: t.colorScheme.error),
      title: Text('Clear all logs',
          style: TextStyle(color: t.colorScheme.error)),
      subtitle: Text('Permanently delete saved test results',
          style: t.textTheme.bodySmall?.copyWith(
              color: t.colorScheme.onSurface.withOpacity(0.5))),
      onTap: () async {
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Clear logs'),
            content: const Text(
                'Delete all saved test results? This cannot be undone.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel')),
              TextButton(onPressed: () => Navigator.pop(ctx, true),
                  child: Text('Delete all',
                      style: TextStyle(color: t.colorScheme.error))),
            ],
          ),
        );
        if (ok == true) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.remove('speed_history');
        }
      },
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    );
  }
}