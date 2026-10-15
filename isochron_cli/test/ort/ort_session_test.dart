import 'package:isochron_cli/src/ort/ort_session.dart';
import 'package:test/test.dart';

void main() {
  group('ONNX Runtime FFI', () {
    test('loads dylib and initializes OrtEnvironment', () {
      final env = OrtEnvironment.instance();
      expect(env, isNotNull);
      expect(env.api.address, isNonZero);
      expect(env.envPtr.address, isNonZero);
      expect(env.cpuMemoryInfo.address, isNonZero);

      env.release();
    });
  });
}
