import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:isochron_flutter/ui/models/project_model.dart';
import 'package:macos_ui/macos_ui.dart';

class InspectorPane extends StatelessWidget {
  final Project project;
  final AlignmentPair? activePair;
  final VoidCallback onChanged;

  const InspectorPane({
    super.key,
    required this.project,
    this.activePair,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = MacosTheme.of(context);

    return Container(
      color: theme.canvasColor,
      width: double.infinity,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (activePair != null) ...[
              _buildPairProperties(context, theme),
              const SizedBox(height: 24),
              Container(height: 1, color: theme.dividerColor),
              const SizedBox(height: 24),
            ],
            _buildProjectSettings(context, theme),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // PAIR PROPERTIES (Only visible when an Alignment is active)
  // ---------------------------------------------------------------------------
  Widget _buildPairProperties(BuildContext context, MacosThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Alignment Properties', style: theme.typography.headline),
        const SizedBox(height: 16),

        // --- AUDIO SELECTION ---
        Text(
          'Audio Asset',
          style: theme.typography.subheadline.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          width: double.infinity,
          child: MacosPopupButton<String?>(
            value:
                project.audioPool.any((a) => a.id == activePair!.audioAssetId)
                ? activePair!.audioAssetId
                : null,
            hint: const Text('Select Audio...'),
            items: [
              const MacosPopupMenuItem<String?>(
                value: null,
                child: Text('None'),
              ),
              ...project.audioPool.map(
                (a) => MacosPopupMenuItem<String?>(
                  value: a.id,
                  child: Text(
                    a.filename,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
            onChanged: (val) {
              activePair!.audioAssetId = val;
              onChanged();
            },
          ),
        ),
        const SizedBox(height: 12),

        // --- TEXT SELECTION ---
        Text(
          'Text Asset',
          style: theme.typography.subheadline.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          width: double.infinity,
          child: MacosPopupButton<String?>(
            value: project.textPool.any((t) => t.id == activePair!.textAssetId)
                ? activePair!.textAssetId
                : null,
            hint: const Text('Select Text...'),
            items: [
              const MacosPopupMenuItem<String?>(
                value: null,
                child: Text('None'),
              ),
              ...project.textPool.map(
                (t) => MacosPopupMenuItem<String?>(
                  value: t.id,
                  child: Text(
                    t.filename,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
            onChanged: (val) {
              activePair!.textAssetId = val;
              onChanged();
            },
          ),
        ),
        const SizedBox(height: 12),

        // --- DICTIONARY SELECTION ---
        Text(
          'Transliteration (Optional)',
          style: theme.typography.subheadline.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          width: double.infinity,
          child: MacosPopupButton<String?>(
            value: project.dictPool.any((d) => d.id == activePair!.dictAssetId)
                ? activePair!.dictAssetId
                : null,
            hint: const Text('Default or Select...'),
            items: [
              const MacosPopupMenuItem<String?>(
                value: null,
                child: Text('Project Default'),
              ),
              ...project.dictPool.map(
                (d) => MacosPopupMenuItem<String?>(
                  value: d.id,
                  child: Text(
                    d.filename,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
            onChanged: (val) {
              activePair!.dictAssetId = val;
              onChanged();
            },
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // GLOBAL PROJECT SETTINGS
  // ---------------------------------------------------------------------------
  Widget _buildProjectSettings(BuildContext context, MacosThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Project Settings', style: theme.typography.headline),
        const SizedBox(height: 16),

        // --- SNAP MODE ---
        Text(
          'Snap Mode',
          style: theme.typography.subheadline.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          width: double.infinity,
          child: MacosPopupButton<String>(
            value: project.snapMode,
            items: const [
              MacosPopupMenuItem<String>(
                value: 'onset',
                child: Text('Onset (Phrase start)'),
              ),
              MacosPopupMenuItem<String>(
                value: 'gap',
                child: Text('Gap (Silence between)'),
              ),
            ],
            onChanged: (val) {
              if (val != null) {
                project.snapMode = val;
                onChanged();
              }
            },
          ),
        ),

        if (project.snapMode == 'onset') ...[
          const SizedBox(height: 12),
          Text(
            'Snap Offset (ms)',
            style: theme.typography.subheadline.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          MacosTextField(
            controller: TextEditingController(
              text: project.snapOffset?.toString() ?? '',
            ),
            placeholder: 'e.g. 250',
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (val) {
              project.snapOffset = val.isEmpty ? null : int.tryParse(val);
              onChanged();
            },
          ),
        ],
        const SizedBox(height: 16),

        // --- DEFAULT ID STRATEGY ---
        Text(
          'Verse ID Strategy',
          style: theme.typography.subheadline.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          width: double.infinity,
          child: MacosPopupButton<int>(
            value: project.defaultGenerateIds
                ? 2
                : (project.defaultHasIds ? 1 : 0),
            items: const [
              MacosPopupMenuItem<int>(value: 0, child: Text('None')),
              MacosPopupMenuItem<int>(value: 1, child: Text('IDs are in text')),
              MacosPopupMenuItem<int>(value: 2, child: Text('Auto-Generate')),
            ],
            onChanged: (val) {
              if (val == 0) {
                project.defaultHasIds = false;
                project.defaultGenerateIds = false;
              } else if (val == 1) {
                project.defaultHasIds = true;
                project.defaultGenerateIds = false;
              } else if (val == 2) {
                project.defaultHasIds = false;
                project.defaultGenerateIds = true;
              }
              onChanged();
            },
          ),
        ),

        if (project.defaultGenerateIds) ...[
          const SizedBox(height: 12),
          Text(
            'ID Prefix',
            style: theme.typography.subheadline.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          MacosTextField(
            controller: TextEditingController(
              text: project.defaultIdPrefix ?? '',
            ),
            placeholder: 'e.g. 40',
            onChanged: (val) {
              project.defaultIdPrefix = val;
              onChanged();
            },
          ),
        ],
      ],
    );
  }
}
