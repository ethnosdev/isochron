import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppThemeMode { system, light, dark }

class UserSettingsService {
  // Singleton Pattern
  static final UserSettingsService _instance = UserSettingsService._internal();
  factory UserSettingsService() => _instance;
  UserSettingsService._internal();

  late SharedPreferences _prefs;

  // Keys
  static const String _keyLastProjectDir = 'last_project_dir';
  static const String _keyLastSourceDir = 'last_source_dir';
  static const String _keyLastDictDir = 'last_dict_dir';
  static const String _keyThemeMode = 'theme_mode';
  static const String _keyLastZoom = 'last_zoom_level';

  late final ValueNotifier<AppThemeMode> themeNotifier;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();

    // Load saved theme or default to system
    final savedThemeIndex =
        _prefs.getInt(_keyThemeMode) ?? AppThemeMode.system.index;
    themeNotifier = ValueNotifier(AppThemeMode.values[savedThemeIndex]);
  }

  // --- Theme ---

  Future<void> setThemeMode(AppThemeMode mode) async {
    themeNotifier.value = mode;
    await _prefs.setInt(_keyThemeMode, mode.index);
  }

  // --- Directory Settings ---

  String? get lastProjectDir => _prefs.getString(_keyLastProjectDir);
  Future<void> setLastProjectDir(String path) async {
    await _prefs.setString(_keyLastProjectDir, path);
  }

  String? get lastSourceDir => _prefs.getString(_keyLastSourceDir);
  Future<void> setLastSourceDir(String path) async {
    await _prefs.setString(_keyLastSourceDir, path);
  }

  String? get lastDictDir => _prefs.getString(_keyLastDictDir);
  Future<void> setLastDictDir(String path) async {
    await _prefs.setString(_keyLastDictDir, path);
  }

  // --- Zoom Setting ---

  double get lastZoom => _prefs.getDouble(_keyLastZoom) ?? 10.0;
  Future<void> setLastZoom(double value) async {
    await _prefs.setDouble(_keyLastZoom, value);
  }
}
