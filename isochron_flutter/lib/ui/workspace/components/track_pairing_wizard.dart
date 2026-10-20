import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:isochron_flutter/services/user_settings_service.dart';
import 'package:isochron_flutter/ui/components/macos_dialogs.dart';
import 'package:isochron_flutter/ui/theme/app_theme.dart';
import 'package:isochron_flutter/utils/media_pairing_engine.dart';
import 'package:isochron_flutter/utils/natural_sort.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:path/path.dart' as p;

class TrackPairingResult {
  final List<PairedRow> rows;

  const TrackPairingResult({required this.rows});
}

class TrackPairingWizard extends StatefulWidget {
  final String collectionName;
  final List<String>? initialAudioFiles;
  final List<String>? initialTextFiles;

  const TrackPairingWizard({
    super.key,
    required this.collectionName,
    this.initialAudioFiles,
    this.initialTextFiles,
  });

  static Future<TrackPairingResult?> show(
    BuildContext context, {
    required String collectionName,
    List<String>? initialAudioFiles,
    List<String>? initialTextFiles,
  }) {
    return showAppSheet<TrackPairingResult>(
      context: context,
      barrierDismissible: true,
      builder: (_) => MacosSheet(
        child: SizedBox(
          width: 840,
          height: 640,
          child: TrackPairingWizard(
            collectionName: collectionName,
            initialAudioFiles: initialAudioFiles,
            initialTextFiles: initialTextFiles,
          ),
        ),
      ),
    );
  }

  @override
  State<TrackPairingWizard> createState() => _TrackPairingWizardState();
}

class _TrackPairingWizardState extends State<TrackPairingWizard> {
  final List<String> _audioFiles = [];
  final List<String> _textFiles = [];
  final List<PairedRow> _rows = [];

  PairingStrategy _strategy = PairingStrategy.smartAuto;
  TrackNameRule _nameRule = TrackNameRule.audioStem;

  String? _audioSourceLabel;
  String? _textSourceLabel;

  @override
  void initState() {
    super.initState();
    if (widget.initialAudioFiles != null) {
      _audioFiles.addAll(widget.initialAudioFiles!);
    }
    if (widget.initialTextFiles != null) {
      _textFiles.addAll(widget.initialTextFiles!);
    }
    if (_audioFiles.isNotEmpty || _textFiles.isNotEmpty) {
      _recomputePairings();
    }
  }

  void _recomputePairings() {
    final result = MediaPairingEngine.computePairings(
      audioFiles: _audioFiles,
      textFiles: _textFiles,
      strategy: _strategy,
      nameRule: _nameRule,
    );
    setState(() {
      _rows.clear();
      _rows.addAll(result);
    });
  }

  Future<void> _pickAudioFolder() async {
    final settings = UserSettingsService();
    final picked = await FilePicker.getDirectoryPath(
      dialogTitle: 'Select Folder Containing Audio Files',
      initialDirectory: settings.lastSourceDir,
    );
    if (picked == null || !mounted) return;
    settings.setLastSourceDir(picked);

    final files = await _scanDirectory(
      picked,
      allowedExtensions: ['.mp3', '.wav', '.m4a'],
    );
    // Also check if directory contains text files and auto-populate if text is empty
    if (_textFiles.isEmpty) {
      final texts = await _scanDirectory(
        picked,
        allowedExtensions: ['.txt', '.phrases'],
      );
      if (texts.isNotEmpty) {
        _textFiles.clear();
        _textFiles.addAll(texts);
        _textSourceLabel = p.basename(picked);
      }
    }

    setState(() {
      _audioFiles.clear();
      _audioFiles.addAll(files);
      _audioSourceLabel = p.basename(picked);
    });
    _recomputePairings();
  }

  Future<void> _pickAudioFiles() async {
    final settings = UserSettingsService();
    final result = await FilePicker.pickFiles(
      allowMultiple: true,
      dialogTitle: 'Select Audio Files',
      type: FileType.custom,
      allowedExtensions: ['mp3', 'wav', 'm4a'],
      initialDirectory: settings.lastSourceDir,
    );
    if (result == null || result.files.isEmpty || !mounted) return;

    final pickedPaths = result.files
        .where((f) => f.path != null)
        .map((f) => f.path!)
        .toList();
    if (pickedPaths.isNotEmpty) {
      settings.setLastSourceDir(p.dirname(pickedPaths.first));
    }

    setState(() {
      _audioFiles.clear();
      _audioFiles.addAll(pickedPaths);
      _audioSourceLabel = '${pickedPaths.length} selected';
    });
    _recomputePairings();
  }

  Future<void> _pickTextFolder() async {
    final settings = UserSettingsService();
    final picked = await FilePicker.getDirectoryPath(
      dialogTitle: 'Select Folder Containing Transcript Files',
      initialDirectory: settings.lastSourceDir,
    );
    if (picked == null || !mounted) return;
    settings.setLastSourceDir(picked);

    final files = await _scanDirectory(
      picked,
      allowedExtensions: ['.txt', '.phrases'],
    );
    setState(() {
      _textFiles.clear();
      _textFiles.addAll(files);
      _textSourceLabel = p.basename(picked);
    });
    _recomputePairings();
  }

  Future<void> _pickTextFiles() async {
    final settings = UserSettingsService();
    final result = await FilePicker.pickFiles(
      allowMultiple: true,
      dialogTitle: 'Select Transcript Files',
      type: FileType.custom,
      allowedExtensions: ['txt', 'phrases'],
      initialDirectory: settings.lastSourceDir,
    );
    if (result == null || result.files.isEmpty || !mounted) return;

    final pickedPaths = result.files
        .where((f) => f.path != null)
        .map((f) => f.path!)
        .toList();
    if (pickedPaths.isNotEmpty) {
      settings.setLastSourceDir(p.dirname(pickedPaths.first));
    }

    setState(() {
      _textFiles.clear();
      _textFiles.addAll(pickedPaths);
      _textSourceLabel = '${pickedPaths.length} selected';
    });
    _recomputePairings();
  }

  Future<List<String>> _scanDirectory(
    String path, {
    required List<String> allowedExtensions,
  }) async {
    final results = <String>[];
    try {
      final dir = Directory(path);
      final entries = await dir.list(recursive: false).toList();
      for (final e in entries) {
        if (e is File) {
          final ext = p.extension(e.path).toLowerCase();
          if (allowedExtensions.contains(ext)) {
            results.add(e.path);
          }
        }
      }
      naturalSort(results);
    } catch (e) {
      debugPrint('Error scanning directory: $e');
    }
    return results;
  }

  int get _completeCount => _rows.where((r) => r.isComplete).length;
  int get _missingTextCount => _rows.where((r) => r.isAudioOnly).length;
  int get _missingAudioCount => _rows.where((r) => r.isTextOnly).length;

  void _handleImport() {
    if (_rows.isEmpty) return;
    Navigator.of(context).pop(TrackPairingResult(rows: _rows));
  }

  @override
  Widget build(BuildContext context) {
    final theme = MacosTheme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Add & Pair Media — ${widget.collectionName}',
                    style: theme.typography.headline,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Select audio recordings and transcripts to pair them into collection tracks.',
                    style: theme.typography.subheadline,
                  ),
                ],
              ),
              MacosIconButton(
                icon: const MacosIcon(CupertinoIcons.xmark_circle),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Dual Source Picker Cards
          Row(
            children: [
              Expanded(
                child: _buildSourceCard(
                  title: 'Audio Files',
                  icon: CupertinoIcons.waveform,
                  count: _audioFiles.length,
                  label: _audioSourceLabel,
                  emptyText: 'No audio selected (.mp3, .wav, .m4a)',
                  onPickFolder: _pickAudioFolder,
                  onPickFiles: _pickAudioFiles,
                  onClear: _audioFiles.isEmpty
                      ? null
                      : () {
                          setState(() {
                            _audioFiles.clear();
                            _audioSourceLabel = null;
                          });
                          _recomputePairings();
                        },
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _buildSourceCard(
                  title: 'Transcripts',
                  icon: CupertinoIcons.doc_text,
                  count: _textFiles.length,
                  label: _textSourceLabel,
                  emptyText: 'No transcripts selected (.txt, .phrases)',
                  onPickFolder: _pickTextFolder,
                  onPickFiles: _pickTextFiles,
                  onClear: _textFiles.isEmpty
                      ? null
                      : () {
                          setState(() {
                            _textFiles.clear();
                            _textSourceLabel = null;
                          });
                          _recomputePairings();
                        },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Toolbar / Controls Bar
          if (_rows.isNotEmpty || _audioFiles.isNotEmpty || _textFiles.isNotEmpty)
            _buildToolbar(theme, isDark),

          const SizedBox(height: 8),

          // Main Review Table
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFFFFFFF),
                borderRadius: BorderRadius.circular(8.0),
                border: Border.all(color: theme.dividerColor),
              ),
              child: _rows.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            CupertinoIcons.arrow_right_arrow_left_square,
                            size: 40,
                            color: AppTheme.grey(context),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Select audio and transcript files above to preview pairings.',
                            style: TextStyle(
                              color: AppTheme.grey(context),
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    )
                  : Column(
                      children: [
                        _buildTableHeader(theme),
                        Container(height: 1, color: theme.dividerColor),
                        Expanded(
                          child: ListView.separated(
                            itemCount: _rows.length,
                            separatorBuilder: (_, _) => Container(
                              height: 1,
                              margin: const EdgeInsets.symmetric(horizontal: 8),
                              color: theme.dividerColor,
                            ),
                            itemBuilder: (context, index) =>
                                _buildTableRow(index, theme),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 14),

          // Footer
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Summary chips
              Row(
                children: [
                  if (_rows.isNotEmpty) ...[
                    _buildStatusChip(
                      '$_completeCount Paired',
                      CupertinoIcons.checkmark_circle_fill,
                      const Color(0xFF28A745),
                    ),
                    const SizedBox(width: 8),
                    if (_missingTextCount > 0) ...[
                      _buildStatusChip(
                        '$_missingTextCount Missing Transcript',
                        CupertinoIcons.exclamationmark_circle_fill,
                        const Color(0xFFE67E22),
                      ),
                      const SizedBox(width: 8),
                    ],
                    if (_missingAudioCount > 0)
                      _buildStatusChip(
                        '$_missingAudioCount Missing Audio',
                        CupertinoIcons.exclamationmark_circle_fill,
                        const Color(0xFFE67E22),
                      ),
                  ],
                ],
              ),
              Row(
                children: [
                  PushButton(
                    controlSize: ControlSize.large,
                    secondary: true,
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 10),
                  PushButton(
                    controlSize: ControlSize.large,
                    onPressed: _rows.isNotEmpty ? _handleImport : null,
                    child: Text(
                      _rows.isEmpty
                          ? 'Import Tracks'
                          : 'Import ${_rows.length} Tracks',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSourceCard({
    required String title,
    required IconData icon,
    required int count,
    required String? label,
    required String emptyText,
    required VoidCallback onPickFolder,
    required VoidCallback onPickFiles,
    required VoidCallback? onClear,
  }) {
    final theme = MacosTheme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(12.0),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF262626) : const Color(0xFFF7F7F7),
        borderRadius: BorderRadius.circular(8.0),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(icon, size: 16, color: theme.typography.headline.color),
                  const SizedBox(width: 6),
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  if (count > 0) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.accent(context).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$count',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.accent(context),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              if (onClear != null)
                MacosIconButton(
                  icon: const MacosIcon(CupertinoIcons.trash, size: 13),
                  onPressed: onClear,
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            label ?? emptyText,
            style: TextStyle(
              fontSize: 11.5,
              color: label != null
                  ? theme.typography.body.color
                  : AppTheme.grey(context),
            ),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              PushButton(
                controlSize: ControlSize.small,
                secondary: true,
                onPressed: onPickFolder,
                child: const Text('Select Folder...'),
              ),
              const SizedBox(width: 8),
              PushButton(
                controlSize: ControlSize.small,
                secondary: true,
                onPressed: onPickFiles,
                child: const Text('Select Files...'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar(MacosThemeData theme, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF242424) : const Color(0xFFEFEFEF),
        borderRadius: BorderRadius.circular(6.0),
      ),
      child: Row(
        children: [
          const Text(
            'Strategy: ',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          MacosPopupButton<PairingStrategy>(
            value: _strategy,
            onChanged: (val) {
              if (val != null) {
                setState(() => _strategy = val);
                _recomputePairings();
              }
            },
            items: const [
              MacosPopupMenuItem(
                value: PairingStrategy.smartAuto,
                child: Text('Smart Auto (Stems & Numbers)'),
              ),
              MacosPopupMenuItem(
                value: PairingStrategy.exactStem,
                child: Text('Exact Stem Only'),
              ),
              MacosPopupMenuItem(
                value: PairingStrategy.numericTokens,
                child: Text('Match by Numbers'),
              ),
              MacosPopupMenuItem(
                value: PairingStrategy.listOrder,
                child: Text('List Order (1-to-1)'),
              ),
            ],
          ),
          const SizedBox(width: 14),
          const Text(
            'Names: ',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          MacosPopupButton<TrackNameRule>(
            value: _nameRule,
            onChanged: (val) {
              if (val != null) {
                setState(() {
                  _nameRule = val;
                  MediaPairingEngine.applyNamingRule(_rows, _nameRule);
                });
              }
            },
            items: const [
              MacosPopupMenuItem(
                value: TrackNameRule.audioStem,
                child: Text('Audio Filename'),
              ),
              MacosPopupMenuItem(
                value: TrackNameRule.textStem,
                child: Text('Transcript Filename'),
              ),
            ],
          ),
          const Spacer(),
          PushButton(
            controlSize: ControlSize.small,
            secondary: true,
            onPressed: _recomputePairings,
            child: const Text('Re-Pair'),
          ),
        ],
      ),
    );
  }

  Widget _buildTableHeader(MacosThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
      color: theme.canvasColor,
      child: const Row(
        children: [
          SizedBox(
            width: 30,
            child: Text(
              '#',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
            ),
          ),
          SizedBox(
            width: 160,
            child: Text(
              'Track Name',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
            ),
          ),
          SizedBox(width: 8),
          Expanded(
            flex: 4,
            child: Text(
              'Audio File',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
            ),
          ),
          SizedBox(
            width: 32,
            child: Center(
              child: Text(
                'Link',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
              ),
            ),
          ),
          Expanded(
            flex: 4,
            child: Text(
              'Transcript File',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
            ),
          ),
          SizedBox(
            width: 120,
            child: Center(
              child: Text(
                'Adjustments',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTableRow(int index, MacosThemeData theme) {
    final row = _rows[index];
    final isDark = theme.brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
      child: Row(
        children: [
          // Index
          SizedBox(
            width: 30,
            child: Text(
              '${index + 1}',
              style: TextStyle(fontSize: 11.5, color: AppTheme.grey(context)),
            ),
          ),

          // Track Name Field
          SizedBox(
            width: 160,
            child: MacosTextField(
              controller: TextEditingController(text: row.name)
                ..selection = TextSelection.collapsed(offset: row.name.length),
              style: const TextStyle(fontSize: 11.5),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF282828) : const Color(0xFFF9F9F9),
                border: Border.all(color: theme.dividerColor),
                borderRadius: BorderRadius.circular(4),
              ),
              onChanged: (val) => row.name = val.trim(),
            ),
          ),
          const SizedBox(width: 8),

          // Audio File
          Expanded(
            flex: 4,
            child: row.audioPath != null
                ? Row(
                    children: [
                      const Icon(CupertinoIcons.waveform, size: 13),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          p.basename(row.audioPath!),
                          style: const TextStyle(fontSize: 11.5),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  )
                : Text(
                    '(missing audio)',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontStyle: FontStyle.italic,
                      color: AppTheme.destructive(context),
                    ),
                  ),
          ),

          // Link Status
          SizedBox(
            width: 32,
            child: Center(
              child: Icon(
                row.isComplete
                    ? CupertinoIcons.link
                    : CupertinoIcons.exclamationmark_triangle,
                size: 14,
                color: row.isComplete
                    ? const Color(0xFF28A745)
                    : const Color(0xFFE67E22),
              ),
            ),
          ),

          // Transcript File
          Expanded(
            flex: 4,
            child: row.textPath != null
                ? Row(
                    children: [
                      const Icon(CupertinoIcons.doc_text, size: 13),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          p.basename(row.textPath!),
                          style: const TextStyle(fontSize: 11.5),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  )
                : Text(
                    '(missing transcript)',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontStyle: FontStyle.italic,
                      color: AppTheme.destructive(context),
                    ),
                  ),
          ),

          // Row Adjustments
          SizedBox(
            width: 120,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // Insert gap in transcript (shift text down)
                MacosTooltip(
                  message: 'Insert gap in transcript (shift transcripts down)',
                  child: MacosIconButton(
                    icon: const MacosIcon(
                      CupertinoIcons.arrow_down_to_line,
                      size: 13,
                    ),
                    onPressed: () {
                      setState(() {
                        MediaPairingEngine.insertGap(
                          _rows,
                          index,
                          isText: true,
                        );
                      });
                    },
                  ),
                ),
                // Shift text up
                MacosTooltip(
                  message: 'Shift transcript up',
                  child: MacosIconButton(
                    icon: const MacosIcon(CupertinoIcons.chevron_up, size: 13),
                    onPressed: index > 0
                        ? () {
                            setState(() {
                              MediaPairingEngine.shiftUp(
                                _rows,
                                index,
                                isText: true,
                              );
                            });
                          }
                        : null,
                  ),
                ),
                // Shift text down
                MacosTooltip(
                  message: 'Shift transcript down',
                  child: MacosIconButton(
                    icon: const MacosIcon(CupertinoIcons.chevron_down, size: 13),
                    onPressed: index < _rows.length - 1
                        ? () {
                            setState(() {
                              MediaPairingEngine.shiftDown(
                                _rows,
                                index,
                                isText: true,
                              );
                            });
                          }
                        : null,
                  ),
                ),
                // Remove row
                MacosTooltip(
                  message: 'Remove row',
                  child: MacosIconButton(
                    icon: const MacosIcon(CupertinoIcons.xmark, size: 12),
                    onPressed: () {
                      setState(() {
                        _rows.removeAt(index);
                      });
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusChip(String label, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
