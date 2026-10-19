import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:isochron_cli/src/core/fragment.dart';
import 'package:isochron_cli/src/mms/constrained_aligner.dart';
import 'package:isochron_cli/src/mms/mms_pipeline.dart';
import 'package:isochron_cli/src/mms/mms_tokenizer.dart';
import 'package:isochron_cli/src/mms/onnx_emissions_engine.dart';

void main() {
  group('ConstrainedAligner (Keep My Edits)', () {
    test('preserves user edited boundaries as strict hard constraints', () {
      final tokenizer = MmsTokenizer();
      final aligner = ConstrainedAligner(tokenizer: tokenizer);

      final frags = [
        Fragment(
          index: 0,
          text: 'First verse',
          status: FragmentStatus.auto,
        )..setRealTiming(start: 0.0, end: 3.0),
        Fragment(
          index: 1,
          text: 'Second verse edited by user',
          status: FragmentStatus.edited,
        )..setRealTiming(start: 4.5, end: 7.0),
        Fragment(
          index: 2,
          text: 'Third verse',
          status: FragmentStatus.auto,
        )..setRealTiming(start: 7.0, end: 10.0),
      ];

      // 500 frames * 32 = 16000 values (~10 seconds at 20ms/frame)
      final dummyData = Float32List(500 * 32);
      for (int i = 0; i < dummyData.length; i++) {
        dummyData[i] = -10.0;
      }
      // Blank (silence) default across all frames
      for (int t = 0; t < 500; t++) {
        dummyData[t * 32 + 0] = 0.0;
      }
      // Populate speech token emissions for 'First verse' in early frames of span 0
      final tokenOutput = tokenizer.tokenizeVerses(['First verse']);
      for (int i = 0; i < tokenOutput.tokenIds.length; i++) {
        final id = tokenOutput.tokenIds[i];
        final frame = i + 2;
        if (frame < 500) {
          dummyData[frame * 32 + 0] = -5.0; // low blank during speech
          dummyData[frame * 32 + id] = 0.0;  // strong token emission
        }
      }
      final emissions = EmissionsOutput(data: dummyData, totalFrames: 500);

      final result = aligner.alignConstrained(
        fragments: frags,
        emissions: emissions,
        pauses: [],
        trackDurationSeconds: 10.0,
        options: const MmsPipelineOptions(keepEdits: true),
      );

      expect(result.length, 3);
      // Verse 0 end must meet Verse 1 start
      expect(result[0].start, 0.0);
      expect(result[0].end, 4.5);

      // Verse 1 start must be locked to 4.5s
      expect(result[1].start, 4.5);

      // Verse 2 must end at track end (10.0s)
      expect(result[2].end, 10.0);
    });
  });
}
