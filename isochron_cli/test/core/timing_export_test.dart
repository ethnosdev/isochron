import 'package:isochron_cli/isochron_cli.dart';
import 'package:test/test.dart';

void main() {
  group('TimingExport metadata parsing', () {
    test('parses primary dash format', () {
      final metadata = TimingExport.parseMetadataFromSourceFilename(
        '/tmp/TH-01-GEN-01.txt',
      );
      expect(metadata.languageCode, 'TH');
      expect(metadata.bookId, '01');
      expect(metadata.bookCode, 'GEN');
      expect(metadata.chapterId, '01');
    });

    test('parses underscore format with trailing suffix', () {
      final metadata = TimingExport.parseMetadataFromSourceFilename(
        '/tmp/grctr_071_MRK_01_read.txt',
      );
      expect(metadata.languageCode, 'grctr');
      expect(metadata.bookId, '071');
      expect(metadata.bookCode, 'MRK');
      expect(metadata.chapterId, '01');
    });

    test('falls back on invalid source name', () {
      final metadata = TimingExport.parseMetadataFromSourceFilename(
        '/tmp/BADNAME.txt',
      );
      expect(metadata.languageCode, TimingExportMetadata.fallback.languageCode);
      expect(metadata.bookId, TimingExportMetadata.fallback.bookId);
      expect(metadata.bookCode, TimingExportMetadata.fallback.bookCode);
      expect(metadata.chapterId, TimingExportMetadata.fallback.chapterId);
    });
  });

  group('TimingExport payload generation', () {
    test('uses tab-separated timing rows', () {
      final fragments = [
        Fragment(index: 0, id: 's1', text: 'line one')
          ..setRealTiming(start: 2.132, end: 10.657),
        Fragment(index: 1, id: '1a', text: 'line two')
          ..setRealTiming(start: 10.657, end: 11.545),
      ];
      final payload = TimingExport.generateTimingPayload(
        fragments,
        const TimingExportMetadata(
          languageCode: 'TH',
          bookId: '01',
          bookCode: 'GEN',
          chapterId: '01',
        ),
      );

      expect(
        payload,
        '\\id GEN\n'
        '\\c 01\n'
        '\\level phrase\n'
        '2.132\t10.657\ts1\n'
        '10.657\t11.545\t1a\n',
      );
    });

    test('falls back to numeric IDs without s prefix', () {
      final fragments = [
        Fragment(index: 0, text: 'line one')
          ..setRealTiming(start: 1.0, end: 2.0),
        Fragment(index: 1, id: '', text: 'line two')
          ..setRealTiming(start: 2.0, end: 3.0),
      ];
      final payload = TimingExport.generateTimingPayload(
        fragments,
        TimingExportMetadata.fallback,
      );

      expect(payload, contains('\n1\t2\t1\n'));
      expect(payload, contains('\n2\t3\t2\n'));
    });
  });

  group('TimingExport output naming and format resolution', () {
    test('default json filename is derived from source text filename', () {
      final name = TimingExport.defaultJsonFilenameFromSourcePath(
        '/tmp/TH-01-GEN-01.txt',
      );
      expect(name, 'TH-01-GEN-01.json');
    });

    test('default json filename falls back when source is missing', () {
      final name = TimingExport.defaultJsonFilenameFromSourcePath(null);
      expect(name, 'alignment.json');
    });

    test('default timing filename uses detected underscore separator', () {
      final name = TimingExport.defaultTimingFilenameFromSourcePath(
        '/tmp/grctr_071_MRK_01_read.txt',
      );
      expect(name, 'grctr_071_MRK_01_read_timing.txt');
    });

    test('default timing filename normalizes spaces to dash', () {
      final name = TimingExport.defaultTimingFilenameFromSourcePath(
        '/tmp/grctr 071 MRK 01 read.txt',
      );
      expect(name, 'grctr 071 MRK 01 read-timing.txt');
    });

    test('resolveOutputFormat respects explicit format first', () {
      final fmt = TimingExport.resolveOutputFormat(
        outputPath: 'alignment.json',
        requestedFormat: 'timing',
      );
      expect(fmt, CliOutputFormat.timing);
    });

    test('resolveOutputFormat keeps explicit json even with .txt output', () {
      final fmt = TimingExport.resolveOutputFormat(
        outputPath: 'alignment.txt',
        requestedFormat: 'json',
      );
      expect(fmt, CliOutputFormat.json);
    });

    test('resolveOutputFormat infers from extension when not explicit', () {
      expect(
        TimingExport.resolveOutputFormat(outputPath: 'a.json'),
        CliOutputFormat.json,
      );
      expect(
        TimingExport.resolveOutputFormat(outputPath: 'a.txt'),
        CliOutputFormat.timing,
      );
    });

    test('resolveOutputFormat falls back to json for unknown extension', () {
      final fmt = TimingExport.resolveOutputFormat(outputPath: 'a.out');
      expect(fmt, CliOutputFormat.json);
    });

    test('normalizeOutputPathForFormat changes extension to match json', () {
      final path = TimingExport.normalizeOutputPathForFormat(
        outputPath: 'alignment.txt',
        format: CliOutputFormat.json,
      );
      expect(path, 'alignment.json');
    });

    test('normalizeOutputPathForFormat changes extension to match timing', () {
      final path = TimingExport.normalizeOutputPathForFormat(
        outputPath: 'alignment.json',
        format: CliOutputFormat.timing,
      );
      expect(path, 'alignment.txt');
    });

    test('normalizeOutputPathForFormat keeps matching extension unchanged', () {
      final path = TimingExport.normalizeOutputPathForFormat(
        outputPath: 'alignment.txt',
        format: CliOutputFormat.timing,
      );
      expect(path, 'alignment.txt');
    });

    test('resolveEffectiveOutput centralizes format/path derivation', () {
      final resolved = TimingExport.resolveEffectiveOutput(
        explicitOutputPath: null,
        requestedFormat: 'timing',
        sourceTextPath: '/tmp/TH-01-GEN-01.txt',
      );
      expect(resolved.format, CliOutputFormat.timing);
      expect(resolved.outputPath, 'TH-01-GEN-01-timing.txt');
    });

    test('resolveEffectiveOutput normalizes mismatched explicit extension', () {
      final resolved = TimingExport.resolveEffectiveOutput(
        explicitOutputPath: 'alignment.txt',
        requestedFormat: 'json',
        sourceTextPath: '/tmp/TH-01-GEN-01.txt',
      );
      expect(resolved.format, CliOutputFormat.json);
      expect(resolved.outputPath, 'alignment.json');
    });
  });
}
