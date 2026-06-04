import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'app_state.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
          builder: (_, seedColor, __) => ValueListenableBuilder<Locale>(
            valueListenable: localeNotifier,
            builder: (_, locale, __) => DynamicColorBuilder(
              builder: (ColorScheme? lightDyn, ColorScheme? darkDyn) {
                final light = (useDynamic && lightDyn != null)
                    ? lightDyn
                    : ColorScheme.fromSeed(seedColor: seedColor);
                final dark = (useDynamic && darkDyn != null)
                    ? darkDyn
                    : ColorScheme.fromSeed(
                        seedColor:  seedColor,
                        brightness: Brightness.dark,
                      );
                return MaterialApp(
                  title:    'Jitter',
                  debugShowCheckedModeBanner: false,
                  theme:     ThemeData(colorScheme: light, useMaterial3: true),
                  darkTheme: ThemeData(colorScheme: dark,  useMaterial3: true),
                  themeMode: mode,
                  locale:    locale,
                  supportedLocales: const [
                    Locale('en'),
                    Locale('fr'),
                    Locale('es'),
                  ],
                  localizationsDelegates: const [
                    GlobalMaterialLocalizations.delegate,
                    GlobalWidgetsLocalizations.delegate,
                    GlobalCupertinoLocalizations.delegate,
                  ],
                  home: const HomeScreen(),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}