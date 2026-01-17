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
      final text = await File(args['textPath']).readAsString();

      // Parse optional rules
      Map<String, String>? rules;
      if (args['rulesJson'] != null) {
        final rawMap = jsonDecode(args['rulesJson']) as Map<String, dynamic>;
        rules = rawMap.map((key, value) => MapEntry(key, value.toString()));
      }

      final frags = await IsochronProcessor.process(
        text: text,
        audioPath: args['audioPath'],
        workDir: workDir,
        ffmpegPath: args['ffmpeg'],
        espeakPath: args['espeak'],
        transliterationRules: rules,
        onProgress: (s, p) =>
            sendPort.send({'type': 'progress', 'status': s, 'value': p}),
      );

      sendPort.send({'type': 'result', 'data': frags});
    } catch (e) {
      sendPort.send({'type': 'error', 'error': e.toString()});
    } finally {
      if (workDir.existsSync()) workDir.deleteSync(recursive: true);
    }
  }
}
