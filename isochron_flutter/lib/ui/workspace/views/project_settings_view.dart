import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:isochron_flutter/services/user_settings_service.dart';
import 'package:isochron_flutter/ui/models/project_model.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:path/path.dart' as p;
import 'package:isochron_flutter/ui/theme/app_theme.dart';

class ProjectSettingsView extends StatefulWidget {
  final Project project;
  final VoidCallback onSaved;

  const ProjectSettingsView({
    super.key,
    required this.project,
    required this.onSaved,
  });

  @override
  State<ProjectSettingsView> createState() => _ProjectSettingsViewState();
}

class _ProjectSettingsViewState extends State<ProjectSettingsView> {
  late bool _generateIds;
  late bool _hasIds;
  late String _prefix;

  late TextEditingController _prefixController;
  late TextEditingController _offsetController;

  @override
  void initState() {
    super.initState();
    _generateIds = widget.project.defaultGenerateIds;
    _hasIds = widget.project.defaultHasIds;
    _prefix = widget.project.defaultIdPrefix ?? "";

    _prefixController = TextEditingController(text: _prefix);
    _offsetController = TextEditingController(
      text: widget.project.snapOffset?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    _prefixController.dispose();
    _offsetController.dispose();
    super.dispose();
  }

  String get _idPreview {
    if (_generateIds) {
      return "Preview: ID [${_prefix}001001] / Text [In the beginning...]";
    }
    if (_hasIds) return "Preview: ID [40001001] / Text [In the beginning...]";
    return "Preview: ID [] / Text [In the beginning...]";
  }

  void _triggerSave() {
    widget.project.defaultGenerateIds = _generateIds;
    widget.project.defaultHasIds = _hasIds;
    widget.project.defaultIdPrefix = _prefix;
    widget.onSaved();
  }

  @override
  Widget build(BuildContext context) {
    final theme = MacosTheme.of(context);

    final textFieldDecoration = BoxDecoration(
      color: theme.brightness == Brightness.dark
          ? const Color(
              0xFF2A2A2A,
            ) // Lighter grey for better contrast in dark mode
          : const Color(0xFFFFFFFF),
      border: Border.all(color: theme.dividerColor),
      borderRadius: BorderRadius.circular(5.0),
    );

    return SingleChildScrollView(
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 600),
          padding: const EdgeInsets.all(32.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Settings",
                style: theme.typography.largeTitle.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 32),

              // --- APP PREFERENCES ---
              Text("App Preferences", style: theme.typography.headline),
              const SizedBox(height: 8),
              Text(
                "Global application settings.",
                style: TextStyle(
                  color: theme.typography.body.color?.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Text(
                    "Theme:",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: theme.typography.body.color,
                    ),
                  ),
                  const SizedBox(width: 16),
                  ValueListenableBuilder<AppThemeMode>(
                    valueListenable: UserSettingsService().themeNotifier,
                    builder: (context, currentMode, _) {
                      return SizedBox(
                        width: 180,
                        child: MacosPopupButton<AppThemeMode>(
                          value: currentMode,
                          items: const [
                            MacosPopupMenuItem<AppThemeMode>(
                              value: AppThemeMode.system,
                              child: Text('System Default'),
                            ),
                            MacosPopupMenuItem<AppThemeMode>(
                              value: AppThemeMode.light,
                              child: Text('Light Mode'),
                            ),
                            MacosPopupMenuItem<AppThemeMode>(
                              value: AppThemeMode.dark,
                              child: Text('Dark Mode'),
                            ),
                          ],
                          onChanged: (val) {
                            if (val != null) {
                              UserSettingsService().setThemeMode(val);
                            }
                          },
                        ),
                      );
                    },
                  ),
                ],
              ),

              const SizedBox(height: 32),
              Container(height: 1, color: theme.dividerColor),
              const SizedBox(height: 32),

              // --- FILE MANAGEMENT ---
              Text("File Management", style: theme.typography.headline),
              const SizedBox(height: 8),
              Text(
                'By default, Isochron references your original audio and text files on your hard drive. '
                'If you prefer, it can copy them into the project folder so your project is portable.',
                style: TextStyle(
                  color: theme.typography.body.color?.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  MacosCheckbox(
                    value: widget.project.copyMediaIntoProject,
                    onChanged: (val) {
                      setState(() {
                        widget.project.copyMediaIntoProject = val;
                        // Mark as prompted so they aren't asked again
                        widget.project.hasPromptedForMediaStorage = true;
                      });
                      _triggerSave();
                    },
                  ),
                  const SizedBox(width: 8),
                  const Text("Copy imported media into project folder"),
                ],
              ),

              const SizedBox(height: 32),
              Container(height: 1, color: theme.dividerColor),
              const SizedBox(height: 32),

              // --- ID STRATEGY ---
              Text("Verse ID Strategy", style: theme.typography.headline),
              const SizedBox(height: 8),
              Text(
                "How should Isochron assign IDs to your text fragments?",
                style: TextStyle(
                  color: theme.typography.body.color?.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: 300,
                child: MacosPopupButton<int>(
                  value: _generateIds ? 2 : (_hasIds ? 1 : 0),
                  items: const [
                    MacosPopupMenuItem<int>(value: 0, child: Text('None')),
                    MacosPopupMenuItem<int>(
                      value: 1,
                      child: Text('IDs are included in text file'),
                    ),
                    MacosPopupMenuItem<int>(
                      value: 2,
                      child: Text('Auto-Generate (Prefix + Rec + Verse)'),
                    ),
                  ],
                  onChanged: (val) {
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
                    _triggerSave();
                  },
                ),
              ),
              if (_generateIds) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: 300,
                  child: MacosTextField(
                    controller: _prefixController,
                    placeholder: 'Optional ID Prefix (e.g. 40)',
                    decoration: textFieldDecoration,
                    onChanged: (val) {
                      setState(() => _prefix = val);
                      _triggerSave();
                    },
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Text(
                _idPreview,
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.grey(context),
                  fontStyle: FontStyle.italic,
                ),
              ),

              const SizedBox(height: 32),
              Container(height: 1, color: theme.dividerColor),
              const SizedBox(height: 32),

              // --- SNAP MODE ---
              Text("Boundary Snap Mode", style: theme.typography.headline),
              const SizedBox(height: 8),
              Text(
                "Determines how audio boundaries are calculated when resolving dynamic time warping.",
                style: TextStyle(
                  color: theme.typography.body.color?.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: 300,
                child: MacosPopupButton<String>(
                  value: widget.project.snapMode,
                  items: const [
                    MacosPopupMenuItem<String>(
                      value: 'onset',
                      child: Text('Onset (Snap to speech start)'),
                    ),
                    MacosPopupMenuItem<String>(
                      value: 'gap',
                      child: Text('Gap (Snap to center of silence)'),
                    ),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => widget.project.snapMode = val);
                      _triggerSave();
                    }
                  },
                ),
              ),

              // <--- CONDITIONAL ONSET OFFSET FIELD --->
              if (widget.project.snapMode == 'onset') ...[
                const SizedBox(height: 16),
                Text(
                  "Snap Offset (ms)",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: theme.typography.body.color,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  "Subtracts milliseconds from the detected onset to catch breath sounds or soft consonants.",
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.typography.body.color?.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: 150,
                  child: MacosTextField(
                    controller: _offsetController,
                    placeholder: 'e.g. 250',
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: textFieldDecoration,
                    onChanged: (val) {
                      widget.project.snapOffset = val.isEmpty
                          ? null
                          : int.tryParse(val);
                      _triggerSave();
                    },
                  ),
                ),
              ],

              const SizedBox(height: 32),
              Container(height: 1, color: theme.dividerColor),
              const SizedBox(height: 32),

              // --- TRANSLITERATION ---
              Text(
                "Global Transliteration Dictionary",
                style: theme.typography.headline,
              ),
              const SizedBox(height: 8),
              Text(
                "Provide a JSON map to convert non-Latin characters into Latin characters to assist the alignment engine.",
                style: TextStyle(
                  color: theme.typography.body.color?.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: 12),
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
                        settings.setLastDictDir(
                          p.dirname(res.files.single.path!),
                        );
                        setState(
                          () =>
                              widget.project.dictPath = res.files.single.path!,
                        );
                        _triggerSave();
                      }
                    },
                    child: const Text("Select JSON File..."),
                  ),
                  const SizedBox(width: 16),
                  if (widget.project.dictPath != null) ...[
                    Expanded(
                      child: Text(
                        p.basename(widget.project.dictPath!),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    MacosIconButton(
                      icon: MacosIcon(
                        CupertinoIcons.clear_circled_solid,
                        color: AppTheme.grey(context),
                      ),
                      onPressed: () {
                        setState(() => widget.project.dictPath = null);
                        _triggerSave();
                      },
                    ),
                  ] else
                    Text(
                      "No dictionary selected.",
                      style: TextStyle(color: AppTheme.grey(context)),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
