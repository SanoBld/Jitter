import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../app_state.dart';
import '../l10n.dart';
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
        Text(context.tr('settings'),
            style: t.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold, letterSpacing: 1.5)),
        const SizedBox(height: 22),

        _section(context.tr('sLanguage'), [const _LanguageTile()], t),
        const SizedBox(height: 14),

        _section(context.tr('sLocation'), [
          const _GpsTile(),
          const Divider(height: 1),
          const _IpLocationTile(),
        ], t),
        const SizedBox(height: 14),

        _section(context.tr('sAppearance'), [
          const _ThemePicker(),
          const Divider(height: 1),
          const _DynamicColorTile(),
          const Divider(height: 1),
          const _ColorPickerTile(),
        ], t),
        const SizedBox(height: 14),

        _section(context.tr('sServer'), [
          const _ServerExpandable(),
          const Divider(height: 1),
          const _AutoFallbackTile(),
        ], t),
        const SizedBox(height: 14),

        _section('PARALLEL CONNECTIONS', [const _ParallelConnsPicker()], t),
        const SizedBox(height: 14),

        _section(context.tr('sDuration'), [const _DurationSlider()], t),
        const SizedBox(height: 14),

        _section(context.tr('sUnit'), [const _UnitPicker()], t),
        const SizedBox(height: 14),

        _section(context.tr('sHistory'), [
          const _AutoSaveTile(),
          const Divider(height: 1),
          const _ExportCsvTile(),
          const Divider(height: 1),
          const _ClearHistoryTile(),
        ], t),
        const SizedBox(height: 36),

        Center(
          child: Text(context.tr('footer'),
              style: t.textTheme.bodySmall?.copyWith(
                  color: t.colorScheme.onSurface.withValues(alpha: 0.26))),
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
            color:        t.colorScheme.onSurface.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: t.colorScheme.onSurface.withValues(alpha: 0.06)),
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
          SnackBar(content: Text(context.tr('gpsUnavail'))),
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
                    title: Text(context.tr('gpsLocation')),
                    subtitle: Text(context.tr('gpsSubtitle')),
                    value:     useGps,
                    onChanged: setUseGps,
                    secondary: Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: t.colorScheme.tertiaryContainer.withValues(alpha: 0.5),
                      ),
                      child: Icon(Icons.gps_fixed_rounded,
                          size: 16, color: t.colorScheme.tertiary),
                    ),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  ),
                  if (useGps)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: Row(children: [
                        const SizedBox(width: 46),
                        Expanded(
                          child: Text(
                            fetching
                                ? context.tr('detectingGps')
                                : city.isEmpty
                                    ? context.tr('notDetected')
                                    : '📍  $city${lat != null ? '  (${lat.toStringAsFixed(2)}, ${lng?.toStringAsFixed(2)})' : ''}',
                            style: t.textTheme.bodySmall?.copyWith(
                              color: city.isNotEmpty && !fetching
                                  ? t.colorScheme.tertiary
                                  : t.colorScheme.onSurface.withValues(alpha: 0.4),
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
                            tooltip: context.tr('refreshGps'),
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
                color: t.colorScheme.secondaryContainer.withValues(alpha: 0.5),
              ),
              child: fetching
                  ? Padding(
                      padding: const EdgeInsets.all(9),
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: t.colorScheme.secondary))
                  : Icon(Icons.language_rounded,
                      size: 16, color: t.colorScheme.secondary),
            ),
            title: Text(context.tr('ipLocation')),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fetching
                      ? context.tr('detecting')
                      : loc.isEmpty
                          ? context.tr('notDetectedIP')
                          : loc,
                  style: t.textTheme.bodySmall?.copyWith(
                    color: loc.isNotEmpty && !fetching
                        ? t.colorScheme.secondary
                        : t.colorScheme.onSurface.withValues(alpha: 0.38),
                    fontWeight: loc.isNotEmpty && !fetching
                        ? FontWeight.w600
                        : FontWeight.normal,
                  ),
                ),
                if (isp.isNotEmpty && !fetching)
                  Text(isp,
                      style: t.textTheme.bodySmall?.copyWith(
                          fontSize: 11,
                          color: t.colorScheme.onSurface.withValues(alpha: 0.45))),
              ],
            ),
            trailing: IconButton(
              icon: const Icon(Icons.refresh_rounded, size: 17),
              onPressed: fetching ? null : _refresh,
              tooltip: context.tr('refreshIp'),
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
        Text(context.tr('theme'),
            style:
                t.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
        const SizedBox(height: 12),
        ValueListenableBuilder<ThemeMode>(
          valueListenable: themeModeNotifier,
          builder: (_, cur, __) => SegmentedButton<ThemeMode>(
            segments: [
              ButtonSegment(
                  value: ThemeMode.system,
                  label: Text(context.tr('system')),
                  icon:  const Icon(Icons.brightness_auto, size: 14)),
              ButtonSegment(
                  value: ThemeMode.light,
                  label: Text(context.tr('light')),
                  icon:  const Icon(Icons.light_mode, size: 14)),
              ButtonSegment(
                  value: ThemeMode.dark,
                  label: Text(context.tr('dark')),
                  icon:  const Icon(Icons.dark_mode, size: 14)),
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
      title:    Text(context.tr('dynamicColor')),
      subtitle: Text(context.tr('dynamicColorSub')),
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
            Text(context.tr('accentColor'),
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
                            ? [BoxShadow(color: c.withValues(alpha: 0.5), blurRadius: 6)]
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

// ── Server expandable section ──────────────────────────────────────────────
class _ServerExpandable extends StatefulWidget {
  const _ServerExpandable();
  @override
  State<_ServerExpandable> createState() => _ServerExpandableState();
}

class _ServerExpandableState extends State<_ServerExpandable> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final t       = Theme.of(context);
    final servers = InternetSpeedService.servers;

    return ValueListenableBuilder<int>(
      valueListenable: selectedServerNotifier,
      builder: (_, selected, __) {
        // Resolve current server safely
        final curIdx = selected.clamp(0, servers.length - 1);
        final cur    = servers[curIdx];

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header — always visible, tap to expand / collapse
            InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(children: [
                  Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: t.colorScheme.primaryContainer.withValues(alpha: 0.5),
                    ),
                    child: Center(
                      child: Text(cur.flag,
                          style: const TextStyle(fontSize: 16)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(context.tr('selectServer'),
                          style: t.textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w500)),
                      Text(
                        '${cur.name}  ·  ${cur.provider}  ·  ${cur.fileSize}',
                        style: t.textTheme.bodySmall?.copyWith(
                            color:
                                t.colorScheme.onSurface.withValues(alpha: 0.45)),
                      ),
                    ],
                  )),
                  AnimatedRotation(
                    turns:    _expanded ? 0.5 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(Icons.keyboard_arrow_down_rounded,
                        color:
                            t.colorScheme.onSurface.withValues(alpha: 0.4)),
                  ),
                ]),
              ),
            ),

            // Expandable server list
            AnimatedSize(
              duration: const Duration(milliseconds: 280),
              curve:    Curves.easeInOut,
              child: _expanded
                  ? Column(mainAxisSize: MainAxisSize.min, children: [
                      Divider(
                          height: 1,
                          color: t.colorScheme.onSurface
                              .withValues(alpha: 0.07)),
                      // Built-in servers
                      for (int i = 0; i < servers.length; i++) ...[
                        _ServerRow(
                          server:   servers[i],
                          index:    i,
                          selected: selected,
                          onTap:    () {
                            setServer(i);
                            setState(() => _expanded = false);
                          },
                        ),
                        if (i < servers.length - 1)
                          Divider(
                              height: 1,
                              indent: 16,
                              color: t.colorScheme.onSurface
                                  .withValues(alpha: 0.06)),
                      ],
                      // Custom server input
                      Divider(
                          height: 1,
                          color: t.colorScheme.onSurface
                              .withValues(alpha: 0.07)),
                      const _CustomServerTile(),
                    ])
                  : const SizedBox.shrink(),
            ),
          ],
        );
      },
    );
  }
}

// ── Single server row (no deprecated RadioListTile) ────────────────────────
class _ServerRow extends StatelessWidget {
  final SpeedServer server;
  final int         index, selected;
  final VoidCallback onTap;
  const _ServerRow({
    required this.server,
    required this.index,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t   = Theme.of(context);
    final sel = index == selected;
    return InkWell(
      onTap: onTap,
      child: Container(
        color: sel
            ? t.colorScheme.primary.withValues(alpha: 0.05)
            : Colors.transparent,
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(children: [
          Text(server.flag, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 10),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Text(server.name,
                    style: t.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: sel ? t.colorScheme.primary : null,
                    )),
                if (server.minConnections >= 8) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: t.colorScheme.tertiaryContainer
                          .withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text('${server.minConnections}×',
                        style: t.textTheme.labelSmall?.copyWith(
                          fontSize: 9,
                          color:    t.colorScheme.tertiary,
                          fontWeight: FontWeight.w700,
                        )),
                  ),
                ],
              ]),
              Text(
                '${server.location}  ·  ${server.provider}  ·  ${server.fileSize}',
                style: t.textTheme.bodySmall?.copyWith(
                    color: t.colorScheme.onSurface.withValues(alpha: 0.45)),
              ),
            ],
          )),
          if (sel)
            Icon(Icons.check_circle_rounded,
                color: t.colorScheme.primary, size: 20)
          else
            Icon(Icons.radio_button_unchecked_rounded,
                color: t.colorScheme.onSurface.withValues(alpha: 0.25),
                size: 20),
        ]),
      ),
    );
  }
}

// ── Custom server URL input ────────────────────────────────────────────────
class _CustomServerTile extends StatefulWidget {
  const _CustomServerTile();
  @override
  State<_CustomServerTile> createState() => _CustomServerTileState();
}

class _CustomServerTileState extends State<_CustomServerTile> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _urlCtrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: customServerNameNotifier.value);
    _urlCtrl  = TextEditingController(text: customServerUrlNotifier.value);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _urlCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await setCustomServer(_nameCtrl.text.trim(), _urlCtrl.text.trim());
    InternetSpeedService.setCustomServer(
        _nameCtrl.text.trim(), _urlCtrl.text.trim());
    if (mounted) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_urlCtrl.text.trim().isEmpty
            ? 'Custom server removed.'
            : 'Custom server saved.'),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 28, height: 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: t.colorScheme.secondaryContainer.withValues(alpha: 0.5),
            ),
            child: const Center(
                child: Text('🔧', style: TextStyle(fontSize: 13))),
          ),
          const SizedBox(width: 10),
          Text('Custom server',
              style: t.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 4),
        Text(
          'Enter any direct download URL (e.g. http://192.168.1.1/file.bin).',
          style: t.textTheme.bodySmall?.copyWith(
              color: t.colorScheme.onSurface.withValues(alpha: 0.45)),
        ),
        const SizedBox(height: 12),
        // Name field
        TextField(
          controller: _nameCtrl,
          decoration: InputDecoration(
            labelText:       'Server name',
            hintText:        'My NAS / Local server',
            border:          OutlineInputBorder(
                borderRadius: BorderRadius.circular(10)),
            contentPadding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 10),
            isDense: true,
          ),
        ),
        const SizedBox(height: 8),
        // URL field
        TextField(
          controller:   _urlCtrl,
          keyboardType: TextInputType.url,
          decoration: InputDecoration(
            labelText:       'Download URL',
            hintText:        'https://… or http://192.168.x.x/…',
            border:          OutlineInputBorder(
                borderRadius: BorderRadius.circular(10)),
            contentPadding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 10),
            isDense: true,
          ),
        ),
        const SizedBox(height: 10),
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          if (_urlCtrl.text.isNotEmpty)
            TextButton(
              onPressed: () {
                _urlCtrl.clear();
                _nameCtrl.text = 'Custom';
                _save();
              },
              child: const Text('Remove'),
            ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon:  _saving
                ? const SizedBox(width: 14, height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.check_rounded, size: 16),
            label: const Text('Save'),
          ),
        ]),
      ]),
    );
  }
}

// ── Old _ServerList kept as alias (used internally) ────────────────────────

// ── Auto-fallback toggle ───────────────────────────────────────────────────
class _AutoFallbackTile extends StatelessWidget {
  const _AutoFallbackTile();
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: autoFallbackNotifier,
    builder: (_, v, __) => SwitchListTile(
      title:    Text(context.tr('autoFallback')),
      subtitle: Text(context.tr('autoFallbackSub')),
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

  static String _hint(int s, BuildContext ctx) {
    if (s == 0) return ctx.tr('runsUntilStop');
    final pd = (s ~/ 2).clamp(3, 60);
    return '${pd}s ↓  +  ${pd}s ↑';
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
              Text(context.tr('durationPerTest'),
                  style: t.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w500)),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color:        t.colorScheme.primaryContainer.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(_label(secs),
                    style: t.textTheme.labelMedium?.copyWith(
                        color:      t.colorScheme.primary,
                        fontWeight: FontWeight.bold)),
              ),
            ]),
            const SizedBox(height: 4),
            Text(_hint(secs, context),
                style: t.textTheme.bodySmall?.copyWith(
                    color: t.colorScheme.onSurface.withValues(alpha: 0.45))),
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
                            : t.colorScheme.onSurface.withValues(alpha: 0.3),
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

// ── Unit picker — 4 options in a 2×2 grid ─────────────────────────────────
class _UnitPicker extends StatelessWidget {
  const _UnitPicker();

  static const _descriptions = [
    'megabits/s  (standard)',
    'megabytes/s  (÷ 8)',
    'gigabits/s  (÷ 1 000)',
    'gigabytes/s  (÷ 8 000)',
  ];

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(context.tr('speedUnit'),
            style: t.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
        const SizedBox(height: 4),
        Text(context.tr('speedUnitSub'),
            style: t.textTheme.bodySmall?.copyWith(
                color: t.colorScheme.onSurface.withValues(alpha: 0.45))),
        const SizedBox(height: 14),
        ValueListenableBuilder<int>(
          valueListenable: speedUnitIndexNotifier,
          builder: (_, cur, __) => GridView.count(
            crossAxisCount: 2,
            shrinkWrap:     true,
            physics:        const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 8,
            mainAxisSpacing:  8,
            childAspectRatio: 2.8,
            children: List.generate(kSpeedUnitLabels.length, (i) {
              final sel = cur == i;
              return GestureDetector(
                onTap: () => setSpeedUnitIndex(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: sel
                        ? t.colorScheme.primary.withValues(alpha: 0.12)
                        : t.colorScheme.onSurface.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: sel
                          ? t.colorScheme.primary.withValues(alpha: 0.4)
                          : t.colorScheme.onSurface.withValues(alpha: 0.08),
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(kSpeedUnitLabels[i],
                          style: t.textTheme.labelMedium?.copyWith(
                            fontWeight: sel ? FontWeight.w800 : FontWeight.w600,
                            color: sel
                                ? t.colorScheme.primary
                                : t.colorScheme.onSurface.withValues(alpha: 0.75),
                          )),
                      Text(_descriptions[i],
                          style: t.textTheme.labelSmall?.copyWith(
                            fontSize: 9,
                            color: sel
                                ? t.colorScheme.primary.withValues(alpha: 0.65)
                                : t.colorScheme.onSurface.withValues(alpha: 0.38),
                          )),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ]),
    );
  }
}

// ── Parallel connections picker ────────────────────────────────────────────
class _ParallelConnsPicker extends StatelessWidget {
  const _ParallelConnsPicker();

  static const _options = [1, 2, 4, 8, 16];
  static const _labels  = ['1×', '2×', '4×', '8×', '16×'];
  static const _hints   = [
    '~100 Mb/s',
    '~300 Mb/s',
    '~600 Mb/s',
    '~1 Gbps',
    '≥ 2.5 Gbps',
  ];

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Connections per test',
            style: t.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
        const SizedBox(height: 4),
        Text(
          'More connections saturate faster links. Use 8–16× for Gbps fiber '
          'combined with a 1 GB or 10 GB server.',
          style: t.textTheme.bodySmall?.copyWith(
              color: t.colorScheme.onSurface.withValues(alpha: 0.45)),
        ),
        const SizedBox(height: 14),
        ValueListenableBuilder<int>(
          valueListenable: parallelConnsNotifier,
          builder: (_, cur, __) => Row(
            children: List.generate(_options.length, (i) {
              final sel = cur == _options[i];
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: i < _options.length - 1 ? 6 : 0),
                  child: GestureDetector(
                    onTap: () => setParallelConns(_options[i]),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: sel
                            ? t.colorScheme.primary.withValues(alpha: 0.12)
                            : t.colorScheme.onSurface.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: sel
                              ? t.colorScheme.primary.withValues(alpha: 0.4)
                              : t.colorScheme.onSurface.withValues(alpha: 0.08),
                        ),
                      ),
                      child: Column(children: [
                        Text(_labels[i],
                            style: t.textTheme.titleSmall?.copyWith(
                              fontWeight: sel ? FontWeight.w800 : FontWeight.w500,
                              color: sel
                                  ? t.colorScheme.primary
                                  : t.colorScheme.onSurface.withValues(alpha: 0.7),
                            )),
                        const SizedBox(height: 2),
                        Text(_hints[i],
                            textAlign: TextAlign.center,
                            style: t.textTheme.labelSmall?.copyWith(
                              fontSize: 8.5,
                              color: sel
                                  ? t.colorScheme.primary.withValues(alpha: 0.65)
                                  : t.colorScheme.onSurface.withValues(alpha: 0.35),
                            )),
                      ]),
                    ),
                  ),
                ),
              );
            }),
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
      title:     Text(context.tr('autoSave')),
      subtitle:  Text(context.tr('autoSaveSub')),
      value:     v,
      onChanged: setAutoSave,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    ),
  );
}

// ── Export CSV tile ────────────────────────────────────────────────────────
class _ExportCsvTile extends StatelessWidget {
  const _ExportCsvTile();

  Future<void> _export(BuildContext context) async {
    final p   = await SharedPreferences.getInstance();
    final raw = p.getStringList('speed_history') ?? [];
    if (raw.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('exportEmpty'))),
        );
      }
      return;
    }

    final buf = StringBuffer();
    buf.writeln('timestamp,flag,server,provider,server_location,'
        'user_location,download_mbps,upload_mbps,ping_ms,jitter_ms,unit');
    for (final s in raw) {
      try {
        final j = json.decode(s) as Map<String, dynamic>;
        final row = [
          j['ts'],
          j['flag'],
          j['server'],
          j['provider'] ?? '',
          '"${(j['location'] ?? '').toString().replaceAll('"', '""')}"',
          '"${(j['userLocation'] ?? '').toString().replaceAll('"', '""')}"',
          j['dl'],
          j['ul'],
          j['ping'],
          j['jitter'] ?? 0,
          j['unit'] ?? 'Mb/s',
        ].join(',');
        buf.writeln(row);
      } catch (_) {}
    }

    await Clipboard.setData(ClipboardData(text: buf.toString()));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.tr('exportCopied')),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return ListTile(
      leading: Container(
        width: 36, height: 36,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: t.colorScheme.secondaryContainer.withValues(alpha: 0.5),
        ),
        child: Icon(Icons.file_download_outlined,
            size: 16, color: t.colorScheme.secondary),
      ),
      title: Text(context.tr('exportCsv')),
      subtitle: Text(context.tr('exportCsvSub'),
          style: t.textTheme.bodySmall?.copyWith(
              color: t.colorScheme.onSurface.withValues(alpha: 0.45))),
      onTap: () => _export(context),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    );
  }
}

// ── Clear history tile ─────────────────────────────────────────────────────
class _ClearHistoryTile extends StatelessWidget {
  const _ClearHistoryTile();
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return ListTile(
      leading: Icon(Icons.delete_sweep_outlined, color: t.colorScheme.error),
      title: Text(context.tr('clearLogs'),
          style: TextStyle(color: t.colorScheme.error)),
      subtitle: Text(context.tr('clearLogsSub'),
          style: t.textTheme.bodySmall?.copyWith(
              color: t.colorScheme.onSurface.withValues(alpha: 0.45))),
      onTap: () async {
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title:   Text(context.tr('clearLogsTitle')),
            content: Text(context.tr('clearLogsBody')),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text(context.tr('cancel'))),
              TextButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text(context.tr('delete'),
                      style: TextStyle(color: t.colorScheme.error))),
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

// ── Language picker ────────────────────────────────────────────────────────
class _LanguageTile extends StatelessWidget {
  const _LanguageTile();

  static const _langs = [
    ('en', '🇬🇧', 'English'),
    ('fr', '🇫🇷', 'Français'),
    ('es', '🇪🇸', 'Español'),
  ];

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return ValueListenableBuilder<Locale>(
      valueListenable: localeNotifier,
      builder: (_, locale, __) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Row(children: [
          for (final (code, flag, name) in _langs) ...[
            Expanded(
              child: GestureDetector(
                onTap: () => setLocale(code),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: locale.languageCode == code
                        ? t.colorScheme.primary.withValues(alpha: 0.12)
                        : t.colorScheme.onSurface.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: locale.languageCode == code
                          ? t.colorScheme.primary.withValues(alpha: 0.4)
                          : t.colorScheme.onSurface.withValues(alpha: 0.07),
                    ),
                  ),
                  child: Column(children: [
                    Text(flag, style: const TextStyle(fontSize: 20)),
                    const SizedBox(height: 4),
                    Text(name,
                        style: t.textTheme.labelSmall?.copyWith(
                          fontWeight: locale.languageCode == code
                              ? FontWeight.w700
                              : FontWeight.w400,
                          color: locale.languageCode == code
                              ? t.colorScheme.primary
                              : t.colorScheme.onSurface.withValues(alpha: 0.55),
                        )),
                  ]),
                ),
              ),
            ),
            if (code != 'es') const SizedBox(width: 8),
          ],
        ]),
      ),
    );
  }
}