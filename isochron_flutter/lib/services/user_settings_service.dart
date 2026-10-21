import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

enum AppThemeMode { system, light, dark }

class RecentProjectEntry {
  final String path;
  final String name;
  final String directory;

  const RecentProjectEntry({
    required this.path,
    required this.name,
    required this.directory,
  });
}

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

  ValueNotifier<AppThemeMode>? _themeNotifier;
  ValueNotifier<AppThemeMode> get themeNotifier =>
      _themeNotifier ??= ValueNotifier(AppThemeMode.system);

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();

    // Load saved theme or default to system
    final savedThemeIndex =
        _prefs.getInt(_keyThemeMode) ?? AppThemeMode.system.index;
    if (_themeNotifier == null) {
      _themeNotifier = ValueNotifier(AppThemeMode.values[savedThemeIndex]);
    } else {
      _themeNotifier!.value = AppThemeMode.values[savedThemeIndex];
    }
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

  // --- Recent Projects ---

  static const String _keyRecentProjects = 'recent_projects';

  List<String> get recentProjectPaths {
    final list = _prefs.getStringList(_keyRecentProjects) ?? [];
    return list.where((path) => File(path).existsSync()).toList();
  }

  /// Returns recent projects parsed with their display names read from project.json
  /// (falling back to folder name if unreadable).
  List<RecentProjectEntry> get recentProjects {
    final paths = recentProjectPaths;
    return paths.map((path) {
      String name = '';
      try {
        final file = File(path);
        if (file.existsSync()) {
          final content = file.readAsStringSync();
          final data = jsonDecode(content);
          if (data is Map &&
              data['name'] != null &&
              data['name'].toString().trim().isNotEmpty) {
            name = data['name'].toString().trim();
          }
        }
      } catch (_) {}

      final dir = FileSystemEntity.isDirectorySync(path)
          ? path
          : p.dirname(path);

      if (name.isEmpty) {
        name = p.basename(dir);
        if (name.isEmpty) name = p.basename(path);
      }

      return RecentProjectEntry(
        path: path,
        name: name,
        directory: dir,
      );
    }).toList();
  }

  Future<void> addRecentProject(String projectJsonPath) async {
    final current =
        List<String>.from(_prefs.getStringList(_keyRecentProjects) ?? []);
    current.remove(projectJsonPath);
    current.insert(0, projectJsonPath);
    final filtered =
        current.where((path) => File(path).existsSync()).take(10).toList();
    await _prefs.setStringList(_keyRecentProjects, filtered);
  }
}
