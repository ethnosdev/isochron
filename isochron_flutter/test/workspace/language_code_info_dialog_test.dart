import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isochron_flutter/ui/workspace/components/language_code_info_dialog.dart';
import 'package:macos_ui/macos_ui.dart';

Widget _buildTestApp(Widget child) {
  return MacosApp(
    home: MacosWindow(
      child: ContentArea(
        builder: (context, _) => child,
      ),
    ),
  );
}

void main() {
  group('LanguageCodeInfoDialog Tests', () {
    testWidgets('renders language support dialog with categories and languages', (tester) async {
      tester.view.physicalSize = const Size(1000, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        _buildTestApp(
          const LanguageCodeInfoDialog(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Language Support in Forced Alignment'), findsOneWidget);
      expect(find.text('Greek Script'), findsOneWidget);
      expect(find.text('Middle Eastern & Perso-Arabic Scripts'), findsOneWidget);
      expect(find.text('Cyrillic Script'), findsOneWidget);
      expect(find.text('European & Turkic Exceptions'), findsOneWidget);
      expect(find.text('South Asian (Schwa / Inherent Vowel Handling)'), findsOneWidget);

      expect(find.text('ell (Modern Greek)'), findsOneWidget);
      expect(find.text('rus (Russian)'), findsOneWidget);
      expect(find.text('ara (Arabic)'), findsOneWidget);
      expect(find.text('san (Sanskrit (preserves final inherent "a"))'), findsOneWidget);
      expect(find.text('deu (German (umlauts / ß expansion))'), findsOneWidget);
      expect(find.text('eng (English (Braille Grade 2 contractions))'), findsOneWidget);

      expect(find.text('View uroman Documentation'), findsOneWidget);
      expect(find.text('Close'), findsOneWidget);
    });
  });
}
