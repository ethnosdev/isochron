import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isochron_cli/isochron_cli.dart';
import 'package:isochron_flutter/ui/settings/model_panel.dart';
import 'package:macos_ui/macos_ui.dart';

void main() {
  testWidgets('ModelPanel renders INT8 details without variant picker dropdown', (tester) async {
    await tester.pumpWidget(
      const MacosApp(
        home: MacosWindow(
          child: SizedBox(
            width: 520,
            height: 360,
            child: ModelPanel(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // Verify Title & Subtitle
    expect(find.text('MMS Acoustic Model'), findsOneWidget);
    expect(
      find.text('Meta MMS-300M Quantized INT8 neural acoustic model (~302 MB) required for multilingual forced alignment.'),
      findsOneWidget,
    );

    // Verify Status & INT8 File Info
    expect(find.text('Status: '), findsOneWidget);
    expect(find.text('File: ${ModelVariant.int8.filename} (~302 MB)'), findsOneWidget);

    // Verify Variant Picker is NOT present
    expect(find.byType(MacosPopupButton<ModelVariant>), findsNothing);
    expect(find.text('Model Variant:  '), findsNothing);
    expect(find.text('FP16 (605 MB)'), findsNothing);
    expect(find.text('FP32 Full Precision (1.2 GB)'), findsNothing);

    // Verify Action buttons
    expect(find.text('Reveal in Finder'), findsOneWidget);
    expect(find.text('Close'), findsOneWidget);
  });
}
