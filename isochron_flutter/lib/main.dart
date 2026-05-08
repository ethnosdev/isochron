import 'package:flutter/material.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:isochron_flutter/services/user_settings_service.dart';
import 'ui/workspace/workspace_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await UserSettingsService().init();

  // Configure native macOS window properties
  await WindowManipulator.initialize();
  await WindowManipulator.makeTitlebarTransparent();
  await WindowManipulator.enableFullSizeContentView();
  await WindowManipulator.hideTitle();
  await WindowManipulator.addToolbar();

  runApp(const IsochronApp());
}

class IsochronApp extends StatelessWidget {
  const IsochronApp({super.key});

  ThemeMode _mapTheme(AppThemeMode mode) {
    switch (mode) {
      case AppThemeMode.light:
        return ThemeMode.light;
      case AppThemeMode.dark:
        return ThemeMode.dark;
      case AppThemeMode.system:
        return ThemeMode.system;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppThemeMode>(
      valueListenable: UserSettingsService().themeNotifier,
      builder: (context, currentMode, _) {
        return MacosApp(
          title: 'Isochron Studio',
          debugShowCheckedModeBanner: false,
          themeMode: _mapTheme(currentMode),
          theme: MacosThemeData.light(),
          darkTheme: MacosThemeData.dark(),
          home: const WorkspaceScreen(), // Our new 3-pane shell
        );
      },
    );
  }
}
