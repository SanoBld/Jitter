import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

final themeModeNotifier        = ValueNotifier<ThemeMode>(ThemeMode.system);
final useDynamicColorNotifier  = ValueNotifier<bool>(true);
final seedColorNotifier        = ValueNotifier<Color>(kPresetColors[0]);
final selectedServerNotifier   = ValueNotifier<int>(0);
final speedUnitIndexNotifier   = ValueNotifier<int>(0);
final autoSaveHistoryNotifier  = ValueNotifier<bool>(true);
final autoFallbackNotifier     = ValueNotifier<bool>(true);
final useGpsLocationNotifier   = ValueNotifier<bool>(true);
final localeNotifier           = ValueNotifier<Locale>(const Locale('en'));

// Per-phase test durations (seconds; 0 = infinite)
final dlDurationSecsNotifier  = ValueNotifier<int>(30);
final ulDurationSecsNotifier  = ValueNotifier<int>(30);
final linkDurationsNotifier   = ValueNotifier<bool>(true);

// Legacy single-duration kept for settings screen compat
final testDurationSecsNotifier = ValueNotifier<int>(30);

// IP location
final ipLocationNotifier       = ValueNotifier<String>('');
final ispNameNotifier          = ValueNotifier<String>('');
final locationFetchingNotifier = ValueNotifier<bool>(false);

// GPS location
final gpsLocationNotifier = ValueNotifier<String>('');
final gpsLatNotifier      = ValueNotifier<double?>(null);
final gpsLngNotifier      = ValueNotifier<double?>(null);
final gpsFetchingNotifier = ValueNotifier<bool>(false);

String get activeLocation {
  if (useGpsLocationNotifier.value && gpsLocationNotifier.value.isNotEmpty) {
    return gpsLocationNotifier.value;
  }
  return ipLocationNotifier.value;
}

ValueNotifier<String> get userLocationNotifier => ipLocationNotifier;

// ── Speed unit helpers ─────────────────────────────────────────────────────
const List<String> kSpeedUnitLabels = ['Mb/s', 'MB/s', 'Gb/s', 'GB/s'];

double convertSpeed(double mbps, int unitIdx) {
  switch (unitIdx) {
    case 1: return mbps / 8;
    case 2: return mbps / 1000;
    case 3: return mbps / 8000;
    default: return mbps;
  }
}

String formatSpeedValue(double mbps, int unitIdx) {
  final v = convertSpeed(mbps, unitIdx);
  switch (unitIdx) {
    case 2:
    case 3:
      if (v >= 1.0) return v.toStringAsFixed(2);
      if (v >= 0.1) return v.toStringAsFixed(3);
      return v.toStringAsFixed(4);
    default:
      return v >= 100 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
  }
}

const List<Color> kPresetColors = [
  Color(0xFF6750A4),
  Color(0xFF1565C0),
  Color(0xFF00796B),
  Color(0xFF2E7D32),
  Color(0xFFE65100),
  Color(0xFFC62828),
  Color(0xFFAD1457),
];

const _kSupportedLocales = ['en', 'fr', 'es'];

Future<void> loadSettings() async {
  final p  = await SharedPreferences.getInstance();
  final ti = (p.getInt('pref_theme') ?? 0).clamp(0, 2);
  themeModeNotifier.value       = ThemeMode.values[ti];
  useDynamicColorNotifier.value = p.getBool('pref_dynamic_color') ?? true;
  final ci = (p.getInt('pref_color_index') ?? 0).clamp(0, kPresetColors.length - 1);
  seedColorNotifier.value       = kPresetColors[ci];
  selectedServerNotifier.value  = p.getInt('pref_server') ?? 0;

  if (p.containsKey('pref_unit_index')) {
    speedUnitIndexNotifier.value =
        (p.getInt('pref_unit_index') ?? 0).clamp(0, kSpeedUnitLabels.length - 1);
  } else {
    speedUnitIndexNotifier.value = (p.getBool('pref_unit_mbps') ?? true) ? 0 : 1;
  }

  autoSaveHistoryNotifier.value = p.getBool('pref_auto_save')     ?? true;
  autoFallbackNotifier.value    = p.getBool('pref_auto_fallback') ?? true;
  useGpsLocationNotifier.value  = p.getBool('pref_use_gps')       ?? true;
  ipLocationNotifier.value      = p.getString('pref_ip_location') ?? '';
  ispNameNotifier.value         = p.getString('pref_isp_name')    ?? '';
  gpsLocationNotifier.value     = p.getString('pref_gps_location') ?? '';

  // Durations
  final legacy = p.getInt('pref_test_duration_secs') ?? 30;
  dlDurationSecsNotifier.value  = p.getInt('pref_dl_duration') ?? legacy;
  ulDurationSecsNotifier.value  = p.getInt('pref_ul_duration') ?? legacy;
  linkDurationsNotifier.value   = p.getBool('pref_link_durations') ?? true;
  testDurationSecsNotifier.value = dlDurationSecsNotifier.value;

  final lang = p.getString('pref_locale') ?? 'en';
  localeNotifier.value = Locale(_kSupportedLocales.contains(lang) ? lang : 'en');
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

Future<void> setSpeedUnitIndex(int idx) async {
  speedUnitIndexNotifier.value = idx.clamp(0, kSpeedUnitLabels.length - 1);
  (await _p).setInt('pref_unit_index', speedUnitIndexNotifier.value);
}

Future<void> setSpeedUnit(bool mbps) => setSpeedUnitIndex(mbps ? 0 : 1);

Future<void> setDlDuration(int secs) async {
  dlDurationSecsNotifier.value   = secs;
  testDurationSecsNotifier.value = secs;
  (await _p).setInt('pref_dl_duration', secs);
  if (linkDurationsNotifier.value) {
    ulDurationSecsNotifier.value = secs;
    (await _p).setInt('pref_ul_duration', secs);
  }
}

Future<void> setUlDuration(int secs) async {
  ulDurationSecsNotifier.value = secs;
  (await _p).setInt('pref_ul_duration', secs);
  if (linkDurationsNotifier.value) {
    dlDurationSecsNotifier.value   = secs;
    testDurationSecsNotifier.value = secs;
    (await _p).setInt('pref_dl_duration', secs);
  }
}

Future<void> setLinkDurations(bool v) async {
  linkDurationsNotifier.value = v;
  (await _p).setBool('pref_link_durations', v);
  if (v) {
    // Sync UL to DL when re-linking
    ulDurationSecsNotifier.value = dlDurationSecsNotifier.value;
    (await _p).setInt('pref_ul_duration', dlDurationSecsNotifier.value);
  }
}

Future<void> setTestDuration(int secs) async {
  testDurationSecsNotifier.value = secs;
  dlDurationSecsNotifier.value   = secs;
  ulDurationSecsNotifier.value   = secs;
  (await _p).setInt('pref_test_duration_secs', secs);
  (await _p).setInt('pref_dl_duration', secs);
  (await _p).setInt('pref_ul_duration', secs);
}

Future<void> setAutoSave(bool v) async {
  autoSaveHistoryNotifier.value = v;
  (await _p).setBool('pref_auto_save', v);
}

Future<void> setAutoFallback(bool v) async {
  autoFallbackNotifier.value = v;
  (await _p).setBool('pref_auto_fallback', v);
}

Future<void> setUseGps(bool v) async {
  useGpsLocationNotifier.value = v;
  (await _p).setBool('pref_use_gps', v);
}

Future<void> setIpLocation(String loc) async {
  ipLocationNotifier.value = loc;
  (await _p).setString('pref_ip_location', loc);
}

Future<void> setUserLocation(String loc) => setIpLocation(loc);

Future<void> setIspName(String name) async {
  ispNameNotifier.value = name;
  (await _p).setString('pref_isp_name', name);
}

Future<void> setGpsLocation(String city, double? lat, double? lng) async {
  gpsLocationNotifier.value = city;
  gpsLatNotifier.value      = lat;
  gpsLngNotifier.value      = lng;
  (await _p).setString('pref_gps_location', city);
}

Future<void> setLocale(String lang) async {
  localeNotifier.value = Locale(lang);
  (await _p).setString('pref_locale', lang);
}