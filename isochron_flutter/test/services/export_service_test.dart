import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:isochron_cli/isochron_cli.dart';
import 'package:isochron_flutter/services/export_service.dart';
import 'package:isochron_flutter/ui/models/project_model.dart';

void main() {
  group('ExportService.parsePhraseMetadataFromTextFilename', () {
    test('parses LANG-BOOKID-BOOK-CHAPTERID format', () {
      final metadata = ExportService.parsePhraseMetadataFromTextFilename(
        '/tmp/TH-01-GEN-01.txt',
      );

      expect(metadata.languageCode, 'TH');
      expect(metadata.bookId, '01');
      expect(metadata.bookCode, 'GEN');
      expect(metadata.chapterId, '01');
    });

    test('supports book codes with dashes', () {
      final metadata = ExportService.parsePhraseMetadataFromTextFilename(
        '/tmp/en-19-1-KINGS-02.txt',
      );

      expect(metadata.languageCode, 'en');
      expect(metadata.bookId, '19');
      expect(metadata.bookCode, '1-KINGS');
      expect(metadata.chapterId, '02');
    });

    test('falls back when parse is not possible', () {
      final metadata = ExportService.parsePhraseMetadataFromTextFilename(
        '/tmp/not-parseable.txt',
      );
      expect(metadata.languageCode, TimingExportMetadata.fallback.languageCode);
      expect(metadata.bookId, TimingExportMetadata.fallback.bookId);
      expect(metadata.bookCode, TimingExportMetadata.fallback.bookCode);
      expect(metadata.chapterId, TimingExportMetadata.fallback.chapterId);
    });

    test('parses underscore variant with trailing suffix', () {
      final metadata = ExportService.parsePhraseMetadataFromTextFilename(
        '/tmp/grctr_071_MRK_01_read.txt',
      );
      expect(metadata.languageCode, 'grctr');
      expect(metadata.bookId, '071');
      expect(metadata.bookCode, 'MRK');
      expect(metadata.chapterId, '01');
    });

    test('parses space-separated variant with trailing suffix', () {
      final metadata = ExportService.parsePhraseMetadataFromTextFilename(
        '/tmp/grctr 071 MRK 01 read.txt',
      );
      expect(metadata.languageCode, 'grctr');
      expect(metadata.bookId, '071');
      expect(metadata.bookCode, 'MRK');
      expect(metadata.chapterId, '01');
    });
  });

  group('ExportService.generatePhraseTiming', () {
    test('emits the exact phrase timing structure', () {
      final entries = <Map<String, dynamic>>[
        {'index': 0, 'id': 's1', 'start': 2.132, 'end': 10.657},
        {'index': 1, 'id': '1a', 'start': 10.657, 'end': 11.545},
      ];
      final metadata = ExportService.parsePhraseMetadataFromTextFilename(
        '/tmp/TH-01-GEN-01.txt',
      );

      final phrase = ExportService.generatePhraseTiming(entries, metadata);
      expect(
        phrase,
        '\\id GEN\n'
        '\\c 01\n'
        '\\level phrase\n'
        '2.132\t10.657\ts1\n'
        '10.657\t11.545\t1a\n',
      );
    });

    test('falls back to <index+1> when id is missing', () {
      final entries = <Map<String, dynamic>>[
        {'index': 0, 'start': 2.1, 'end': 3.4},
        {'index': 1, 'id': '', 'start': 3.4, 'end': 5.6},
      ];

      final phrase = ExportService.generatePhraseTiming(
        entries,
        TimingExportMetadata.fallback,
      );

      expect(phrase, contains('\n2.1\t3.4\t1\n'));
      expect(phrase, contains('\n3.4\t5.6\t2\n'));
    });

    test('throws MissingPhraseIdException when requireIds is true and id is missing', () {
      final entries = <Map<String, dynamic>>[
        {'index': 0, 'id': 's1', 'start': 2.1, 'end': 3.4},
        {'index': 1, 'start': 3.4, 'end': 5.6},
      ];

      expect(
        () => ExportService.generatePhraseTiming(
          entries,
          TimingExportMetadata.fallback,
          requireIds: true,
        ),
        throwsA(isA<MissingPhraseIdException>()),
      );
    });

    test('exports tab-delimited verse-letter fixture phrase IDs exactly', () {
      final entries = <Map<String, dynamic>>[
        {'index': 0, 'id': 's1', 'start': 0.06, 'end': 3.478},
        {'index': 1, 'id': '1a', 'start': 3.478, 'end': 6.005},
        {'index': 2, 'id': '1b', 'start': 6.005, 'end': 8.182},
        {'index': 3, 'id': 'is1', 'start': 8.182, 'end': 10.5},
        {'index': 4, 'id': '4-5a', 'start': 10.5, 'end': 14.23},
      ];
      const metadata = TimingExportMetadata(
        languageCode: 'dz',
        bookId: '56',
        bookCode: 'TIT',
        chapterId: '01',
      );

      final payload = ExportService.generatePhraseTiming(
        entries,
        metadata,
        requireIds: true,
      );

      final expectedLines = [
        '\\id TIT',
        '\\c 01',
        '\\level phrase',
        '0.06\t3.478\ts1',
        '3.478\t6.005\t1a',
        '6.005\t8.182\t1b',
        '8.182\t10.5\tis1',
        '10.5\t14.23\t4-5a',
      ];

      expect(payload.trim().split('\n'), equals(expectedLines));
    });
  });

  group('ExportService helpers', () {
    test('status gating only allows done/reviewed', () {
      expect(
        ExportService.isPhraseExportableStatus(AlignmentStatus.done),
        isTrue,
      );
      expect(
        ExportService.isPhraseExportableStatus(AlignmentStatus.reviewed),
        isTrue,
      );
      expect(
        ExportService.isPhraseExportableStatus(AlignmentStatus.pending),
        isFalse,
      );
      expect(
        ExportService.isPhraseExportableStatus(AlignmentStatus.processing),
        isFalse,
      );
      expect(
        ExportService.isPhraseExportableStatus(AlignmentStatus.error),
        isFalse,
      );
    });

    test('combined phrase export gate requires valid status only', () {
      final doneTrack = Track(
        id: 'done',
        name: 'Done Track',
        outputFilename: 'x.json',
        status: AlignmentStatus.done,
      );
      final pendingTrack = Track(
        id: 'pending',
        name: 'Pending Track',
        outputFilename: 'x.json',
        status: AlignmentStatus.pending,
      );

      expect(ExportService.canExportPhraseTiming(doneTrack), isTrue);
      expect(ExportService.canExportPhraseTiming(pendingTrack), isFalse);
    });

    test('tooltip reflects status-only enablement', () {
      final doneTrack = Track(
        id: 'ok',
        name: 'Done Track',
        outputFilename: 'x.json',
        status: AlignmentStatus.done,
      );
      final pendingTrack = Track(
        id: 'bad_status',
        name: 'Pending Track',
        outputFilename: 'x.json',
        status: AlignmentStatus.pending,
      );

      expect(
        ExportService.phraseExportTooltip(doneTrack),
        'Export phrase timing',
      );
      expect(
        ExportService.phraseExportTooltip(pendingTrack),
        'Export is available only for Done/Reviewed alignments',
      );
    });
  });

  group('ExportService orchestration', () {
    late Directory tempDir;
    late Project project;
    late Collection collection;
    late Track doneTrack;
    late Track pendingTrack;

    Future<void> writeTrackOutput(
      Track track,
      List<Map<String, dynamic>> rows,
    ) async {
      final abs = track.getAbsoluteOutputPath(
        project.directoryPath,
        collection.folderName,
      );
      await File(abs).create(recursive: true);
      await File(abs).writeAsString(jsonEncode(rows));
    }

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('export_service_test_');

      doneTrack = Track(
        id: 'track_done',
        collectionId: 'col_1', // Explicitly set collectionId for mock testing
        name: 'Done Track',
        audioPath: '/audio/rec01.wav',
        textPath: '/text/TH-01-GEN-01.txt',
        outputFilename: 'done.json',
        status: AlignmentStatus.done,
      );
      pendingTrack = Track(
        id: 'track_pending',
        collectionId: 'col_1', // Explicitly set collectionId for mock testing
        name: 'Pending Track',
        audioPath: '/audio/rec01.wav',
        textPath: '/text/BADNAME.txt',
        outputFilename: 'pending.json',
        status: AlignmentStatus.pending,
      );

      collection = Collection(
        id: 'col_1',
        name: 'Main Collection',
        tracks: [doneTrack, pendingTrack],
      );

      project = Project(
        id: 'proj1',
        name: 'My Project',
        directoryPath: tempDir.path,
        collections: [collection],
      );

      await writeTrackOutput(doneTrack, [
        {'index': 0, 'id': 's1', 'start': 2.132, 'end': 10.657},
        {'index': 1, 'id': '1a', 'start': 10.657, 'end': 11.545},
      ]);
      await writeTrackOutput(pendingTrack, [
        {'index': 0, 'id': 'p1', 'start': 0.0, 'end': 1.0},
      ]);
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('buildPhraseTiming returns null for non-exportable status', () async {
      final payload = await ExportService.buildPhraseTiming(
        project,
        pendingTrack,
      );
      expect(payload, isNull);
    });

    test('buildPhraseTiming returns phrase payload for done track', () async {
      final payload = await ExportService.buildPhraseTiming(project, doneTrack);
      expect(payload, isNotNull);
      expect(payload!, startsWith('\\id GEN\n\\c 01\n\\level phrase\n'));
      expect(payload, contains('2.132\t10.657\ts1\n'));
    });

    test(
      'defaultPhraseTimingFilenameForTrack uses parsed filename metadata',
      () {
        final name = ExportService.defaultPhraseTimingFilenameForTrack(
          doneTrack,
        );
        expect(name, 'TH-01-GEN-01-timing.txt');
      },
    );

    test('defaultPhraseTimingFilenameForTrack falls back on parse failure', () {
      final name = ExportService.defaultPhraseTimingFilenameForTrack(
        pendingTrack,
      );
      expect(name, 'BADNAME-timing.txt');
    });

    test('buildPhraseTiming still works for done non-.phrase input', () async {
      doneTrack.textPath = '/text/grctr_071_MRK_01_read.txt';
      doneTrack.status = AlignmentStatus.done;

      final payload = await ExportService.buildPhraseTiming(project, doneTrack);
      expect(payload, isNotNull);
      expect(payload!, startsWith('\\id MRK\n\\c 01\n\\level phrase\n'));
    });

    test('default output naming preserves underscore separator', () {
      final track = Track(
        id: 'track_underscore',
        name: 'Underscore',
        textPath: '/text/grctr_071_MRK_01_read.txt',
        outputFilename: 'u.json',
        status: AlignmentStatus.done,
      );

      final name = ExportService.defaultPhraseTimingFilenameForTrack(track);
      expect(name, 'grctr_071_MRK_01_read_timing.txt');
    });

    test(
      'default output naming forces .txt extension even for .phrase input',
      () {
        final track = Track(
          id: 'track_phrase_ext',
          name: 'Phrase Ext',
          textPath: '/text/TH-01-GEN-01.phrase',
          outputFilename: 'p.json',
          status: AlignmentStatus.done,
        );

        final name = ExportService.defaultPhraseTimingFilenameForTrack(track);
        expect(name, 'TH-01-GEN-01-timing.txt');
      },
    );

    test('default output naming normalizes space separator to dash', () {
      final track = Track(
        id: 'track_space',
        name: 'Space Name',
        textPath: '/text/grctr 071 MRK 01 read.txt',
        outputFilename: 's.json',
        status: AlignmentStatus.done,
      );

      final name = ExportService.defaultPhraseTimingFilenameForTrack(track);
      expect(name, 'grctr 071 MRK 01 read-timing.txt');
    });

    test('buildPhraseTiming with tab-delimited verse-letter IDs exports exact IDs', () async {
      final tabTrack = Track(
        id: 'track_tab',
        collectionId: 'col_1',
        name: 'Tab Track',
        audioPath: '/audio/rec01.wav',
        textPath: '/text/dz-56-TIT-01.txt',
        outputFilename: 'tab.json',
        status: AlignmentStatus.done,
      );
      collection.tracks.add(tabTrack);

      const phraseSource = '''
s1\tlaa nethantogto be go pezi kor.
1a\tkon chhog gi ku dunlu nge
1b\tmi sonpo nge shi song mi tshu lu
is1\tIntroductory section
4-5a\tCombined verse phrase
''';
      final fragments = TextParser.parse(phraseSource, hasIds: true);
      final timingEntries = <Map<String, dynamic>>[];
      for (int i = 0; i < fragments.length; i++) {
        timingEntries.add({
          'index': fragments[i].index,
          'id': fragments[i].id,
          'start': i * 2.0,
          'end': (i + 1) * 2.0,
          'text': fragments[i].text,
        });
      }
      await writeTrackOutput(tabTrack, timingEntries);

      project.defaultHasIds = true;
      final payload = await ExportService.buildPhraseTiming(project, tabTrack);
      expect(payload, isNotNull);

      final lines = payload!.trim().split('\n');
      expect(lines[0], '\\id TIT');
      expect(lines[1], '\\c 01');
      expect(lines[2], '\\level phrase');
      expect(lines[3], contains('\ts1'));
      expect(lines[4], contains('\t1a'));
      expect(lines[5], contains('\t1b'));
      expect(lines[6], contains('\tis1'));
      expect(lines[7], contains('\t4-5a'));
    });

    test('buildPhraseTiming throws MissingPhraseIdException when defaultHasIds is true and ID is missing', () async {
      final missingIdTrack = Track(
        id: 'track_missing_id',
        collectionId: 'col_1',
        name: 'Missing ID Track',
        audioPath: '/audio/rec01.wav',
        textPath: '/text/TH-01-GEN-01.txt',
        outputFilename: 'missing_id.json',
        status: AlignmentStatus.done,
      );
      collection.tracks.add(missingIdTrack);

      await writeTrackOutput(missingIdTrack, [
        {'index': 0, 'id': 's1', 'start': 0.0, 'end': 1.0},
        {'index': 1, 'start': 1.0, 'end': 2.0}, // missing ID
      ]);

      project.defaultHasIds = true;
      expect(
        () => ExportService.buildPhraseTiming(project, missingIdTrack),
        throwsA(isA<MissingPhraseIdException>()),
      );
    });
  });
}
