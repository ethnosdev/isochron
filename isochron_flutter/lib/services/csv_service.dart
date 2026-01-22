import 'package:isochron_cli/isochron_cli.dart';

class CsvService {
  /// Generates a CSV string from a list of fragments.
  /// Header: id,verse_id,recording_id,start,end
  static String generateCsv(List<Fragment> fragments, String recordingId) {
    final buffer = StringBuffer();
    // Header
    buffer.writeln('id,verse_id,recording_id,start,end');

    for (final f in fragments) {
      // Columns
      // 1. id (Internal Index)
      buffer.write('${f.index},');

      // 2. verse_id (The text ID, e.g. "40001001", or empty if null)
      buffer.write('${f.id ?? ""},');

      // 3. recording_id (User supplied)
      // Escape commas just in case, though unlikely in IDs
      buffer.write('${_escape(recordingId)},');

      // 4. start (3 decimal places)
      buffer.write('${f.realStart.toStringAsFixed(3)},');

      // 5. end (3 decimal places)
      buffer.write(f.realEnd.toStringAsFixed(3));

      buffer.writeln(); // New line
    }

    return buffer.toString();
  }

  static String _escape(String input) {
    if (input.contains(',')) {
      return '"$input"';
    }
    return input;
  }
}
