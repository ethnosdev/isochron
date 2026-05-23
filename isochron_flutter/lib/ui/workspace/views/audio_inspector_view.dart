import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:isochron_flutter/services/audio_service.dart';
import 'package:isochron_flutter/services/user_settings_service.dart';
import 'package:isochron_flutter/ui/models/project_model.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:path/path.dart' as p;
import 'package:isochron_flutter/ui/theme/app_theme.dart';

class AudioInspectorView extends StatefulWidget {
  final Track track;
  final Project project;
  final Collection collection;
  final Future<void> Function(Future<void> Function()) onReplace;

  const AudioInspectorView({
    super.key,
    required this.track,
    required this.project,
    required this.collection,
    required this.onReplace,
  });

  @override
  State<AudioInspectorView> createState() => _AudioInspectorViewState();
}

class _AudioInspectorViewState extends State<AudioInspectorView> {
  final AudioService _audio = AudioService();
  bool _isPlaying = false;
  Duration? _duration;

  @override
  void initState() {
    super.initState();
    _initAudio();
    _audio.stateStream.listen((s) {
      if (mounted) setState(() => _isPlaying = s.playing);
    });
  }

  Future<void> _initAudio() async {
    final resolvedPath = widget.track.getResolvedAudioPath(
      widget.project.directoryPath,
      widget.collection.folderName,
    );
    if (resolvedPath != null && await File(resolvedPath).exists()) {
      _duration = await _audio.load(resolvedPath);
      setState(() {});
    }
  }

  @override
  void dispose() {
    _audio.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.track.audioPath == null) {
      return Center(
        child: PushButton(
          controlSize: ControlSize.large,
          onPressed: _replaceFile,
          child: const Text("Attach Audio File"),
        ),
      );
    }

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          MacosIcon(
            CupertinoIcons.speaker_3_fill,
            size: 80,
            color: AppTheme.accent(context),
          ),
          const SizedBox(height: 24),
          Text(
            p.basename(widget.track.audioPath!),
            style: MacosTheme.of(context).typography.title1,
          ),
          const SizedBox(height: 8),
          Text(
            _duration != null
                ? "${_duration!.inSeconds} seconds"
                : "Loading...",
            style: TextStyle(color: AppTheme.grey(context)),
          ),
          const SizedBox(height: 32),
          MacosIconButton(
            icon: MacosIcon(
              _isPlaying
                  ? CupertinoIcons.pause_fill
                  : CupertinoIcons.play_arrow_solid,
              size: 24,
              color: CupertinoColors.white,
            ),
            backgroundColor: AppTheme.accent(context),
            shape: BoxShape.circle,
            onPressed: () => _isPlaying ? _audio.pause() : _audio.play(),
          ),
          const SizedBox(height: 48),
          PushButton(
            secondary: true,
            controlSize: ControlSize.regular,
            onPressed: _replaceFile,
            child: const Text("Replace Audio File..."),
          ),
        ],
      ),
    );
  }

  Future<void> _replaceFile() async {
    final settings = UserSettingsService();
    final result = await FilePicker.pickFiles(
      type: FileType.audio,
      initialDirectory: settings.lastSourceDir,
    );
    if (result != null && result.files.single.path != null) {
      final originalPath = result.files.single.path!;
      settings.setLastSourceDir(p.dirname(originalPath));

      widget.onReplace(() async {
        if (widget.project.copyMediaIntoProject) {
          final audioDir = Directory(
            p.join(
              widget.project.directoryPath,
              'collections',
              widget.collection.folderName,
              'audio',
            ),
          );
          if (!await audioDir.exists()) await audioDir.create(recursive: true);
          final newPath = p.join(audioDir.path, p.basename(originalPath));
          await File(originalPath).copy(newPath);
          widget.track.audioPath = p.basename(originalPath);
        } else {
          widget.track.audioPath = originalPath;
        }
        await _initAudio();
      });
    }
  }
}
