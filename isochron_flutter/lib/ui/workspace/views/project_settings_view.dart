import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:isochron_flutter/services/user_settings_service.dart';
import 'package:isochron_flutter/ui/models/project_model.dart';
import 'package:isochron_flutter/ui/settings/model_panel.dart';
import 'package:macos_ui/macos_ui.dart';
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
  late String _prefix;
  late TextEditingController _prefixController;
  late TextEditingController _langController;
  late TextEditingController _leadInController;
  late TextEditingController _collaboratorNameController;

  @override
  void initState() {
    super.initState();
    _prefix = widget.project.defaultIdPrefix ?? "";

    _prefixController = TextEditingController(text: _prefix);
    _langController = TextEditingController(
      text: widget.project.languageCode ?? '',
    );
    _leadInController = TextEditingController(
      text: widget.project.boundaryLeadInMs.toString(),
    );
    _collaboratorNameController = TextEditingController(
      text: UserSettingsService().collaboratorName,
    );
  }

  @override
  void dispose() {
    _prefixController.dispose();
    _langController.dispose();
    _leadInController.dispose();
    _collaboratorNameController.dispose();
    super.dispose();
  }

  void _triggerSave() {
    widget.project.defaultIdPrefix =
        _prefix.trim().isEmpty ? null : _prefix.trim();
    final lang = _langController.text.trim();
    widget.project.languageCode = lang.isEmpty ? null : lang.toLowerCase();
    final leadIn = int.tryParse(_leadInController.text.trim());
    if (leadIn != null && leadIn >= 0) {
      widget.project.boundaryLeadInMs = leadIn;
    }
    widget.onSaved();
  }

  @override
  Widget build(BuildContext context) {
    final theme = MacosTheme.of(context);

    final textFieldDecoration = BoxDecoration(
      color: theme.brightness == Brightness.dark
          ? const Color(0xFF2A2A2A)
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
              const SizedBox(height: 16),
              Row(
                children: [
                  Text(
                    "Collaborator Name:",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: theme.typography.body.color,
                    ),
                  ),
                  const SizedBox(width: 16),
                  SizedBox(
                    width: 220,
                    child: MacosTextField(
                      controller: _collaboratorNameController,
                      placeholder: 'e.g. Alice Smith',
                      decoration: textFieldDecoration,
                      onChanged: (val) {
                        UserSettingsService().setCollaboratorName(val);
                      },
                    ),
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
                    activeColor: AppTheme.accent(context),
                    onChanged: (val) {
                      setState(() {
                        widget.project.copyMediaIntoProject = val;
                        widget.project.hasPromptedForMediaStorage = true;
                      });
                      _triggerSave();
                    },
                  ),
                  const SizedBox(width: 8),
                  const Text("Copy imported media into project folder"),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                "Default ID Prefix (Optional)",
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: theme.typography.body.color,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                "Used to auto-generate sequential IDs when transcript files do not contain embedded IDs.",
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.grey(context),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: 300,
                child: MacosTextField(
                  controller: _prefixController,
                  placeholder: 'e.g. 40, MRK, MAT',
                  decoration: textFieldDecoration,
                  onChanged: (val) {
                    setState(() => _prefix = val);
                    _triggerSave();
                  },
                ),
              ),

              const SizedBox(height: 32),
              Container(height: 1, color: theme.dividerColor),
              const SizedBox(height: 32),

              // --- MMS ALIGNMENT SETTINGS ---
              Text("MMS Aligner Settings", style: theme.typography.headline),
              const SizedBox(height: 8),
              Text(
                "Configure language support and boundary calibration for Meta MMS-300M forced alignment.",
                style: TextStyle(
                  color: theme.typography.body.color?.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: 16),

              Text(
                "Language Code (ISO 639-3):",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: theme.typography.body.color,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                "Optional 3-letter language code (e.g. ell, eng, heb, cmn). Prefilled automatically from standard Bible filenames.",
                style: TextStyle(
                  fontSize: 12,
                  color: theme.typography.body.color?.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: 150,
                child: MacosTextField(
                  controller: _langController,
                  placeholder: 'e.g. eng',
                  decoration: textFieldDecoration,
                  onChanged: (_) => _triggerSave(),
                ),
              ),

              const SizedBox(height: 20),
              Text(
                "Boundary Lead-In (ms):",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: theme.typography.body.color,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                "Milliseconds subtracted from speech onset to catch breath sounds and initial consonants (default: 190 ms).",
                style: TextStyle(
                  fontSize: 12,
                  color: theme.typography.body.color?.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: 150,
                child: MacosTextField(
                  controller: _leadInController,
                  placeholder: '170',
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: textFieldDecoration,
                  onChanged: (_) => _triggerSave(),
                ),
              ),

              const SizedBox(height: 24),
              Row(
                children: [
                  PushButton(
                    controlSize: ControlSize.regular,
                    secondary: true,
                    onPressed: () => ModelPanel.show(context),
                    child: const Text("Manage Acoustic Model..."),
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
