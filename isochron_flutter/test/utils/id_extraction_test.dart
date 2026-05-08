import 'package:flutter_test/flutter_test.dart';
import 'package:isochron_flutter/utils/id_extraction.dart';

void main() {
  group('extractIdFromLine', () {
    test('extracts id with single-space delimiter', () {
      final parsed = extractIdFromLine('40001001 In the beginning');
      expect(parsed.hasId, isTrue);
      expect(parsed.id, '40001001');
      expect(parsed.content, 'In the beginning');
    });

    test('extracts id with tab delimiter', () {
      final parsed = extractIdFromLine('40001001\tIn the beginning');
      expect(parsed.hasId, isTrue);
      expect(parsed.id, '40001001');
      expect(parsed.content, 'In the beginning');
    });

    test('extracts id with mixed whitespace delimiter', () {
      final parsed = extractIdFromLine('40001001 \t  In the beginning');
      expect(parsed.hasId, isTrue);
      expect(parsed.id, '40001001');
      expect(parsed.content, 'In the beginning');
    });

    test('handles leading/trailing whitespace around id and content', () {
      final parsed = extractIdFromLine('   40001001   In the beginning   ');
      expect(parsed.hasId, isTrue);
      expect(parsed.id, '40001001');
      expect(parsed.content, 'In the beginning');
    });

    test('returns no id when line has only one token', () {
      final parsed = extractIdFromLine('InTheBeginning');
      expect(parsed.hasId, isFalse);
      expect(parsed.id, '');
      expect(parsed.content, 'InTheBeginning');
    });
  });
}
