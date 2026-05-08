import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:isochron_cli/isochron_cli.dart';
import 'package:isochron_flutter/services/export_service.dart';
import 'package:isochron_flutter/ui/models/project_model.dart';

void main() {
  group('ExportService.generateCsv', () {
    test('matches expected CSV format with header', () {
      final entries = <Map<String, dynamic>>[
        {'index': 0, 'id': '40001001', 'start': 2.132, 'end': 10.657},
        {'index': 1, 'id': null, 'start': 10.657, 'end': 11.545},
      ];

      final csv = ExportService.generateCsv(entries, 'recordingA');
      expect(
        csv,
        'id,verse_id,recording_id,start,end\n'
        '0,40001001,recordingA,2.132,10.657\n'
        '1,,recordingA,10.657,11.545\n',
      );
    });

    test('supports headerless append mode', () {
      final entries = <Map<String, dynamic>>[
        {'index': 2, 'id': '40001003', 'start': 11.545, 'end': 12.200},
      ];

      final csv = ExportService.generateCsv(
        entries,
        'rec-2',
        includeHeader: false,
      );

      expect(csv, '2,40001003,rec-2,11.545,12.2\n');
    });

    test('escapes recording IDs containing commas', () {
      final entries = <Map<String, dynamic>>[
        {'index': 1, 'id': 'v1', 'start': 0.0, 'end': 1.0},
      ];

      final csv = ExportService.generateCsv(entries, 'rec,with,comma');
      expect(csv, contains('1,v1,"rec,with,comma",0.0,1.0'));
    });
  });

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
  });

  group('ExportService helpers', () {
    test('builds default filenames', () {
      final phraseName = ExportService.defaultPhraseTimingFilename(
        const TimingExportMetadata(
          languageCode: 'TH',
          bookId: '01',
          bookCode: 'GEN',
          chapterId: '01',
        ),
      );
      expect(phraseName, 'TH-01-GEN-01.txt');
      expect(
        ExportService.defaultCsvFilename('My Project Name'),
        'My_Project_Name_full.csv',
      );
    });

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
      final abs = track.getAbsoluteOutputPath(project.directoryPath);
      await File(abs).create(recursive: true);
      await File(abs).writeAsString(jsonEncode(rows));
    }

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('export_service_test_');

      doneTrack = Track(
        id: 'track_done',
        name: 'Done Track',
        audioPath: '/audio/rec01.wav',
        textPath: '/text/TH-01-GEN-01.txt',
        outputFilename: 'done.json',
        status: AlignmentStatus.done,
      );
      pendingTrack = Track(
        id: 'track_pending',
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

    test('buildCombinedCsv exports done/reviewed tracks only', () async {
      final csv = await ExportService.buildCombinedCsv(project);

      expect(csv, startsWith('id,verse_id,recording_id,start,end\n'));
      expect(csv, contains('0,s1,rec01,2.132,10.657\n'));
      expect(csv, contains('1,1a,rec01,10.657,11.545\n'));
      expect(csv, isNot(contains('p1')));
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

    test(
      'buildCombinedCsv returns empty when no exportable tracks exist',
      () async {
        pendingTrack.status = AlignmentStatus.error;
        doneTrack.status = AlignmentStatus.pending;

        final csv = await ExportService.buildCombinedCsv(project);
        expect(csv, isEmpty);
      },
    );

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
  });
}
