import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:isochron_flutter/services/audio_service.dart';
import 'package:isochron_flutter/services/user_settings_service.dart';
import 'package:isochron_flutter/ui/models/project_model.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:path/path.dart' as p;

class AudioInspectorView extends StatefulWidget {
  final Track track;
  final Future<void> Function(Future<void> Function()) onReplace;

  const AudioInspectorView({
    super.key,
    required this.track,
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
    if (widget.track.audioPath != null &&
        await File(widget.track.audioPath!).exists()) {
      _duration = await _audio.load(widget.track.audioPath!);
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
          const MacosIcon(
            CupertinoIcons.speaker_3_fill,
            size: 80,
            color: CupertinoColors.activeBlue,
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
            style: const TextStyle(color: CupertinoColors.systemGrey),
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
            backgroundColor: CupertinoColors.activeBlue,
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
      settings.setLastSourceDir(p.dirname(result.files.single.path!));
      widget.onReplace(() async {
        widget.track.audioPath = result.files.single.path!;
        await _initAudio();
      });
    }
  }
}
