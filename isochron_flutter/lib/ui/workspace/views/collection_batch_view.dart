import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:isochron_flutter/services/export_service.dart';
import 'package:isochron_flutter/services/user_settings_service.dart';
import 'package:isochron_flutter/ui/models/project_model.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

class CollectionBatchView extends StatelessWidget {
  final Collection collection;
  final Project project;
  final bool isRunning;
  final String status;
  final double progress;
  final VoidCallback onRunBatch;
  final VoidCallback onStopBatch;
  final VoidCallback onChanged;
  final void Function(Track track) onOpenTrack;

  const CollectionBatchView({
    super.key,
    required this.collection,
    required this.project,
    required this.isRunning,
    required this.status,
    required this.progress,
    required this.onRunBatch,
    required this.onStopBatch,
    required this.onChanged,
    required this.onOpenTrack,
  });

  Future<void> _importAndAutoPair(BuildContext context) async {
    final settings = UserSettingsService();
    final result = await FilePicker.pickFiles(
      allowMultiple: true,
      initialDirectory: settings.lastSourceDir,
    );
    if (result == null || result.files.isEmpty) return;

    // --- NEW PROMPT LOGIC ---
    // If we haven't asked them yet, pause and ask how they want to store media.
    if (!project.hasPromptedForMediaStorage) {
      bool? shouldCopy = await showMacosAlertDialog<bool>(
        context: context,
        builder: (context) => MacosAlertDialog(
          appIcon: const MacosIcon(CupertinoIcons.folder_badge_plus),
          title: const Text('Project Storage Style'),
          message: const Text(
            'Do you want to copy these files into the Isochron project folder, or reference them from their current location on your hard drive?\n\nCopying them makes your project portable, but takes up more disk space.',
            textAlign: TextAlign.center,
          ),
          primaryButton: PushButton(
            controlSize: ControlSize.large,
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Copy to Project'),
          ),
          secondaryButton: PushButton(
            controlSize: ControlSize.large,
            secondary: true,
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep in Place'),
          ),
        ),
      );

      if (shouldCopy == null) return; // User pressed Escape or aborted
      project.copyMediaIntoProject = shouldCopy;
      project.hasPromptedForMediaStorage = true;
    }
    // -------------------------

    // Save the folder where they keep their raw audio/text so the picker opens there next time
    settings.setLastSourceDir(p.dirname(result.files.first.path!));

    final List<String> audioFiles = [];
    final List<String> textFiles = [];

    for (var file in result.files) {
      if (file.path == null) continue;
      final ext = p.extension(file.path!).toLowerCase();
      if (['.mp3', '.wav', '.m4a'].contains(ext)) {
        audioFiles.add(file.path!);
      } else if (['.txt', '.phrases'].contains(ext)) {
        textFiles.add(file.path!);
      }
    }

    if (audioFiles.isEmpty && textFiles.isEmpty) return;

    // Natural sort helper (ensures Track 2 comes before Track 10)
    int naturalCompare(String a, String b) {
      final regex = RegExp(r'\d+|\D+');
      final matchesA = regex.allMatches(a).map((m) => m.group(0)!).toList();
      final matchesB = regex.allMatches(b).map((m) => m.group(0)!).toList();
      for (int i = 0; i < matchesA.length && i < matchesB.length; i++) {
        final isNumA = int.tryParse(matchesA[i]) != null;
        final isNumB = int.tryParse(matchesB[i]) != null;
        if (isNumA && isNumB) {
          final cmp = int.parse(matchesA[i]).compareTo(int.parse(matchesB[i]));
          if (cmp != 0) return cmp;
        } else {
          final cmp = matchesA[i].compareTo(matchesB[i]);
          if (cmp != 0) return cmp;
        }
      }
      return matchesA.length.compareTo(matchesB.length);
    }

    audioFiles.sort(naturalCompare);
    textFiles.sort(naturalCompare);

    // Helper: Copies the file if settings require it, then returns the correct path string to save in the Track
    Future<String> processFile(
      String originalPath,
      String subfolderName,
    ) async {
      if (!project.copyMediaIntoProject)
        return originalPath; // Keep absolute path

      final dir = Directory(
        p.join(
          project.directoryPath,
          'collections',
          collection.id,
          subfolderName,
        ),
      );
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      final newPath = p.join(dir.path, p.basename(originalPath));
      await File(originalPath).copy(newPath);
      return p.basename(originalPath); // Return relative filename
    }

    // 1. FILL HOLES IN EXISTING TRACKS FIRST
    if (audioFiles.isNotEmpty) {
      final tracksNeedingAudio = collection.tracks
          .where((t) => t.audioPath == null)
          .toList();
      int fillCount = tracksNeedingAudio.length < audioFiles.length
          ? tracksNeedingAudio.length
          : audioFiles.length;
      for (int i = 0; i < fillCount; i++) {
        final originalAudio = audioFiles.removeAt(0);
        tracksNeedingAudio[i].audioPath = await processFile(
          originalAudio,
          'audio',
        );
      }
    }

    if (textFiles.isNotEmpty) {
      final tracksNeedingText = collection.tracks
          .where((t) => t.textPath == null)
          .toList();
      int fillCount = tracksNeedingText.length < textFiles.length
          ? tracksNeedingText.length
          : textFiles.length;
      for (int i = 0; i < fillCount; i++) {
        final originalText = textFiles.removeAt(0);
        tracksNeedingText[i].textPath = await processFile(originalText, 'text');
      }
    }

    // 2. PAIR AND CREATE NEW TRACKS WITH WHATEVER IS LEFT OVER
    int maxCount = audioFiles.length > textFiles.length
        ? audioFiles.length
        : textFiles.length;

    for (int i = 0; i < maxCount; i++) {
      final originalAudio = i < audioFiles.length ? audioFiles[i] : null;
      final originalText = i < textFiles.length ? textFiles[i] : null;

      final name = originalAudio != null
          ? p.basenameWithoutExtension(originalAudio)
          : p.basenameWithoutExtension(originalText!);

      String? finalAudio;
      String? finalText;

      if (originalAudio != null)
        finalAudio = await processFile(originalAudio, 'audio');
      if (originalText != null)
        finalText = await processFile(originalText, 'text');

      collection.tracks.add(
        Track(
          id: const Uuid().v4(),
          collectionId: collection.id, // Link to collection
          name: name,
          audioPath: finalAudio,
          textPath: finalText,
          outputFilename: '${name}_timing.json',
        ),
      );
    }

    onChanged(); // Triggers UI update and save
  }

  @override
  Widget build(BuildContext context) {
    if (collection.tracks.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const MacosIcon(
              CupertinoIcons.tray_arrow_down,
              size: 64,
              color: CupertinoColors.systemGrey,
            ),
            const SizedBox(height: 16),
            Text(
              "Empty Collection",
              style: MacosTheme.of(context).typography.title1,
            ),
            const SizedBox(height: 8),
            const Text(
              "Select audio and text files to generate your tracks.",
              style: TextStyle(color: CupertinoColors.systemGrey),
            ),
            const SizedBox(height: 24),
            PushButton(
              controlSize: ControlSize.large,
              onPressed: () => _importAndAutoPair(context),
              child: const Text("Select Files..."),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              PushButton(
                controlSize: ControlSize.large,
                secondary: isRunning,
                onPressed: isRunning ? onStopBatch : onRunBatch,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    MacosIcon(
                      isRunning
                          ? CupertinoIcons.stop_fill
                          : CupertinoIcons.play_arrow_solid,
                      size: 14,
                      color: isRunning
                          ? CupertinoColors.destructiveRed
                          : CupertinoColors.white,
                    ),
                    const SizedBox(width: 8),
                    Text(isRunning ? "Stop Batch" : "Run Alignment on All"),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              // ADDED: Import button always available
              PushButton(
                controlSize: ControlSize.regular,
                secondary: true,
                onPressed: () => _importAndAutoPair(context),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    MacosIcon(CupertinoIcons.add, size: 12),
                    SizedBox(width: 4),
                    Text("Import Files"),
                  ],
                ),
              ),
              const Spacer(),
              PushButton(
                controlSize: ControlSize.regular,
                secondary: true,
                onPressed: () async {
                  final out = await FilePicker.saveFile(
                    dialogTitle: 'Export CSV',
                    fileName: ExportService.defaultCsvFilename(project.name),
                    type: FileType.custom,
                    allowedExtensions: ['csv'],
                    initialDirectory: project.directoryPath,
                  );
                  if (out != null) {
                    final payload = await ExportService.buildCombinedCsv(
                      project,
                    );
                    await File(out).writeAsString(payload);
                  }
                },
                child: const Text("Export Combined CSV"),
              ),
            ],
          ),
        ),
        if (isRunning)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 8.0,
            ),
            child: ProgressBar(value: progress * 100),
          ),
        Container(height: 1, color: MacosTheme.of(context).dividerColor),
        Expanded(
          child: ListView.builder(
            itemCount: collection.tracks.length,
            itemExtent: 56,
            itemBuilder: (ctx, i) {
              final t = collection.tracks[i];
              return MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onOpenTrack(t),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: MacosTheme.of(context).dividerColor,
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        if (t.status == AlignmentStatus.processing)
                          const ProgressCircle()
                        else
                          const MacosIcon(
                            CupertinoIcons.waveform_path,
                            color: CupertinoColors.systemGrey,
                          ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                t.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (t.audioPath == null || t.textPath == null)
                                Text(
                                  t.audioPath == null
                                      ? "Missing Audio"
                                      : "Missing Text",
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: CupertinoColors.destructiveRed,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Text(
                          t.status.name.toUpperCase(),
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: CupertinoColors.systemGrey,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
