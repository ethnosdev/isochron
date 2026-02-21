import 'package:flutter/material.dart';
import 'package:isochron_flutter/services/user_settings_service.dart';
import 'ui/welcome_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await UserSettingsService().init();
  runApp(const IsochronApp());
}

class IsochronApp extends StatelessWidget {
  const IsochronApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: UserSettingsService().themeNotifier,
      builder: (context, currentMode, _) {
        return MaterialApp(
          title: 'Isochron Studio',
          debugShowCheckedModeBanner: false,
          themeMode: currentMode, // <-- Listens to the toggle!
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.teal,
              brightness: Brightness.light,
            ),
            useMaterial3: true,
          ),
          darkTheme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.teal,
              brightness: Brightness.dark,
            ),
            useMaterial3: true,
          ),
          home: const WelcomeScreen(),
        );
      },
    );
  }
}
