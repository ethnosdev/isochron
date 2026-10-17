import 'package:flutter_test/flutter_test.dart';
import 'package:isochron_flutter/utils/natural_sort.dart';

void main() {
  group('Natural Sort Utility', () {
    test('sorts mixed alphanumeric strings numerically in-place', () {
      final input = ['Track 10.mp3', 'Track 2.mp3', 'Track 1.mp3', 'Track 20.mp3'];
      naturalSort(input);
      expect(input, ['Track 1.mp3', 'Track 2.mp3', 'Track 10.mp3', 'Track 20.mp3']);
    });

    test('handles leading zeros and case insensitivity', () {
      final input = ['chapter_10', 'chapter_02', 'Chapter_1'];
      naturalSort(input);
      expect(input, ['Chapter_1', 'chapter_02', 'chapter_10']);
    });
  });
}
