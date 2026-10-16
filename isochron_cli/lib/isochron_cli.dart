/// Isochron CLI Library
/// Exports internal components for testing and CLI usage.
library;

// Core
export 'src/core/fragment.dart';
export 'src/core/text_parser.dart';
export 'src/core/isochron_processor.dart';
export 'src/core/timing_export.dart';
export 'src/core/romanizer.dart';
export 'package:uroman/uroman.dart';

// Drivers
export 'src/core/drivers.dart';
export 'src/platform/mac_drivers.dart';

// MMS Neural Aligner
export 'src/mms/mms_pipeline.dart';
export 'src/mms/mms_tokenizer.dart';
export 'src/mms/model_manager.dart';
export 'src/mms/boundary_placer.dart';
export 'src/mms/ctc_aligner.dart';
export 'src/mms/onnx_emissions_engine.dart';
export 'src/mms/find_unread.dart';
export 'src/mms/quality_analyzer.dart';

// Audio
export 'src/audio/wav_reader.dart';
export 'src/audio/wav_utils.dart';
export 'src/audio/audio_signal.dart';
export 'src/audio/pause_detector.dart';
export 'src/mms/pause_snapper.dart';

// Evaluation
export 'src/eval/evaluator.dart';
