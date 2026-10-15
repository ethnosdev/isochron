import 'package:flutter_test/flutter_test.dart';
import 'package:isochron_cli/isochron_cli.dart';
import 'package:isochron_flutter/services/user_settings_service.dart';
import 'package:isochron_flutter/ui/app_manager.dart';
import 'package:isochron_flutter/ui/models/project_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await UserSettingsService().init();
  });

  group('Listen-and-Nudge and Quality Signals', () {
    test('Project defaults boundaryLeadInMs to 190ms', () {
      final project = Project(
        id: 'p1',
        name: 'Test Project',
        directoryPath: '/tmp/test',
      );
      expect(project.boundaryLeadInMs, 190);
    });

    test('jumpToNextFlaggedVerse navigates to next flagged fragment and wraps', () {
      final appManager = AppManager();
      final frags = [
        Fragment(index: 0, text: 'Verse 1')..setRealTiming(start: 0.0, end: 3.0),
        Fragment(index: 1, text: 'Verse 2', flags: ['not_at_pause'])..setRealTiming(start: 3.0, end: 6.0),
        Fragment(index: 2, text: 'Verse 3')..setRealTiming(start: 6.0, end: 9.0),
        Fragment(index: 3, text: 'Verse 4', flags: ['poor_text_match'])..setRealTiming(start: 9.0, end: 12.0),
      ];

      appManager.value = appManager.value.copyWith(
        fragments: frags,
        selectedFragmentIndex: 0,
      );

      // From index 0, jump should land on index 1
      appManager.jumpToNextFlaggedVerse();
      expect(appManager.value.selectedFragmentIndex, 1);

      // From index 1, jump should land on index 3
      appManager.jumpToNextFlaggedVerse();
      expect(appManager.value.selectedFragmentIndex, 3);

      // From index 3, jump should wrap around to index 1
      appManager.jumpToNextFlaggedVerse();
      expect(appManager.value.selectedFragmentIndex, 1);
    });

    test('markReviewedAndAdvance marks status reviewed and selects next verse', () {
      final appManager = AppManager();
      final frags = [
        Fragment(index: 0, text: 'Verse 1', status: FragmentStatus.auto)
          ..setRealTiming(start: 0.0, end: 3.0),
        Fragment(index: 1, text: 'Verse 2', status: FragmentStatus.auto)
          ..setRealTiming(start: 3.0, end: 6.0),
      ];

      appManager.value = appManager.value.copyWith(
        fragments: frags,
        selectedFragmentIndex: 0,
      );

      appManager.markReviewedAndAdvance();

      expect(appManager.value.fragments[0].status, FragmentStatus.reviewed);
      expect(appManager.value.selectedFragmentIndex, 1);
    });
  });
}
