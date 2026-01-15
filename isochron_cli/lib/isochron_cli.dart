/// Isochron CLI Library
/// Exports internal components for testing and CLI usage.
library;

// Core
export 'src/core/config.dart';
export 'src/core/fragment.dart';
export 'src/core/text_parser.dart';
export 'src/core/time_projector.dart';

// Math
export 'src/math/dsp_utils.dart';
export 'src/math/mfcc_extractor.dart';
export 'src/math/dtw_aligner.dart';
export 'src/math/vector_utils.dart';

// Audio & Synthesis
export 'src/audio/ffmpeg_processor.dart';
export 'src/synthesis/anchor_generator.dart';
export 'src/audio/wav_utils.dart';
