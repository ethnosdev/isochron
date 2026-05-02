import 'dart:math' as math;
import 'dart:typed_data';
import 'package:fftea/fftea.dart'; // The FFT library
import 'dsp_utils.dart';

class MfccExtractor {
  static const int sampleRate = 16000;
  static const double frameDuration = 0.020; // 20ms
  static const double frameStride = 0.010; // 10ms
  static const int numMelFilters = 26;
  static const int numCepstra = 13;
  static const int fftSize = 512; // Nearest power of 2 for 20ms (320 samples)

  /// Takes raw audio samples and returns a sequence of feature vectors.
  /// Result: List of Frames, where each Frame is a List`<`double`>` of size 13.
  static List<List<double>> extract(Float64List audioData,
      {Function(double)? onProgress}) {
    final processedAudio = Float64List.fromList(audioData);
    _applyPreEmphasis(processedAudio);

    final int frameLenSamples = (frameDuration * sampleRate).round(); // 320
    final int strideSamples = (frameStride * sampleRate).round(); // 160

    // Pre-calculate reusable tools
    final window = DspUtils.createHammingWindow(frameLenSamples);
    final fft = FFT(fftSize);

    // Note: fftea's realFft returns size N/2.
    // For 512, we get 256 bins.
    final int spectrumSize = fftSize ~/ 2;

    final melFilters =
        _createMelFilterBank(fftSize, spectrumSize, sampleRate, numMelFilters);

    final List<List<double>> mfccFrames = [];

    // PROGRESS LOGIC: Report roughly every 1% of processing
    // audioData.length is total samples.
    final int reportInterval = (processedAudio.length / 100).ceil();

    // Framing Loop
    for (int i = 0;
        i + frameLenSamples <= processedAudio.length;
        i += strideSamples) {
      if (onProgress != null && (i % reportInterval) < strideSamples) {
        onProgress(i / processedAudio.length);
      }

      // A. Extract Frame & Apply Window
      final frame = Float64List(fftSize); // Zero-padded to 512
      for (int j = 0; j < frameLenSamples; j++) {
        frame[j] = processedAudio[i + j] * window[j];
      }

      // B. Compute FFT (Power Spectrum)
      // realFft returns Float64x2List (List of Complex Numbers)
      final spectrum = fft.realFft(frame);
      final powerSpectrum = Float64List(spectrumSize);

      for (int k = 0; k < spectrumSize; k++) {
        final c = spectrum[k];
        // Magnitude = sqrt(real^2 + imag^2)
        // Float64x2 stores real in 'x' and imag in 'y'
        final mag = math.sqrt(c.x * c.x + c.y * c.y);

        // Power = |X|^2 / N
        powerSpectrum[k] = (mag * mag) / fftSize;
      }

      // C. Apply Mel Filterbank & Log
      // Matrix Multiplication: MelMatrix [26 x 256] * PowerVector [256]
      final logEnergies = Float64List(numMelFilters);

      for (int m = 0; m < numMelFilters; m++) {
        double sum = 0.0;
        final filterWeights = melFilters[m];

        // Only iterate up to the spectrum size (256)
        // The filterWeights are generated to match this size.
        for (int k = 0; k < filterWeights.length; k++) {
          sum += powerSpectrum[k] * filterWeights[k];
        }

        // D. Logarithm (avoid log(0) with a tiny epsilon)
        logEnergies[m] = math.log(sum + 1e-10);
      }

      // E. DCT
      final dctCoeffs = DspUtils.dct(logEnergies);

      // F. Keep first 13
      final features = dctCoeffs.sublist(0, numCepstra);
      mfccFrames.add(features);
    }

    onProgress?.call(1.0);

    return mfccFrames;
  }

  /// Applies a pre-emphasis filter to flatten the signal spectrum.
  /// y[n] = x[n] - alpha * x[n-1]
  static void _applyPreEmphasis(Float64List signal, {double alpha = 0.97}) {
    for (int i = signal.length - 1; i > 0; i--) {
      signal[i] = signal[i] - alpha * signal[i - 1];
    }
  }

  /// Private helper to generate triangular filters
  static List<Float64List> _createMelFilterBank(
      int nFft, int numBins, int rate, int nFilters) {
    // 1. Define limits
    const double lowFreq = 0.0;
    final double highFreq = rate / 2.0;

    // 2. Convert to Mel
    final double lowMel = DspUtils.hzToMel(lowFreq);
    final double highMel = DspUtils.hzToMel(highFreq);

    // 3. Create (nFilters + 2) points linearly spaced in Mel
    final List<double> melPoints = [];
    final step = (highMel - lowMel) / (nFilters + 1);
    for (int i = 0; i < nFilters + 2; i++) {
      melPoints.add(lowMel + i * step);
    }

    // 4. Convert back to Hz and then to FFT Bins
    final bin = melPoints.map((mel) {
      final hz = DspUtils.melToHz(mel);
      // Map Hz to bin index.
      // Formula: floor((nFft + 1) * hz / rate)
      // We clamp it to ensure we don't exceed numBins - 1
      final val = ((nFft + 1) * hz / rate).floor();
      return math.min(val, numBins - 1);
    }).toList();

    // 5. Create Filterbank Matrix [nFilters x numBins]
    final bank = List.generate(nFilters, (_) => Float64List(numBins));

    for (int m = 1; m <= nFilters; m++) {
      final int start = bin[m - 1];
      final int center = bin[m];
      final int end = bin[m + 1];

      for (int k = start; k < center; k++) {
        if (k >= numBins) break;
        bank[m - 1][k] = (k - bin[m - 1]) / (bin[m] - bin[m - 1]);
      }
      for (int k = center; k < end; k++) {
        if (k >= numBins) break;
        bank[m - 1][k] = (bin[m + 1] - k) / (bin[m + 1] - bin[m]);
      }
    }

    return bank;
  }
}
