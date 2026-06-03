import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'app_state.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock to portrait — speed test gauges only make sense in portrait
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  await loadSettings();
  runApp(const JitterApp());
}

class JitterApp extends StatelessWidget {
  const JitterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeModeNotifier,
      builder: (_, mode, __) => ValueListenableBuilder<bool>(
        valueListenable: useDynamicColorNotifier,
        builder: (_, useDynamic, __) => ValueListenableBuilder<Color>(
          valueListenable: seedColorNotifier,
          builder: (_, seedColor, __) => DynamicColorBuilder(
            builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
              final light = (useDynamic && lightDynamic != null)
                  ? lightDynamic
                  : ColorScheme.fromSeed(seedColor: seedColor);
              final dark = (useDynamic && darkDynamic != null)
                  ? darkDynamic
                  : ColorScheme.fromSeed(
                      seedColor:  seedColor,
                      brightness: Brightness.dark,
                    );
              return MaterialApp(
                title:                     'Jitter',
                debugShowCheckedModeBanner: false,
                theme:     ThemeData(colorScheme: light, useMaterial3: true),
                darkTheme: ThemeData(colorScheme: dark,  useMaterial3: true),
                themeMode: mode,
                home:      const HomeScreen(),
              );
            },
          ),
        ),
      ),
    );
  }
}