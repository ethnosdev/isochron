import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:isochron_flutter/services/user_settings_service.dart';
import 'package:isochron_flutter/ui/models/project_model.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

class _SortPart {
  final String value;
  final int? number;

  const _SortPart(this.value, this.number);
}

class _SortWrapper {
  final String originalPath;
  final List<_SortPart> parts;

  const _SortWrapper(this.originalPath, this.parts);
}

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
  final VoidCallback onHealBrokenLinks;

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
    required this.onHealBrokenLinks,
  });

  List<_SortPart> _getSortParts(String filename) {
    final regex = RegExp(r'\d+|\D+');
    return regex.allMatches(filename).map((m) {
      final val = m.group(0)!;
      return _SortPart(val, int.tryParse(val));
    }).toList();
  }

  int _compareWrappers(_SortWrapper a, _SortWrapper b) {
    final len = a.parts.length < b.parts.length
        ? a.parts.length
        : b.parts.length;
    for (int i = 0; i < len; i++) {
      final pA = a.parts[i];
      final pB = b.parts[i];

      if (pA.number != null && pB.number != null) {
        final cmp = pA.number!.compareTo(pB.number!);
        if (cmp != 0) return cmp;
      } else {
        final cmp = pA.value.compareTo(pB.value);
        if (cmp != 0) return cmp;
      }
    }
    return a.parts.length.compareTo(b.parts.length);
  }

  void _naturalSort(List<String> paths) {
    final wrappers = paths.map((path) {
      final filename = p.basenameWithoutExtension(path);
      return _SortWrapper(path, _getSortParts(filename));
    }).toList();

    wrappers.sort(_compareWrappers);

    for (int i = 0; i < paths.length; i++) {
      paths[i] = wrappers[i].originalPath;
    }
  }

  Future<void> _importAndAutoPair(BuildContext context) async {
    final settings = UserSettingsService();
    final result = await FilePicker.pickFiles(
      allowMultiple: true,
      initialDirectory: settings.lastSourceDir,
    );
    if (result == null || result.files.isEmpty) return;

    if (!project.hasPromptedForMediaStorage) {
      if (!context.mounted) return;
      bool? shouldCopy = await showMacosAlertDialog<bool>(
        context: context,
        builder: (context) => MacosAlertDialog(
          appIcon: const MacosIcon(CupertinoIcons.folder_badge_plus),
          title: const Text('Project Storage Style'),
          message: const Text(
            'Do you want to copy these files into the Isochron project folder, '
            'or reference them from their current location on your hard drive?\n\n'
            'Copying them makes your project portable, but takes up more disk space.',
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

      if (shouldCopy == null) return;
      project.copyMediaIntoProject = shouldCopy;
      project.hasPromptedForMediaStorage = true;
    }

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

    _naturalSort(audioFiles);
    _naturalSort(textFiles);

    Future<String> processFile(
      String originalPath,
      String subfolderName,
    ) async {
      if (!project.copyMediaIntoProject) {
        return originalPath;
      }

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
      return p.basename(originalPath);
    }

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

      if (originalAudio != null) {
        finalAudio = await processFile(originalAudio, 'audio');
      }
      if (originalText != null) {
        finalText = await processFile(originalText, 'text');
      }

      collection.tracks.add(
        Track(
          id: const Uuid().v4(),
          collectionId: collection.id,
          name: name,
          audioPath: finalAudio,
          textPath: finalText,
          outputFilename: '${name}_timing.json',
        ),
      );
    }

    onChanged();
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

    final List<Track> brokenTracks = collection.tracks.where((t) {
      if (t.audioPath != null) {
        final p = t.getResolvedAudioPath(project.directoryPath);
        if (p == null || !File(p).existsSync()) return true;
      }
      if (t.textPath != null) {
        final p = t.getResolvedTextPath(project.directoryPath);
        if (p == null || !File(p).existsSync()) return true;
      }
      return false;
    }).toList();

    final bool hasBroken = brokenTracks.isNotEmpty;

    return Column(
      children: [
        if (hasBroken)
          Container(
            margin: const EdgeInsets.all(16.0),
            padding: const EdgeInsets.all(12.0),
            decoration: BoxDecoration(
              color: CupertinoColors.systemRed.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8.0),
              border: Border.all(
                color: CupertinoColors.systemRed.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  CupertinoIcons.exclamationmark_triangle_fill,
                  color: CupertinoColors.destructiveRed,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '${brokenTracks.length} tracks in this collection have missing source files. This happens if the media directory was renamed or moved.',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                const SizedBox(width: 12),
                PushButton(
                  controlSize: ControlSize.regular,
                  onPressed: onHealBrokenLinks,
                  child: const Text('Locate Missing Media...'),
                ),
              ],
            ),
          ),
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
