import 'dart:io';
import 'dart:typed_data';
import 'package:isochron_cli/src/ort/ort_session.dart';

void main() {
  final home = Platform.environment['HOME']!;
  final path = '$home/Library/Application Support/isochron/models/model_int8.onnx';
  final session = OrtSession.fromFile(path);

  // 1 second of 16kHz audio: 16000 float32 samples
  final inputData = Float32List(16000);
  final inputs = {
    'input_values': (shape: [1, 16000], data: inputData),
  };

  final stopwatch = Stopwatch()..start();
  final outputs = session.run(inputs);
  stopwatch.stop();

  final logits = outputs['logits']!;
  stdout.writeln('Inference completed in ${stopwatch.elapsedMilliseconds} ms');
  stdout.writeln('Output shape: ${logits.shape}');
  stdout.writeln('Total elements: ${logits.data.length}');

  session.release();
}
