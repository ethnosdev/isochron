import 'dart:io';
import '../core/fragment.dart';
import '../core/text_parser.dart';
import '../core/drivers.dart';
import '../mms/mms_pipeline.dart';
import '../mms/mms_tokenizer.dart';
import '../mms/model_manager.dart';

class IsochronProcessor {
  static Future<List<Fragment>> process({
    required String text,
    required String audioPath,
    Directory? workDir,
    AudioDriver? audioDriver,
    ProgressCallback? onProgress,
    bool hasIds = false,
    String? languageCode,
    double leadInSeconds = 0.17,
    double starScore = 0.0,
    StarPlacement starPlacement = StarPlacement.segment,
    String? modelPath,
    ModelVariant modelVariant = ModelVariant.int8,
  }) async {
    final fragments = TextParser.parse(text, hasIds: hasIds);
    if (fragments.isEmpty) throw Exception("No text found in file.");

    final pipeline = MmsPipeline();
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
      ),
      onProgress: (stage, progress) => onProgress?.call(stage, progress),
    );
    return result.fragments;
  }
}
