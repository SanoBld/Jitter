import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// One ValueNotifier per app-wide setting
final themeModeNotifier        = ValueNotifier<ThemeMode>(ThemeMode.system);
final useDynamicColorNotifier  = ValueNotifier<bool>(true);
final seedColorNotifier        = ValueNotifier<Color>(kPresetColors[0]);
final selectedServerNotifier   = ValueNotifier<int>(0);
final speedUnitMbpsNotifier    = ValueNotifier<bool>(true);   // true = Mb/s
final autoSaveHistoryNotifier  = ValueNotifier<bool>(true);
final testDurationSecsNotifier = ValueNotifier<int>(30);      // 0 = infinite
final autoFallbackNotifier     = ValueNotifier<bool>(true);   // try next server on failure
final useGpsLocationNotifier   = ValueNotifier<bool>(true);   // use device GPS if available

// IP-based location (city + ISP from public IP)
final ipLocationNotifier       = ValueNotifier<String>('');
final ispNameNotifier          = ValueNotifier<String>('');
final locationFetchingNotifier = ValueNotifier<bool>(false);

// GPS-based location (device sensor)
final gpsLocationNotifier      = ValueNotifier<String>('');
final gpsLatNotifier           = ValueNotifier<double?>(null);
final gpsLngNotifier           = ValueNotifier<double?>(null);
final gpsFetchingNotifier      = ValueNotifier<bool>(false);

// Which location string is "active" for display and history saving
String get activeLocation {
  if (useGpsLocationNotifier.value && gpsLocationNotifier.value.isNotEmpty) {
    return gpsLocationNotifier.value;
  }
  return ipLocationNotifier.value;
}

// Legacy alias so existing code still compiles
ValueNotifier<String> get userLocationNotifier => ipLocationNotifier;

// Preset accent colors
const List<Color> kPresetColors = [
  Color(0xFF6750A4), // Violet (default)
  Color(0xFF1565C0), // Blue
  Color(0xFF00796B), // Teal
  Color(0xFF2E7D32), // Green
  Color(0xFFE65100), // Orange
  Color(0xFFC62828), // Red
  Color(0xFFAD1457), // Pink
];

// Load all saved settings from disk on startup
Future<void> loadSettings() async {
  final p  = await SharedPreferences.getInstance();
  final ti = (p.getInt('pref_theme') ?? 0).clamp(0, 2);
  themeModeNotifier.value        = ThemeMode.values[ti];
  useDynamicColorNotifier.value  = p.getBool('pref_dynamic_color')     ?? true;
  final ci = (p.getInt('pref_color_index') ?? 0).clamp(0, kPresetColors.length - 1);
  seedColorNotifier.value        = kPresetColors[ci];
  selectedServerNotifier.value   = p.getInt('pref_server')             ?? 0;
  speedUnitMbpsNotifier.value    = p.getBool('pref_unit_mbps')         ?? true;
  autoSaveHistoryNotifier.value  = p.getBool('pref_auto_save')         ?? true;
  testDurationSecsNotifier.value = p.getInt('pref_test_duration_secs') ?? 30;
  autoFallbackNotifier.value     = p.getBool('pref_auto_fallback')     ?? true;
  useGpsLocationNotifier.value   = p.getBool('pref_use_gps')           ?? true;
  ipLocationNotifier.value       = p.getString('pref_ip_location')     ?? '';
  ispNameNotifier.value          = p.getString('pref_isp_name')        ?? '';
  gpsLocationNotifier.value      = p.getString('pref_gps_location')    ?? '';
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

Future<void> setTestDuration(int secs) async {
  testDurationSecsNotifier.value = secs;
  (await _p).setInt('pref_test_duration_secs', secs);
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