import 'package:flutter/material.dart';
import '../../services/user_settings_service.dart';

class ThemeToggleButton extends StatelessWidget {
  const ThemeToggleButton({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: UserSettingsService().themeNotifier,
      builder: (context, mode, _) {
        // Determine if we are currently displaying dark mode
        final isDark =
            mode == ThemeMode.dark ||
            (mode == ThemeMode.system &&
                MediaQuery.platformBrightnessOf(context) == Brightness.dark);

        return IconButton(
          icon: Icon(isDark ? Icons.light_mode : Icons.dark_mode),
          tooltip: "Toggle Theme",
          onPressed: () {
            // Toggle between light and dark
            final newMode = isDark ? ThemeMode.light : ThemeMode.dark;
            UserSettingsService().setThemeMode(newMode);
          },
        );
      },
    );
  }
}
