import 'package:flutter/material.dart';
import 'package:isochron_flutter/services/user_settings_service.dart';
import 'ui/welcome_screen.dart'; // Import the new screen

void main() async {
  // 1. Ensure bindings are initialized
  WidgetsFlutterBinding.ensureInitialized();

  // 2. Init Settings
  await UserSettingsService().init();

  runApp(const IsochronApp());
}

class IsochronApp extends StatelessWidget {
  const IsochronApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Isochron Studio',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: const WelcomeScreen(),
    );
  }
}
