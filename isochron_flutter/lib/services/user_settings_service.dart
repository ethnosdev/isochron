import 'package:shared_preferences/shared_preferences.dart';

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
  static const String _keyFfmpegPath = 'ffmpeg';
  static const String _keyEspeakPath = 'espeak';

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
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

  // --- Dictionary ---

  String? get lastDictDir => _prefs.getString(_keyLastDictDir);
  Future<void> setLastDictDir(String path) async {
    await _prefs.setString(_keyLastDictDir, path);
  }

  // --- Tool Settings (FFmpeg / eSpeak) ---

  String get ffmpegPath => _prefs.getString(_keyFfmpegPath) ?? 'ffmpeg';
  Future<void> setFfmpegPath(String path) async {
    await _prefs.setString(_keyFfmpegPath, path);
  }

  String get espeakPath => _prefs.getString(_keyEspeakPath) ?? 'espeak-ng';
  Future<void> setEspeakPath(String path) async {
    await _prefs.setString(_keyEspeakPath, path);
  }
}
