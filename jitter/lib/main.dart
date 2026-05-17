import 'package:flutter/material.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'app_state.dart';
import 'screens/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const JitterApp());
}

class JitterApp extends StatelessWidget {
  const JitterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeModeNotifier,
      builder: (context, mode, _) => ValueListenableBuilder<bool>(
        valueListenable: useDynamicColorNotifier,
        builder: (context, useDynamic, _) => DynamicColorBuilder(
          builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
            final light = (useDynamic && lightDynamic != null) ? lightDynamic : ColorScheme.fromSeed(seedColor: const Color(0xFF6750A4));
            final dark = (useDynamic && darkDynamic != null) ? darkDynamic : ColorScheme.fromSeed(seedColor: const Color(0xFF6750A4), brightness: Brightness.dark);
            return MaterialApp(
              title: 'Jitter',
              debugShowCheckedModeBanner: false,
              theme: ThemeData(colorScheme: light, useMaterial3: true),
              darkTheme: ThemeData(colorScheme: dark, useMaterial3: true),
              themeMode: mode,
              home: const HomeScreen(),
            );
          },
        ),
      ),
    );
  }
}