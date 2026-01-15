import 'package:test/test.dart';
import 'package:isochron_cli/isochron_cli.dart';

void main() {
  group('Fragment', () {
    test('should hold text and sequential ID', () {
      // We haven't written the Fragment class yet, but this is how we expect it to work:
      // final frag = Fragment(id: '1', text: 'Hello World');
      // expect(frag.id, '1');
      // expect(frag.text, 'Hello World');
    });

    test('should allow setting calculated timestamps later', () {
      // final frag = Fragment(id: '1', text: 'Hello');
      // frag.realStart = 0.5;
      // expect(frag.realStart, 0.5);
    });
  });
}
