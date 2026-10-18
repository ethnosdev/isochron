import 'package:path/path.dart' as p;

/// Tracks files modified locally by Isochron so the directory watcher does not
/// treat our own disk writes as remote changes from external collaborators.
class FileSyncTracker {
  static final Map<String, DateTime> _locallyWrittenPaths = {};

  /// Marks [path] as having been written locally at the current time.
  static void markLocallyWritten(String path) {
    _locallyWrittenPaths[p.canonicalize(path)] = DateTime.now();
  }

  /// Checks if [path] was written locally within the last 2.5 seconds.
  /// If so, returns `true` and clears old expired entries.
  static bool isLocallyWritten(String path) {
    final normalized = p.canonicalize(path);
    final timestamp = _locallyWrittenPaths[normalized];
    if (timestamp == null) return false;

    if (DateTime.now().difference(timestamp).inMilliseconds < 2500) {
      return true;
    }

    _locallyWrittenPaths.remove(normalized);
    return false;
  }

  /// Clears tracked paths (useful for test isolation).
  static void clear() {
    _locallyWrittenPaths.clear();
  }
}
