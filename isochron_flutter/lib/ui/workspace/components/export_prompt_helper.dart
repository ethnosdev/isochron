import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/widgets.dart';
import 'package:isochron_flutter/ui/theme/app_icons.dart';
import 'package:isochron_flutter/services/export_service.dart';
import 'package:isochron_flutter/ui/components/macos_dialogs.dart';
import 'package:isochron_flutter/ui/models/project_model.dart';
import 'package:isochron_flutter/ui/theme/app_theme.dart';
import 'package:macos_ui/macos_ui.dart';

typedef DirectoryPickerFn = Future<String?> Function({
  String? dialogTitle,
  String? initialDirectory,
});

typedef FileSaverFn = Future<Uri?> Function({
  required String fileName,
  required Uint8List bytes,
  String? dialogTitle,
  String? initialDirectory,
});

String formatUnalignedIssuesMessage(List<UnalignedTrackIssue> issues) {
  final totalVerses = issues.fold<int>(0, (sum, i) => sum + i.count);
  final buffer = StringBuffer();
  buffer.writeln(
    '$totalVerses unaligned or omitted verse(s) found across ${issues.length} track(s):',
  );
  buffer.writeln();

  const maxTracks = 5;
  const maxLabelsPerTrack = 4;
  for (final issue in issues.take(maxTracks)) {
    final shownLabels = issue.fragmentLabels.take(maxLabelsPerTrack).join(', ');
    final extraCount = issue.fragmentLabels.length - maxLabelsPerTrack;
    final suffix = extraCount > 0 ? ', +$extraCount more' : '';
    buffer.writeln('• ${issue.track.name}: $shownLabels$suffix');
  }
  if (issues.length > maxTracks) {
    buffer.writeln('• …and ${issues.length - maxTracks} more track(s)');
  }

  buffer.writeln();
  buffer.write(
    'These verses lack valid timings and will be omitted from the exported file(s).',
  );
  return buffer.toString();
}

/// Prompts the user to confirm exporting when [issues] contains unaligned verses.
/// Returns `true` if there are no issues or the user chooses "Export Anyway".
Future<bool> confirmUnalignedExportWarning(
  BuildContext context,
  List<UnalignedTrackIssue> issues,
) async {
  if (issues.isEmpty) return true;

  final message = formatUnalignedIssuesMessage(issues);
  final confirmed = await showAppAlertDialog<bool>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Cancel',
    builder: (ctx) => MacosAlertDialog(
      appIcon: MacosIcon(
        AppIcons.exclamationmark_triangle_fill,
        color: AppTheme.warning(ctx),
      ),
      title: const Text('Unaligned Verses Found'),
      message: Text(message, textAlign: TextAlign.left),
      secondaryButton: PushButton(
        controlSize: ControlSize.large,
        secondary: true,
        child: const Text('Cancel'),
        onPressed: () => Navigator.of(ctx).pop(false),
      ),
      primaryButton: PushButton(
        controlSize: ControlSize.large,
        child: const Text('Export Anyway'),
        onPressed: () => Navigator.of(ctx).pop(true),
      ),
    ),
  );
  return confirmed ?? false;
}

/// Exports phrase timing for a single [track], warning the user first if any
/// verses lack valid timings.
Future<void> exportSingleTrackWithPrompt(
  BuildContext context,
  Project? project,
  Track track, {
  FileSaverFn? fileSaver,
}) async {
  if (project == null || !ExportService.canExportPhraseTiming(track)) {
    return;
  }

  try {
    final issues = await ExportService.findUnalignedIssues(project, [track]);
    if (issues.isNotEmpty) {
      if (!context.mounted) return;
      final shouldContinue =
          await confirmUnalignedExportWarning(context, issues);
      if (!shouldContinue) return;
    }

    final payload = await ExportService.buildPhraseTiming(project, track);
    if (payload == null || payload.isEmpty) return;

    final defaultName = ExportService.defaultPhraseTimingFilenameForTrack(
      track,
    );
    final bytes = Uint8List.fromList(utf8.encode(payload));
    final saver = fileSaver ?? FilePicker.saveFile;
    await saver(
      dialogTitle: 'Export Phrase Timing',
      fileName: defaultName,
      bytes: bytes,
      initialDirectory: project.directoryPath,
    );
  } catch (e) {
    if (context.mounted) {
      showAppAlertDialog(
        context: context,
        barrierLabel: 'Dismiss',
        builder: (ctx) => MacosAlertDialog(
          appIcon:
              const MacosIcon(AppIcons.exclamationmark_triangle_fill),
          title: const Text('Export Error'),
          message: Text(e.toString(), textAlign: TextAlign.center),
          primaryButton: PushButton(
            controlSize: ControlSize.large,
            child: const Text('OK'),
            onPressed: () => Navigator.of(ctx).pop(),
          ),
        ),
      );
    }
  }
}
