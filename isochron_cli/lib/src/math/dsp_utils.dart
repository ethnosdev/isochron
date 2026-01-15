import 'dart:math' as math;
import 'dart:typed_data';

class DspUtils {
  /// Converts Frequency (Hz) to Mel Scale.
  /// Formula: 2595 * log10(1 + f/700)
  static double hzToMel(double hz) {
    return 2595 * (math.log(1 + hz / 700) / math.ln10);
  }

  /// Converts Mel Scale to Frequency (Hz).
  /// Formula: 700 * (10^(m/2595) - 1)
  static double melToHz(double mel) {
    return 700 * (math.pow(10, mel / 2595) - 1);
  }

  /// Creates a Hamming Window of size N.
  /// w(n) = 0.54 - 0.46 * cos(2*pi*n / (N-1))
  static Float64List createHammingWindow(int size) {
    final window = Float64List(size);
    for (int i = 0; i < size; i++) {
      window[i] = 0.54 - 0.46 * math.cos((2 * math.pi * i) / (size - 1));
    }
    return window;
  }

  /// Computes Type-II Discrete Cosine Transform (DCT).
  /// Used to decorrelate the Mel-Filterbank energies.
  ///
  /// Note: This is an O(N^2) implementation.
  /// Since N is small (num filters = 26), this is acceptable.
  static Float64List dct(Float64List input) {
    final N = input.length;
    final output = Float64List(N);

    for (int k = 0; k < N; k++) {
      double sum = 0.0;
      for (int n = 0; n < N; n++) {
        sum += input[n] * math.cos((math.pi / N) * (n + 0.5) * k);
      }
      // Orthogonalization scale factor could be applied here,
      // but standard MFCC often skips it or applies it globally.
      output[k] = sum;
    }
    return output;
  }
}
