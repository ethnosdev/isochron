import 'dart:io';
import 'dart:math' as math;
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

class CollectionBatchView extends StatefulWidget {
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

  @override
  State<CollectionBatchView> createState() => _CollectionBatchViewState();
}

class _CollectionBatchViewState extends State<CollectionBatchView> {
  // Wizard State
  bool _showWizard = false;
  int _currentStep = 0;

  // Step 0 Fields
  late TextEditingController _nameController;
  late bool _copyMedia;

  // Step 1 Fields
  final List<String> _audioFiles = [];
  final List<String> _textFiles = [];
  final List<({String? audio, String? text, String trackName})> _pairedItems =
      [];

  // Step 2 Fields
  late bool _hasIds;
  late bool _generateIds;
  late TextEditingController _prefixController;

  // Step 3 Fields (Conditional)
  String? _dictPath;

  bool get _isFirstCollection =>
      widget.project.collections.isNotEmpty &&
      widget.project.collections.first.id == widget.collection.id;

  int get _totalSteps => _isFirstCollection ? 4 : 3;

  @override
  void initState() {
    super.initState();
    _initWizardState();
  }

  void _initWizardState() {
    _nameController = TextEditingController(text: widget.collection.name);
    _prefixController = TextEditingController(
      text: widget.project.defaultIdPrefix ?? "",
    );
    _copyMedia = widget.project.copyMediaIntoProject;
    _hasIds = widget.project.defaultHasIds;
    _generateIds = widget.project.defaultGenerateIds;
    _dictPath = widget.project.dictPath;
    _audioFiles.clear();
    _textFiles.clear();
    _pairedItems.clear();
  }

  @override
  void didUpdateWidget(CollectionBatchView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.collection.id != widget.collection.id) {
      _initWizardState();
      _showWizard = false;
      _currentStep = 0;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _prefixController.dispose();
    super.dispose();
  }

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

  void _updatePairing() {
    _naturalSort(_audioFiles);
    _naturalSort(_textFiles);

    _pairedItems.clear();

    final maxCount = math.max(_audioFiles.length, _textFiles.length);
    for (int i = 0; i < maxCount; i++) {
      final audio = i < _audioFiles.length ? _audioFiles[i] : null;
      final text = i < _textFiles.length ? _textFiles[i] : null;

      final name = audio != null
          ? p.basenameWithoutExtension(audio)
          : p.basenameWithoutExtension(text!);

      _pairedItems.add((audio: audio, text: text, trackName: name));
    }
  }

  Future<void> _pickWizardFiles() async {
    final settings = UserSettingsService();
    final result = await FilePicker.pickFiles(
      allowMultiple: true,
      initialDirectory: settings.lastSourceDir,
    );
    if (result == null || result.files.isEmpty) return;

    settings.setLastSourceDir(p.dirname(result.files.first.path!));

    final List<String> audio = [];
    final List<String> text = [];

    for (var file in result.files) {
      if (file.path == null) continue;
      final ext = p.extension(file.path!).toLowerCase();
      if (['.mp3', '.wav', '.m4a'].contains(ext)) {
        audio.add(file.path!);
      } else if (['.txt', '.phrases'].contains(ext)) {
        text.add(file.path!);
      }
    }

    setState(() {
      _audioFiles.addAll(audio);
      _textFiles.addAll(text);
      _updatePairing();
    });
  }

  bool _isStepValid() {
    if (_currentStep == 0) {
      return _nameController.text.trim().isNotEmpty;
    }
    if (_currentStep == 1) {
      return _pairedItems.isNotEmpty;
    }
    return true;
  }

  Future<void> _finishWizard() async {
    // 1. Commit and save global settings configurations
    widget.collection.name = _nameController.text.trim();
    widget.project.copyMediaIntoProject = _copyMedia;
    widget.project.hasPromptedForMediaStorage = true;
    widget.project.defaultHasIds = _hasIds;
    widget.project.defaultGenerateIds = _generateIds;
    widget.project.defaultIdPrefix = _prefixController.text.trim();
    widget.project.dictPath = _dictPath;

    Future<String> processFile(
      String originalPath,
      String subfolderName,
    ) async {
      if (!_copyMedia) {
        return originalPath;
      }

      final dir = Directory(
        p.join(
          widget.project.directoryPath,
          'collections',
          widget.collection.folderName,
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

    // 2. Generate and write physical folder and file tracks
    for (final item in _pairedItems) {
      String? finalAudio;
      String? finalText;

      if (item.audio != null) {
        finalAudio = await processFile(item.audio!, 'audio');
      }
      if (item.text != null) {
        finalText = await processFile(item.text!, 'text');
      }

      widget.collection.tracks.add(
        Track(
          id: const Uuid().v4(),
          collectionId: widget.collection.id,
          name: item.trackName,
          audioPath: finalAudio,
          textPath: finalText,
          outputFilename: '${item.trackName}_timing.json',
        ),
      );
    }

    widget.onChanged();
  }

  // UI Building Methods

  Widget _buildStep0(
    BuildContext context,
    MacosThemeData theme,
    BoxDecoration textFieldDecoration,
  ) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Collection Identity", style: theme.typography.title2),
          const SizedBox(height: 8),
          Text(
            "Configure collection names and asset localization behavior.",
            style: TextStyle(
              color: theme.typography.body.color?.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            "Collection Name",
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          MacosTextField(
            controller: _nameController,
            placeholder: 'e.g. Volume 1',
            decoration: textFieldDecoration,
          ),
          const SizedBox(height: 32),
          const Text(
            "File Storage Behavior",
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MacosCheckbox(
                value: _copyMedia,
                onChanged: (val) {
                  setState(() => _copyMedia = val);
                },
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Copy imported media files into project"),
                    const SizedBox(height: 4),
                    Text(
                      "Copying files keeps projects self-contained and portable. Leaving this off will reference hard drive locations directly.",
                      style: TextStyle(
                        fontSize: 11,
                        color: theme.typography.body.color?.withValues(
                          alpha: 0.6,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStep1(BuildContext context, MacosThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("Import Source Files", style: theme.typography.title2),
        const SizedBox(height: 8),
        Text(
          "Import audio and text transcript files to establish tracks. Files are naturally sorted and paired.",
          style: TextStyle(
            color: theme.typography.body.color?.withValues(alpha: 0.7),
          ),
        ),
        const SizedBox(height: 16),
        PushButton(
          controlSize: ControlSize.large,
          onPressed: _pickWizardFiles,
          child: const Text("Select Files..."),
        ),
        if (_pairedItems.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            "Auto-Pairing Verification (Detected ${_pairedItems.length} Tracks):",
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: theme.dividerColor),
                borderRadius: BorderRadius.circular(6),
              ),
              child: ListView.builder(
                itemCount: _pairedItems.length,
                itemExtent: 36,
                itemBuilder: (context, i) {
                  final item = _pairedItems[i];
                  final hasAudio = item.audio != null;
                  final hasText = item.text != null;

                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: theme.dividerColor),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: Text(
                            item.trackName,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Row(
                            children: [
                              Icon(
                                hasAudio
                                    ? CupertinoIcons.music_note
                                    : CupertinoIcons.clear_circled,
                                size: 14,
                                color: hasAudio
                                    ? CupertinoColors.activeGreen
                                    : CupertinoColors.systemRed,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  hasAudio
                                      ? p.basename(item.audio!)
                                      : "Missing Audio",
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: hasAudio
                                        ? theme.typography.body.color
                                        : CupertinoColors.systemRed,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Row(
                            children: [
                              Icon(
                                hasText
                                    ? CupertinoIcons.doc_text
                                    : CupertinoIcons.clear_circled,
                                size: 14,
                                color: hasText
                                    ? CupertinoColors.activeGreen
                                    : CupertinoColors.systemRed,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  hasText
                                      ? p.basename(item.text!)
                                      : "Missing Text",
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: hasText
                                        ? theme.typography.body.color
                                        : CupertinoColors.systemRed,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ] else ...[
          const Spacer(),
          const Center(
            child: Column(
              children: [
                Icon(
                  CupertinoIcons.folder_badge_plus,
                  size: 48,
                  color: CupertinoColors.systemGrey,
                ),
                SizedBox(height: 8),
                Text(
                  "Please select your transcripts and audio files.",
                  style: TextStyle(color: CupertinoColors.systemGrey),
                ),
              ],
            ),
          ),
          const Spacer(),
        ],
      ],
    );
  }

  Widget _buildStep2(
    BuildContext context,
    MacosThemeData theme,
    BoxDecoration textFieldDecoration,
  ) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Verse ID Strategy", style: theme.typography.title2),
          const SizedBox(height: 8),
          Text(
            "Determine how IDs should be assigned to text lines.",
            style: TextStyle(
              color: theme.typography.body.color?.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            "Select Assignment Mode",
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: 300,
            child: MacosPopupButton<int>(
              value: _generateIds ? 2 : (_hasIds ? 1 : 0),
              items: const [
                MacosPopupMenuItem<int>(
                  value: 0,
                  child: Text('None (Raw text lines only)'),
                ),
                MacosPopupMenuItem<int>(
                  value: 1,
                  child: Text('IDs are already included in files'),
                ),
                MacosPopupMenuItem<int>(
                  value: 2,
                  child: Text('Auto-Generate (Prefix + Rec + Verse)'),
                ),
              ],
              onChanged: (val) {
                if (val == null) return;
                setState(() {
                  if (val == 0) {
                    _hasIds = false;
                    _generateIds = false;
                  } else if (val == 1) {
                    _hasIds = true;
                    _generateIds = false;
                  } else if (val == 2) {
                    _hasIds = false;
                    _generateIds = true;
                  }
                });
              },
            ),
          ),
          if (_generateIds) ...[
            const SizedBox(height: 24),
            const Text(
              "Optional ID Prefix",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: 300,
              child: MacosTextField(
                controller: _prefixController,
                placeholder: 'e.g. 40',
                decoration: textFieldDecoration,
              ),
            ),
          ],
          const SizedBox(height: 32),
          Text(
            _generateIds
                ? "Preview: ID [${_prefixController.text}001001] / Text [In the beginning...]"
                : (_hasIds
                      ? "Preview: ID [40001001] / Text [In the beginning...]"
                      : "Preview: ID [] / Text [In the beginning...]"),
            style: const TextStyle(
              fontSize: 12,
              color: CupertinoColors.systemGrey,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStep3(BuildContext context, MacosThemeData theme) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Transliteration Dictionary", style: theme.typography.title2),
          const SizedBox(height: 8),
          Text(
            "Map non-Latin character strings to Latin phonetic characters to assist alignment systems.",
            style: TextStyle(
              color: theme.typography.body.color?.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              PushButton(
                controlSize: ControlSize.regular,
                secondary: true,
                onPressed: () async {
                  final settings = UserSettingsService();
                  final res = await FilePicker.pickFiles(
                    allowedExtensions: ['json'],
                    type: FileType.custom,
                    initialDirectory: settings.lastDictDir,
                  );
                  if (res != null && res.files.single.path != null) {
                    settings.setLastDictDir(p.dirname(res.files.single.path!));
                    setState(() => _dictPath = res.files.single.path!);
                  }
                },
                child: const Text("Select JSON File..."),
              ),
              const SizedBox(width: 16),
              if (_dictPath != null) ...[
                Expanded(
                  child: Text(
                    p.basename(_dictPath!),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                MacosIconButton(
                  icon: const MacosIcon(
                    CupertinoIcons.clear_circled_solid,
                    color: CupertinoColors.systemGrey,
                  ),
                  onPressed: () {
                    setState(() => _dictPath = null);
                  },
                ),
              ] else
                const Text(
                  "No dictionary configured.",
                  style: TextStyle(color: CupertinoColors.systemGrey),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWizardSidebar(BuildContext context) {
    final theme = MacosTheme.of(context);
    final activeColor = CupertinoColors.systemBlue.resolveFrom(context);
    final inactiveColor = CupertinoColors.systemGrey.resolveFrom(context);

    final stepLabels = [
      'Identity & Storage',
      'Import Files',
      'ID Strategy',
      if (_isFirstCollection) 'Transliteration',
    ];

    return Container(
      width: 200,
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: theme.brightness == Brightness.dark
            ? const Color(0xFF1E1E1E)
            : const Color(0xFFF5F5F7),
        border: Border(right: BorderSide(color: theme.dividerColor)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "New Collection",
            style: theme.typography.headline.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 24),
          ...List.generate(stepLabels.length, (index) {
            final isActive = _currentStep == index;
            final isCompleted = _currentStep > index;

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Row(
                children: [
                  Icon(
                    isCompleted
                        ? CupertinoIcons.checkmark_circle_fill
                        : (isActive
                              ? CupertinoIcons.circle_fill
                              : CupertinoIcons.circle),
                    size: 14,
                    color: isCompleted
                        ? CupertinoColors.systemGreen
                        : (isActive ? activeColor : inactiveColor),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      stepLabels[index],
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: isActive
                            ? FontWeight.bold
                            : FontWeight.normal,
                        color: isActive
                            ? theme.typography.body.color
                            : inactiveColor,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildStepContent(
    BuildContext context,
    MacosThemeData theme,
    BoxDecoration textFieldDecoration,
  ) {
    switch (_currentStep) {
      case 0:
        return _buildStep0(context, theme, textFieldDecoration);
      case 1:
        return _buildStep1(context, theme);
      case 2:
        return _buildStep2(context, theme, textFieldDecoration);
      case 3:
        if (_isFirstCollection) {
          return _buildStep3(context, theme);
        }
        return const SizedBox();
      default:
        return const SizedBox();
    }
  }

  Widget _buildWizardNavigation(BuildContext context) {
    final isLastStep = _currentStep == (_totalSteps - 1);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: MacosTheme.of(context).dividerColor),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          PushButton(
            controlSize: ControlSize.regular,
            secondary: true,
            onPressed: () {
              setState(() {
                _showWizard = false;
                _initWizardState();
              });
            },
            child: const Text("Cancel"),
          ),
          const Spacer(),
          if (_currentStep > 0)
            PushButton(
              controlSize: ControlSize.regular,
              secondary: true,
              onPressed: () {
                setState(() => _currentStep--);
              },
              child: const Text("Back"),
            ),
          const SizedBox(width: 8),
          PushButton(
            controlSize: ControlSize.regular,
            onPressed: !_isStepValid()
                ? null
                : () async {
                    if (isLastStep) {
                      await _finishWizard();
                    } else {
                      setState(() => _currentStep++);
                    }
                  },
            child: Text(isLastStep ? "Finish" : "Next"),
          ),
        ],
      ),
    );
  }

  Widget _buildWizardView(BuildContext context) {
    final theme = MacosTheme.of(context);
    final textFieldDecoration = BoxDecoration(
      color: theme.brightness == Brightness.dark
          ? const Color(0xFF2A2A2A)
          : const Color(0xFFFFFFFF),
      border: Border.all(color: theme.dividerColor),
      borderRadius: BorderRadius.circular(5.0),
    );

    return Row(
      children: [
        _buildWizardSidebar(context),
        Expanded(
          child: Column(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(32.0),
                  child: _buildStepContent(context, theme, textFieldDecoration),
                ),
              ),
              _buildWizardNavigation(context),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildWelcomeView(BuildContext context) {
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
            "Configure collection details and import resource files.",
            style: TextStyle(color: CupertinoColors.systemGrey),
          ),
          const SizedBox(height: 24),
          PushButton(
            controlSize: ControlSize.large,
            onPressed: () {
              setState(() {
                _showWizard = true;
                _currentStep = 0;
              });
            },
            child: const Text("Start Setup Wizard..."),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.collection.tracks.isEmpty) {
      if (_showWizard) {
        return _buildWizardView(context);
      }
      return _buildWelcomeView(context);
    }

    final List<Track> brokenTracks = widget.collection.tracks.where((t) {
      if (t.audioPath != null) {
        final p = t.getResolvedAudioPath(
          widget.project.directoryPath,
          widget.collection.folderName,
        );
        if (p == null || !File(p).existsSync()) return true;
      }
      if (t.textPath != null) {
        final p = t.getResolvedTextPath(
          widget.project.directoryPath,
          widget.collection.folderName,
        );
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
                  onPressed: widget.onHealBrokenLinks,
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
                secondary: widget.isRunning,
                onPressed: widget.isRunning
                    ? widget.onStopBatch
                    : widget.onRunBatch,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    MacosIcon(
                      widget.isRunning
                          ? CupertinoIcons.stop_fill
                          : CupertinoIcons.play_arrow_solid,
                      size: 14,
                      color: widget.isRunning
                          ? CupertinoColors.destructiveRed
                          : CupertinoColors.white,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      widget.isRunning ? "Stop Batch" : "Run Alignment on All",
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              PushButton(
                controlSize: ControlSize.regular,
                secondary: true,
                onPressed: () {
                  setState(() {
                    _initWizardState();
                    _showWizard = true;
                    _currentStep = 1; // Jump straight to file import selection
                  });
                },
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
        if (widget.isRunning)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 8.0,
            ),
            child: ProgressBar(value: widget.progress * 100),
          ),
        Container(height: 1, color: MacosTheme.of(context).dividerColor),
        Expanded(
          child: ListView.builder(
            itemCount: widget.collection.tracks.length,
            itemExtent: 56,
            itemBuilder: (ctx, i) {
              final t = widget.collection.tracks[i];
              return MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => widget.onOpenTrack(t),
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
