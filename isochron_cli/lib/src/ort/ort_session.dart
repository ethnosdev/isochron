import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;
import 'ort_bindings.dart' as raw;

class OrtException implements Exception {
  final String message;
  final int? code;
  OrtException(this.message, [this.code]);

  @override
  String toString() => 'OrtException: $message${code != null ? ' (code $code)' : ''}';
}

/// Helper to load libonnxruntime.dylib from standard and fallback locations.
ffi.DynamicLibrary loadOrtLibrary({String? customPath}) {
  if (customPath != null && File(customPath).existsSync()) {
    return ffi.DynamicLibrary.open(customPath);
  }

  final envPath = Platform.environment['ORT_DYLIB_PATH'];
  if (envPath != null && File(envPath).existsSync()) {
    return ffi.DynamicLibrary.open(envPath);
  }

  // 1. Script-relative native/lib directory
  final scriptDir = p.dirname(Platform.script.toFilePath());
  final candidates = [
    p.normalize(p.join(scriptDir, '..', 'native', 'lib', 'libonnxruntime.dylib')),
    p.normalize(p.join(scriptDir, 'native', 'lib', 'libonnxruntime.dylib')),
    p.join(Directory.current.path, 'native', 'lib', 'libonnxruntime.dylib'),
    p.join(Directory.current.path, 'isochron_cli', 'native', 'lib', 'libonnxruntime.dylib'),
    p.join(
      Platform.environment['HOME'] ?? '',
      'Library',
      'Application Support',
      'isochron',
      'lib',
      'libonnxruntime.dylib',
    ),
    // App bundle Frameworks (macOS app)
    p.normalize(p.join(Platform.resolvedExecutable, '..', '..', 'Frameworks', 'libonnxruntime.dylib')),
  ];

  for (final path in candidates) {
    if (File(path).existsSync()) {
      return ffi.DynamicLibrary.open(path);
    }
  }

  // System dynamic linker fallback
  try {
    return ffi.DynamicLibrary.open('libonnxruntime.dylib');
  } catch (_) {
    throw OrtException(
      'Could not find libonnxruntime.dylib.\nChecked paths:\n${candidates.join('\n')}\n'
      'Run `dart run tool/fetch_onnxruntime.dart` or set ORT_DYLIB_PATH.',
    );
  }
}

/// Managed singleton OrtEnvironment wrapping OrtApi.
class OrtEnvironment {
  static OrtEnvironment? _instance;
  final raw.OrtNativeBindings bindings;
  final ffi.Pointer<raw.OrtApi> api;
  final ffi.Pointer<raw.OrtEnv> envPtr;
  final ffi.Pointer<raw.OrtMemoryInfo> cpuMemoryInfo;

  OrtEnvironment._({
    required this.bindings,
    required this.api,
    required this.envPtr,
    required this.cpuMemoryInfo,
  });

  static OrtEnvironment instance({String? customDylibPath, String logId = 'isochron'}) {
    if (_instance != null) return _instance!;

    final dylib = loadOrtLibrary(customPath: customDylibPath);
    final bindings = raw.OrtNativeBindings(dylib);

    final apiBase = bindings.OrtGetApiBase();
    if (apiBase == ffi.nullptr) {
      throw OrtException('Failed to get OrtApiBase');
    }

    const ortApiVersion = 31;
    final getApiFn = apiBase.ref.GetApi
        .asFunction<ffi.Pointer<raw.OrtApi> Function(int)>();
    final api = getApiFn(ortApiVersion);
    if (api == ffi.nullptr) {
      throw OrtException('Failed to get OrtApi version $ortApiVersion');
    }

    // Create OrtEnv
    final envPtrPtr = calloc<ffi.Pointer<raw.OrtEnv>>();
    final logIdPtr = logId.toNativeUtf8();
    try {
      final createEnvFn = api.ref.CreateEnv
          .asFunction<ffi.Pointer<raw.OrtStatus> Function(int, ffi.Pointer<ffi.Char>, ffi.Pointer<ffi.Pointer<raw.OrtEnv>>)>();
      _checkStatus(
        api,
        createEnvFn(
          raw.OrtLoggingLevel.ORT_LOGGING_LEVEL_WARNING.value,
          logIdPtr.cast(),
          envPtrPtr,
        ),
      );
    } finally {
      calloc.free(logIdPtr);
    }
    final env = envPtrPtr.value;
    calloc.free(envPtrPtr);

    // Create CPU memory info
    final memInfoPtrPtr = calloc<ffi.Pointer<raw.OrtMemoryInfo>>();
    final createMemInfoFn = api.ref.CreateCpuMemoryInfo
        .asFunction<ffi.Pointer<raw.OrtStatus> Function(int, int, ffi.Pointer<ffi.Pointer<raw.OrtMemoryInfo>>)>();
    _checkStatus(
      api,
      createMemInfoFn(
        raw.OrtAllocatorType.OrtArenaAllocator.value,
        raw.OrtMemType.OrtMemTypeDefault.value,
        memInfoPtrPtr,
      ),
    );
    final memInfo = memInfoPtrPtr.value;
    calloc.free(memInfoPtrPtr);

    _instance = OrtEnvironment._(
      bindings: bindings,
      api: api,
      envPtr: env,
      cpuMemoryInfo: memInfo,
    );
    return _instance!;
  }

  static void _checkStatus(ffi.Pointer<raw.OrtApi> api, ffi.Pointer<raw.OrtStatus> status) {
    if (status == ffi.nullptr) return;

    final getMsgFn = api.ref.GetErrorMessage
        .asFunction<ffi.Pointer<ffi.Char> Function(ffi.Pointer<raw.OrtStatus>)>();
    final getCodeFn = api.ref.GetErrorCode
        .asFunction<int Function(ffi.Pointer<raw.OrtStatus>)>();
    final releaseStatusFn = api.ref.ReleaseStatus
        .asFunction<void Function(ffi.Pointer<raw.OrtStatus>)>();

    final msgPtr = getMsgFn(status);
    final msg = msgPtr.cast<Utf8>().toDartString();
    final code = getCodeFn(status);
    releaseStatusFn(status);

    throw OrtException(msg, code);
  }

  void release() {
    if (_instance == null) return;
    final releaseMemInfoFn = api.ref.ReleaseMemoryInfo
        .asFunction<void Function(ffi.Pointer<raw.OrtMemoryInfo>)>();
    releaseMemInfoFn(cpuMemoryInfo);

    final releaseEnvFn = api.ref.ReleaseEnv
        .asFunction<void Function(ffi.Pointer<raw.OrtEnv>)>();
    releaseEnvFn(envPtr);
    _instance = null;
  }
}

/// An active inference session loaded from an ONNX model file.
class OrtSession {
  final OrtEnvironment env;
  final ffi.Pointer<raw.OrtSession> _sessionPtr;
  final ffi.Pointer<raw.OrtSessionOptions> _optionsPtr;
  final List<String> inputNames;
  final List<String> outputNames;

  OrtSession._({
    required this.env,
    required this._sessionPtr,
    required this._optionsPtr,
    required this.inputNames,
    required this.outputNames,
  });

  factory OrtSession.fromFile(
    String modelPath, {
    OrtEnvironment? env,
    int? intraOpThreads,
  }) {
    final e = env ?? OrtEnvironment.instance();
    final api = e.api;

    // Create session options
    final optPtrPtr = calloc<ffi.Pointer<raw.OrtSessionOptions>>();
    final createOptFn = api.ref.CreateSessionOptions
        .asFunction<ffi.Pointer<raw.OrtStatus> Function(ffi.Pointer<ffi.Pointer<raw.OrtSessionOptions>>)>();
    OrtEnvironment._checkStatus(api, createOptFn(optPtrPtr));
    final optPtr = optPtrPtr.value;
    calloc.free(optPtrPtr);

    // Threads
    final threads = intraOpThreads ?? Platform.numberOfProcessors;
    final setThreadsFn = api.ref.SetIntraOpNumThreads
        .asFunction<ffi.Pointer<raw.OrtStatus> Function(ffi.Pointer<raw.OrtSessionOptions>, int)>();
    OrtEnvironment._checkStatus(api, setThreadsFn(optPtr, threads));

    // Graph optimization
    final setOptLevelFn = api.ref.SetSessionGraphOptimizationLevel
        .asFunction<ffi.Pointer<raw.OrtStatus> Function(ffi.Pointer<raw.OrtSessionOptions>, int)>();
    OrtEnvironment._checkStatus(
      api,
      setOptLevelFn(optPtr, raw.GraphOptimizationLevel.ORT_ENABLE_ALL.value),
    );

    // Create session
    final sessPtrPtr = calloc<ffi.Pointer<raw.OrtSession>>();
    final pathPtr = modelPath.toNativeUtf8();
    try {
      final createSessFn = api.ref.CreateSession
          .asFunction<ffi.Pointer<raw.OrtStatus> Function(ffi.Pointer<raw.OrtEnv>, ffi.Pointer<ffi.Char>, ffi.Pointer<raw.OrtSessionOptions>, ffi.Pointer<ffi.Pointer<raw.OrtSession>>)>();
      OrtEnvironment._checkStatus(
        api,
        createSessFn(e.envPtr, pathPtr.cast(), optPtr, sessPtrPtr),
      );
    } finally {
      calloc.free(pathPtr);
    }
    final sessPtr = sessPtrPtr.value;
    calloc.free(sessPtrPtr);

    // Query input & output names
    final allocatorPtrPtr = calloc<ffi.Pointer<raw.OrtAllocator>>();
    final getDefAllocFn = api.ref.GetAllocatorWithDefaultOptions
        .asFunction<ffi.Pointer<raw.OrtStatus> Function(ffi.Pointer<ffi.Pointer<raw.OrtAllocator>>)>();
    OrtEnvironment._checkStatus(api, getDefAllocFn(allocatorPtrPtr));
    final allocator = allocatorPtrPtr.value;
    calloc.free(allocatorPtrPtr);

    // Inputs
    final inCountPtr = calloc<ffi.Size>();
    final getInCountFn = api.ref.SessionGetInputCount
        .asFunction<ffi.Pointer<raw.OrtStatus> Function(ffi.Pointer<raw.OrtSession>, ffi.Pointer<ffi.Size>)>();
    OrtEnvironment._checkStatus(api, getInCountFn(sessPtr, inCountPtr));
    final inCount = inCountPtr.value;
    calloc.free(inCountPtr);

    final inputNames = <String>[];
    final getInNameFn = api.ref.SessionGetInputName
        .asFunction<ffi.Pointer<raw.OrtStatus> Function(ffi.Pointer<raw.OrtSession>, int, ffi.Pointer<raw.OrtAllocator>, ffi.Pointer<ffi.Pointer<ffi.Char>>)>();
    for (var i = 0; i < inCount; i++) {
      final namePtrPtr = calloc<ffi.Pointer<ffi.Char>>();
      OrtEnvironment._checkStatus(api, getInNameFn(sessPtr, i, allocator, namePtrPtr));
      inputNames.add(namePtrPtr.value.cast<Utf8>().toDartString());
      allocator.ref.Free.asFunction<void Function(ffi.Pointer<raw.OrtAllocator>, ffi.Pointer<ffi.Void>)>()(
        allocator,
        namePtrPtr.value.cast(),
      );
      calloc.free(namePtrPtr);
    }

    // Outputs
    final outCountPtr = calloc<ffi.Size>();
    final getOutCountFn = api.ref.SessionGetOutputCount
        .asFunction<ffi.Pointer<raw.OrtStatus> Function(ffi.Pointer<raw.OrtSession>, ffi.Pointer<ffi.Size>)>();
    OrtEnvironment._checkStatus(api, getOutCountFn(sessPtr, outCountPtr));
    final outCount = outCountPtr.value;
    calloc.free(outCountPtr);

    final outputNames = <String>[];
    final getOutNameFn = api.ref.SessionGetOutputName
        .asFunction<ffi.Pointer<raw.OrtStatus> Function(ffi.Pointer<raw.OrtSession>, int, ffi.Pointer<raw.OrtAllocator>, ffi.Pointer<ffi.Pointer<ffi.Char>>)>();
    for (var i = 0; i < outCount; i++) {
      final namePtrPtr = calloc<ffi.Pointer<ffi.Char>>();
      OrtEnvironment._checkStatus(api, getOutNameFn(sessPtr, i, allocator, namePtrPtr));
      outputNames.add(namePtrPtr.value.cast<Utf8>().toDartString());
      allocator.ref.Free.asFunction<void Function(ffi.Pointer<raw.OrtAllocator>, ffi.Pointer<ffi.Void>)>()(
        allocator,
        namePtrPtr.value.cast(),
      );
      calloc.free(namePtrPtr);
    }

    return OrtSession._(
      env: e,
      sessionPtr: sessPtr,
      optionsPtr: optPtr,
      inputNames: inputNames,
      outputNames: outputNames,
    );
  }

  /// Runs inference with float32 inputs.
  /// [inputs]: map of input name to (shape: [dim0, dim1, ...], data: Float32List).
  /// Returns map of output name to (shape: `List<int>`, data: Float32List).
  Map<String, ({List<int> shape, Float32List data})> run(
    Map<String, ({List<int> shape, Float32List data})> inputs, {
    List<String>? requestedOutputs,
  }) {
    final api = env.api;
    final outNames = requestedOutputs ?? outputNames;

    final inCount = inputs.length;
    final inNamesPtr = calloc<ffi.Pointer<ffi.Char>>(inCount);
    final inValuesPtr = calloc<ffi.Pointer<raw.OrtValue>>(inCount);

    final allocatedNativeFloats = <ffi.Pointer<ffi.Float>>[];
    final allocatedNativeShapes = <ffi.Pointer<ffi.Int64>>[];

    try {
      var idx = 0;
      for (final entry in inputs.entries) {
        final name = entry.key;
        final shape = entry.value.shape;
        final data = entry.value.data;

        inNamesPtr[idx] = name.toNativeUtf8().cast();

        // Shape array
        final shapePtr = calloc<ffi.Int64>(shape.length);
        for (var s = 0; s < shape.length; s++) {
          shapePtr[s] = shape[s];
        }
        allocatedNativeShapes.add(shapePtr);

        // Data buffer
        final dataPtr = calloc<ffi.Float>(data.length);
        dataPtr.asTypedList(data.length).setAll(0, data);
        allocatedNativeFloats.add(dataPtr);

        // Create OrtValue tensor
        final valPtrPtr = calloc<ffi.Pointer<raw.OrtValue>>();
        final createTensorFn = api.ref.CreateTensorWithDataAsOrtValue
            .asFunction<ffi.Pointer<raw.OrtStatus> Function(
              ffi.Pointer<raw.OrtMemoryInfo>,
              ffi.Pointer<ffi.Void>,
              int,
              ffi.Pointer<ffi.Int64>,
              int,
              int,
              ffi.Pointer<ffi.Pointer<raw.OrtValue>>,
            )>();

        OrtEnvironment._checkStatus(
          api,
          createTensorFn(
            env.cpuMemoryInfo,
            dataPtr.cast(),
            data.lengthInBytes,
            shapePtr,
            shape.length,
            raw.ONNXTensorElementDataType.ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT.value,
            valPtrPtr,
          ),
        );
        inValuesPtr[idx] = valPtrPtr.value;
        calloc.free(valPtrPtr);
        idx++;
      }

      // Outputs setup
      final outCount = outNames.length;
      final outNamesPtr = calloc<ffi.Pointer<ffi.Char>>(outCount);
      final outValuesPtr = calloc<ffi.Pointer<raw.OrtValue>>(outCount);

      for (var i = 0; i < outCount; i++) {
        outNamesPtr[i] = outNames[i].toNativeUtf8().cast();
        outValuesPtr[i] = ffi.nullptr;
      }

      // Run
      final runFn = api.ref.Run
          .asFunction<ffi.Pointer<raw.OrtStatus> Function(
            ffi.Pointer<raw.OrtSession>,
            ffi.Pointer<raw.OrtRunOptions>,
            ffi.Pointer<ffi.Pointer<ffi.Char>>,
            ffi.Pointer<ffi.Pointer<raw.OrtValue>>,
            int,
            ffi.Pointer<ffi.Pointer<ffi.Char>>,
            int,
            ffi.Pointer<ffi.Pointer<raw.OrtValue>>,
          )>();

      OrtEnvironment._checkStatus(
        api,
        runFn(
          _sessionPtr,
          ffi.nullptr,
          inNamesPtr,
          inValuesPtr,
          inCount,
          outNamesPtr,
          outCount,
          outValuesPtr,
        ),
      );

      final results = <String, ({List<int> shape, Float32List data})>{};

      final releaseValFn = api.ref.ReleaseValue
          .asFunction<void Function(ffi.Pointer<raw.OrtValue>)>();
      final getTensorTypeAndShapeFn = api.ref.GetTensorTypeAndShape
          .asFunction<ffi.Pointer<raw.OrtStatus> Function(ffi.Pointer<raw.OrtValue>, ffi.Pointer<ffi.Pointer<raw.OrtTensorTypeAndShapeInfo>>)>();
      final getShapeCountFn = api.ref.GetTensorShapeElementCount
          .asFunction<ffi.Pointer<raw.OrtStatus> Function(ffi.Pointer<raw.OrtTensorTypeAndShapeInfo>, ffi.Pointer<ffi.Size>)>();
      final getDimensionsCountFn = api.ref.GetDimensionsCount
          .asFunction<ffi.Pointer<raw.OrtStatus> Function(ffi.Pointer<raw.OrtTensorTypeAndShapeInfo>, ffi.Pointer<ffi.Size>)>();
      final getDimensionsFn = api.ref.GetDimensions
          .asFunction<ffi.Pointer<raw.OrtStatus> Function(ffi.Pointer<raw.OrtTensorTypeAndShapeInfo>, ffi.Pointer<ffi.Int64>, int)>();
      final getTensorDataFn = api.ref.GetTensorMutableData
          .asFunction<ffi.Pointer<raw.OrtStatus> Function(ffi.Pointer<raw.OrtValue>, ffi.Pointer<ffi.Pointer<ffi.Void>>)>();
      final releaseShapeInfoFn = api.ref.ReleaseTensorTypeAndShapeInfo
          .asFunction<void Function(ffi.Pointer<raw.OrtTensorTypeAndShapeInfo>)>();

      for (var i = 0; i < outCount; i++) {
        final val = outValuesPtr[i];
        if (val == ffi.nullptr) continue;

        final infoPtrPtr = calloc<ffi.Pointer<raw.OrtTensorTypeAndShapeInfo>>();
        OrtEnvironment._checkStatus(api, getTensorTypeAndShapeFn(val, infoPtrPtr));
        final info = infoPtrPtr.value;
        calloc.free(infoPtrPtr);

        final totalElementsPtr = calloc<ffi.Size>();
        OrtEnvironment._checkStatus(api, getShapeCountFn(info, totalElementsPtr));
        final totalElements = totalElementsPtr.value;
        calloc.free(totalElementsPtr);

        final dimCountPtr = calloc<ffi.Size>();
        OrtEnvironment._checkStatus(api, getDimensionsCountFn(info, dimCountPtr));
        final dimCount = dimCountPtr.value;
        calloc.free(dimCountPtr);

        final dimsPtr = calloc<ffi.Int64>(dimCount);
        OrtEnvironment._checkStatus(api, getDimensionsFn(info, dimsPtr, dimCount));
        final shape = <int>[];
        for (var d = 0; d < dimCount; d++) {
          shape.add(dimsPtr[d]);
        }
        calloc.free(dimsPtr);
        releaseShapeInfoFn(info);

        final rawDataPtrPtr = calloc<ffi.Pointer<ffi.Void>>();
        OrtEnvironment._checkStatus(api, getTensorDataFn(val, rawDataPtrPtr));
        final floatDataPtr = rawDataPtrPtr.value.cast<ffi.Float>();
        final copyData = Float32List.fromList(floatDataPtr.asTypedList(totalElements));
        calloc.free(rawDataPtrPtr);

        releaseValFn(val);
        results[outNames[i]] = (shape: shape, data: copyData);
      }

      for (var i = 0; i < outCount; i++) {
        calloc.free(outNamesPtr[i]);
      }
      calloc.free(outNamesPtr);
      calloc.free(outValuesPtr);

      return results;
    } finally {
      final releaseValFn = api.ref.ReleaseValue
          .asFunction<void Function(ffi.Pointer<raw.OrtValue>)>();
      for (var i = 0; i < inCount; i++) {
        calloc.free(inNamesPtr[i]);
        if (inValuesPtr[i] != ffi.nullptr) {
          releaseValFn(inValuesPtr[i]);
        }
      }
      calloc.free(inNamesPtr);
      calloc.free(inValuesPtr);

      for (final ptr in allocatedNativeFloats) {
        calloc.free(ptr);
      }
      for (final ptr in allocatedNativeShapes) {
        calloc.free(ptr);
      }
    }
  }

  void release() {
    final api = env.api;
    final releaseSessionFn = api.ref.ReleaseSession
        .asFunction<void Function(ffi.Pointer<raw.OrtSession>)>();
    releaseSessionFn(_sessionPtr);

    final releaseOptFn = api.ref.ReleaseSessionOptions
        .asFunction<void Function(ffi.Pointer<raw.OrtSessionOptions>)>();
    releaseOptFn(_optionsPtr);
  }
}
