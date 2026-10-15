import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'package:isochron_cli/isochron_cli.dart';

class AlignmentService {
  static AlignmentService? _instance;
  factory AlignmentService() => _instance ??= AlignmentService._();
  AlignmentService._();

  Isolate? _workerIsolate;
  SendPort? _workerSendPort;
  ReceivePort? _workerResponsePort;
  Completer<List<Fragment>>? _activeCompleter;
  void Function(String status, double progress)? _activeOnProgress;

  Future<void> _ensureWorkerStarted() async {
    if (_workerIsolate != null && _workerSendPort != null) return;

    final initPort = ReceivePort();
    _workerIsolate = await Isolate.spawn(_isolateWorkerMain, initPort.sendPort);
    _workerSendPort = await initPort.first as SendPort;
    initPort.close();

    _workerResponsePort = ReceivePort();
    _workerResponsePort!.listen(_handleWorkerMessage);
    _workerSendPort!.send({
      'command': 'init',
      'responsePort': _workerResponsePort!.sendPort,
    });
  }

  void _handleWorkerMessage(dynamic message) {
    if (message is! Map<String, dynamic>) return;
    final type = message['type'] as String?;
    if (type == 'progress') {
      _activeOnProgress?.call(
        message['status'] as String? ?? '',
        (message['value'] as num?)?.toDouble() ?? 0.0,
      );
    } else if (type == 'result') {
      final jsonList = message['data'] as List<dynamic>;
      final fragments = jsonList
          .map((item) => Fragment.fromJson(item as Map<String, dynamic>))
          .toList();
      _activeCompleter?.complete(fragments);
      _activeCompleter = null;
      _activeOnProgress = null;
    } else if (type == 'error') {
      _activeCompleter?.completeError(Exception(message['error']));
      _activeCompleter = null;
      _activeOnProgress = null;
    }
  }

  /// Cancels the running alignment cooperatively, with a hard timeout fallback.
  void cancelCurrentRun() {
    if (_workerSendPort != null) {
      _workerSendPort!.send({'command': 'cancel'});
    }
    Future.delayed(const Duration(seconds: 2), () {
      if (_activeCompleter != null && !_activeCompleter!.isCompleted) {
        _killWorker();
        _activeCompleter?.completeError(Exception('Alignment cancelled'));
        _activeCompleter = null;
        _activeOnProgress = null;
      }
    });
  }

  void _killWorker() {
    _workerIsolate?.kill(priority: Isolate.immediate);
    _workerIsolate = null;
    _workerSendPort = null;
    _workerResponsePort?.close();
    _workerResponsePort = null;
  }

  void shutdown() {
    _workerSendPort?.send({'command': 'shutdown'});
    _killWorker();
  }

  /// Primary alignment entry point using the MMS neural engine.
  Future<List<Fragment>> align({
    required String textPath,
    required String audioPath,
    String? languageCode,
    double leadInSeconds = 0.19,
    double starScore = -2.0,
    StarPlacement starPlacement = StarPlacement.segment,
    String? modelPath,
    ModelVariant modelVariant = ModelVariant.int8,
    bool snapToPauses = true,
    bool keepEdits = false,
    List<Fragment>? existingFragments,
    bool hasIds = false,
    bool generateIds = false,
    String? generatedIdPrefix,
    int recordingNumber = 1,
    required void Function(String status, double progress) onProgress,
  }) async {
    await _ensureWorkerStarted();

    if (_activeCompleter != null && !_activeCompleter!.isCompleted) {
      throw StateError('An alignment task is already in progress.');
    }

    _activeCompleter = Completer<List<Fragment>>();
    _activeOnProgress = onProgress;

    _workerSendPort!.send({
      'command': 'align',
      'responsePort': _workerResponsePort!.sendPort,
      'textPath': textPath,
      'audioPath': audioPath,
      'languageCode': languageCode,
      'leadInSeconds': leadInSeconds,
      'starScore': starScore,
      'starPlacement': starPlacement.name,
      'modelPath': modelPath,
      'modelVariant': modelVariant.name,
      'snapToPauses': snapToPauses,
      'keepEdits': keepEdits,
      'existingFragments': existingFragments?.map((f) => f.toJson()).toList(),
      'hasIds': hasIds,
      'generateIds': generateIds,
      'generatedIdPrefix': generatedIdPrefix,
      'recordingNumber': recordingNumber,
    });

    return _activeCompleter!.future;
  }

  /// Backward-compatible alias for existing call sites.
  Future<List<Fragment>> runIsochron({
    required String textPath,
    required String audioPath,
    String? dictPath,
    String? pinsPath,
    String? languageCode,
    double leadInSeconds = 0.19,
    bool hasIds = false,
    bool generateIds = false,
    String? generatedIdPrefix,
    int recordingNumber = 1,
    required void Function(String status, double progress) onProgress,
    String snapMode = 'onset',
    int snapOffsetMs = 0,
  }) {
    return align(
      textPath: textPath,
      audioPath: audioPath,
      languageCode: languageCode,
      leadInSeconds: leadInSeconds,
      hasIds: hasIds,
      generateIds: generateIds,
      generatedIdPrefix: generatedIdPrefix,
      recordingNumber: recordingNumber,
      onProgress: onProgress,
    );
  }

  static Future<void> _isolateWorkerMain(SendPort mainSendPort) async {
    final commandPort = ReceivePort();
    mainSendPort.send(commandPort.sendPort);

    SendPort? responsePort;
    bool cancelRequested = false;
    MmsPipeline? pipeline;

    await for (final message in commandPort) {
      if (message is! Map<String, dynamic>) continue;
      final command = message['command'] as String?;

      if (command == 'init') {
        responsePort = message['responsePort'] as SendPort?;
      } else if (command == 'cancel') {
        cancelRequested = true;
      } else if (command == 'shutdown') {
        break;
      } else if (command == 'align') {
        responsePort = message['responsePort'] as SendPort? ?? responsePort;
        cancelRequested = false;

        try {
          pipeline ??= MmsPipeline();

          final textPath = message['textPath'] as String;
          final audioPath = message['audioPath'] as String;
          final languageCode = message['languageCode'] as String?;
          final leadInSeconds =
              (message['leadInSeconds'] as num?)?.toDouble() ?? 0.19;
          final starScore =
              (message['starScore'] as num?)?.toDouble() ?? -2.0;
          final starPlacementStr =
              message['starPlacement'] as String? ?? 'segment';
          final starPlacement = starPlacementStr == 'edges'
              ? StarPlacement.edges
              : StarPlacement.segment;
          final modelPath = message['modelPath'] as String?;
          final variantStr = message['modelVariant'] as String? ?? 'int8';
          final modelVariant = ModelVariant.values.firstWhere(
            (v) => v.name == variantStr,
            orElse: () => ModelVariant.int8,
          );
          final snapToPauses = message['snapToPauses'] as bool? ?? true;
          final keepEdits = message['keepEdits'] as bool? ?? false;
          final existingList = message['existingFragments'] as List<dynamic>?;

          final hasIds = message['hasIds'] as bool? ?? false;
          final generateIds = message['generateIds'] as bool? ?? false;
          final generatedIdPrefix = message['generatedIdPrefix'] as String?;
          final recordingNumber = message['recordingNumber'] as int? ?? 1;

          List<Fragment> fragments;
          if (keepEdits && existingList != null && existingList.isNotEmpty) {
            fragments = existingList
                .map((item) => Fragment.fromJson(item as Map<String, dynamic>))
                .toList();
          } else {
            final textFile = File(textPath);
            final rawText = await textFile.readAsString();
            fragments = TextParser.parse(rawText, hasIds: hasIds);
          }

          if (fragments.isEmpty) {
            throw Exception('No text fragments parsed from $textPath');
          }

          final result = await pipeline.process(
            fragments: fragments,
            audioPath: audioPath,
            options: MmsPipelineOptions(
              languageCode: languageCode,
              leadInSeconds: leadInSeconds,
              starScore: starScore,
              starPlacement: starPlacement,
              modelPath: modelPath,
              modelVariant: modelVariant,
              snapToPauses: snapToPauses,
              keepEdits: keepEdits,
            ),
            onProgress: (status, progress) {
              responsePort?.send({
                'type': 'progress',
                'status': status,
                'value': progress,
              });
            },
            isCancelled: () => cancelRequested,
          );

          var outputFragments = result.fragments;

          if (generateIds && generatedIdPrefix != null && !hasIds) {
            final recStr = recordingNumber.toString().padLeft(3, '0');
            final idList = <Fragment>[];
            for (var i = 0; i < outputFragments.length; i++) {
              final verseStr = (i + 1).toString().padLeft(3, '0');
              idList.add(outputFragments[i].copyWith(
                id: '$generatedIdPrefix$recStr$verseStr',
              ));
            }
            outputFragments = idList;
          }

          responsePort?.send({
            'type': 'result',
            'data': outputFragments.map((f) => f.toJson()).toList(),
          });
        } catch (e) {
          responsePort?.send({
            'type': 'error',
            'error': e.toString(),
          });
        }
      }
    }
  }
}
