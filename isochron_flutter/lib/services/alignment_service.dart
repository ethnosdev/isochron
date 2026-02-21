import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:isochron_cli/isochron_cli.dart';

class AlignmentService {
  Future<List<Fragment>> runIsochron({
    required String textPath,
    required String audioPath,
    required String ffmpegPath,
    required String espeakPath,
    String? dictPath,
    bool hasIds = false,
    bool generateIds = false,
    String? generatedIdPrefix,
    int recordingNumber = 1,
    required Function(String status, double progress) onProgress,
  }) async {
    final receivePort = ReceivePort();
    String? rulesJson;

    if (dictPath != null) {
      rulesJson = await File(dictPath).readAsString();
    }

    try {
      await Isolate.spawn(_isolateEntry, {
        'sendPort': receivePort.sendPort,
        'textPath': textPath,
        'audioPath': audioPath,
        'rulesJson': rulesJson,
        'ffmpeg': ffmpegPath,
        'espeak': espeakPath,
        'hasIds': hasIds,
        'generateIds': generateIds,
        'generatedIdPrefix': generatedIdPrefix,
        'recordingNumber': recordingNumber,
      });

      await for (final message in receivePort) {
        if (message['type'] == 'progress') {
          onProgress(message['status'], message['value']);
        } else if (message['type'] == 'result') {
          receivePort.close();
          return message['data'] as List<Fragment>;
        } else if (message['type'] == 'error') {
          throw message['error'];
        }
      }
    } catch (e) {
      receivePort.close();
      rethrow;
    }
    return [];
  }

  static Future<void> _isolateEntry(Map<String, dynamic> args) async {
    final SendPort sendPort = args['sendPort'];
    final workDir = Directory.systemTemp.createTempSync('iso_bg_');

    try {
      Map<String, String>? rules;
      if (args['rulesJson'] != null) {
        final rawMap = jsonDecode(args['rulesJson']) as Map<String, dynamic>;
        rules = rawMap.map((key, value) => MapEntry(key, value.toString()));
      }

      final hasIds = args['hasIds'] as bool? ?? false;
      final generateIds = args['generateIds'] as bool? ?? false;
      final generatedIdPrefix = args['generatedIdPrefix'] as String?;
      final recordingNumber = args['recordingNumber'] as int? ?? 1;

      final File textFile = File(args['textPath']);
      final lines = await textFile.readAsLines();

      String cleanTextForEngine = "";
      List<String> extractedIds = [];

      if (hasIds) {
        final buffer = StringBuffer();
        for (var line in lines) {
          if (line.trim().isEmpty) continue;
          final parts = line.trim().split(' ');
          if (parts.length > 1) {
            extractedIds.add(parts.first);
            buffer.writeln(parts.sublist(1).join(' '));
          } else {
            extractedIds.add("");
            buffer.writeln(line);
          }
        }
        cleanTextForEngine = buffer.toString();
      } else {
        cleanTextForEngine = await textFile.readAsString();
      }

      // 1. Run Alignment on CLEAN text
      final List<Fragment> rawFragments = await IsochronProcessor.process(
        text: cleanTextForEngine,
        audioPath: args['audioPath'],
        workDir: workDir,
        ffmpegPath: args['ffmpeg'],
        espeakPath: args['espeak'],
        transliterationRules: rules,
        onProgress: (s, p) =>
            sendPort.send({'type': 'progress', 'status': s, 'value': p}),
      );

      // 2. Merge IDs back (if applicable)
      List<Fragment> finalFragments = rawFragments;

      if (hasIds && extractedIds.isNotEmpty) {
        finalFragments = [];
        for (int i = 0; i < rawFragments.length; i++) {
          String? id;
          if (i < extractedIds.length) {
            id = extractedIds[i];
          }
          finalFragments.add(rawFragments[i].copyWith(id: id));
        }
      } else if (generateIds && generatedIdPrefix != null) {
        // AUTO-GENERATE IDs: {Prefix}{RecordingNumber:000}{VerseNumber:000}
        finalFragments = [];
        final recStr = recordingNumber.toString().padLeft(3, '0');

        for (int i = 0; i < rawFragments.length; i++) {
          final verseStr = (i + 1).toString().padLeft(3, '0');
          final generatedId = '$generatedIdPrefix$recStr$verseStr';

          finalFragments.add(rawFragments[i].copyWith(id: generatedId));
        }
      }

      sendPort.send({'type': 'result', 'data': finalFragments});
    } catch (e) {
      sendPort.send({'type': 'error', 'error': e.toString()});
    } finally {
      if (workDir.existsSync()) workDir.deleteSync(recursive: true);
    }
  }
}
