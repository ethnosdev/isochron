import 'package:flutter_test/flutter_test.dart';
import 'package:isochron_cli/isochron_cli.dart';
import 'package:isochron_flutter/services/user_settings_service.dart';
import 'package:isochron_flutter/ui/app_manager.dart';
import 'package:isochron_flutter/ui/models/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppManager Undo / Redo System', () {
    late AppManager manager;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await UserSettingsService().init();
      manager = AppManager();
      manager.value = manager.value.copyWith(
        audioDuration: const Duration(seconds: 10),
        fragments: [
          Fragment(index: 0, text: 'Verse 1')..setRealTiming(start: 1.0, end: 3.0),
          Fragment(index: 1, text: 'Verse 2')..setRealTiming(start: 3.5, end: 6.0),
        ],
        selectedFragmentIndex: 0,
      );
    });

    test('canUndo and canRedo initial state', () {
      expect(manager.canUndo, isFalse);
      expect(manager.canRedo, isFalse);
    });

    test('undoes and redoes boundary edit', () {
      manager.beginBoundaryEdit();
      manager.updateFragment(0, 1.5, 3.0);

      expect(manager.value.fragments[0].realStart, 1.5);
      expect(manager.canUndo, isTrue);
      expect(manager.canRedo, isFalse);

      manager.undo();
      expect(manager.value.fragments[0].realStart, 1.0);
      expect(manager.canUndo, isFalse);
      expect(manager.canRedo, isTrue);

      manager.redo();
      expect(manager.value.fragments[0].realStart, 1.5);
      expect(manager.canUndo, isTrue);
      expect(manager.canRedo, isFalse);
    });

    test('undoes and redoes inline text edit', () {
      manager.updateFragmentText(0, 'Verse 1 Modified');

      expect(manager.value.fragments[0].text, 'Verse 1 Modified');
      expect(manager.canUndo, isTrue);

      manager.undo();
      expect(manager.value.fragments[0].text, 'Verse 1');

      manager.redo();
      expect(manager.value.fragments[0].text, 'Verse 1 Modified');
    });

    test('undoes and redoes reviewed toggle', () {
      expect(manager.value.fragments[0].status, FragmentStatus.auto);

      manager.toggleFragmentReviewed(0);
      expect(manager.value.fragments[0].status, FragmentStatus.reviewed);
      expect(manager.canUndo, isTrue);

      manager.undo();
      expect(manager.value.fragments[0].status, FragmentStatus.auto);

      manager.redo();
      expect(manager.value.fragments[0].status, FragmentStatus.reviewed);
    });

    test('undoes and redoes clearFragmentTiming', () {
      expect(manager.value.fragments[0].realStart, 1.0);

      manager.clearFragmentTiming(0);
      expect(manager.value.fragments[0].realStart, -1.0);
      expect(manager.canUndo, isTrue);

      manager.undo();
      expect(manager.value.fragments[0].realStart, 1.0);

      manager.redo();
      expect(manager.value.fragments[0].realStart, -1.0);
    });

    test('filter state switching', () {
      expect(manager.value.filter, FragmentFilter.all);

      manager.setFilter(FragmentFilter.unreviewed);
      expect(manager.value.filter, FragmentFilter.unreviewed);

      manager.setFilter(FragmentFilter.flagged);
      expect(manager.value.filter, FragmentFilter.flagged);
    });
  });
}
