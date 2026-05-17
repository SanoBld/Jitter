import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ── Notifiers ──────────────────────────────────────────────────────────────
final themeModeNotifier       = ValueNotifier<ThemeMode>(ThemeMode.system);
final useDynamicColorNotifier = ValueNotifier<bool>(true);
final seedColorNotifier       = ValueNotifier<Color>(kPresetColors[0]);
final selectedServerNotifier  = ValueNotifier<int>(0);
final speedUnitMbpsNotifier   = ValueNotifier<bool>(true);   // true=Mbps false=MB/s
final autoSaveHistoryNotifier = ValueNotifier<bool>(true);
final downloadSizeMBNotifier  = ValueNotifier<int>(100);

// ── Preset accent colours ──────────────────────────────────────────────────
const List<Color> kPresetColors = [
  Color(0xFF6750A4), // Violet (défaut)
  Color(0xFF1565C0), // Bleu
  Color(0xFF00796B), // Sarcelle
  Color(0xFF2E7D32), // Vert
  Color(0xFFE65100), // Orange
  Color(0xFFC62828), // Rouge
  Color(0xFFAD1457), // Rose
];

// ── Persistence ────────────────────────────────────────────────────────────
Future<void> loadSettings() async {
  final p = await SharedPreferences.getInstance();
  final ti = (p.getInt('pref_theme') ?? 0).clamp(0, 2);
  themeModeNotifier.value       = ThemeMode.values[ti];
  useDynamicColorNotifier.value = p.getBool('pref_dynamic_color') ?? true;
  final ci = (p.getInt('pref_color_index') ?? 0).clamp(0, kPresetColors.length - 1);
  seedColorNotifier.value       = kPresetColors[ci];
  selectedServerNotifier.value  = p.getInt('pref_server') ?? 0;
  speedUnitMbpsNotifier.value   = p.getBool('pref_unit_mbps') ?? true;
  autoSaveHistoryNotifier.value = p.getBool('pref_auto_save') ?? true;
  downloadSizeMBNotifier.value  = p.getInt('pref_dl_size') ?? 100;
}

Future<SharedPreferences> get _p => SharedPreferences.getInstance();

Future<void> setThemeMode(ThemeMode m) async {
  themeModeNotifier.value = m;
  (await _p).setInt('pref_theme', m.index);
}

Future<void> setDynamicColor(bool v) async {
  useDynamicColorNotifier.value = v;
  (await _p).setBool('pref_dynamic_color', v);
}

Future<void> setSeedColor(int index) async {
  seedColorNotifier.value = kPresetColors[index];
  (await _p).setInt('pref_color_index', index);
}

Future<void> setServer(int index) async {
  selectedServerNotifier.value = index;
  (await _p).setInt('pref_server', index);
}

Future<void> setSpeedUnit(bool mbps) async {
  speedUnitMbpsNotifier.value = mbps;
  (await _p).setBool('pref_unit_mbps', mbps);
}

Future<void> setAutoSave(bool v) async {
  autoSaveHistoryNotifier.value = v;
  (await _p).setBool('pref_auto_save', v);
}

Future<void> setDownloadSize(int mb) async {
  downloadSizeMBNotifier.value = mb;
  (await _p).setInt('pref_dl_size', mb);
}
