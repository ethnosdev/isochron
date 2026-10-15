import 'dart:io';
import 'package:isochron_cli/src/ort/ort_session.dart';

void main() {
  final home = Platform.environment['HOME']!;
  final path = '$home/Library/Application Support/isochron/models/model_int8.onnx';
  final session = OrtSession.fromFile(path);
  stdout.writeln('Inputs: ${session.inputNames}');
  stdout.writeln('Outputs: ${session.outputNames}');
  session.release();
}
