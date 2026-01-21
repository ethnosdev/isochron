import 'package:flutter/material.dart';
import '../../controllers/alignment_controller.dart';
import '../../models/app_state.dart';

class ControlBar extends StatelessWidget {
  final AlignmentController controller;
  final AppState state;
  final VoidCallback onRun;

  const ControlBar({
    super.key,
    required this.controller,
    required this.state,
    required this.onRun,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Wrap(
        spacing: 8.0,
        runSpacing: 8.0,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _FileBtn(
            icon: Icons.description,
            label: "Text",
            active: state.textPath != null,
            onTap: () => controller.pickText(context),
          ),
          _FileBtn(
            icon: Icons.audio_file,
            label: "Audio",
            active: state.audioPath != null,
            onTap: controller.pickAudio,
          ),
          _FileBtn(
            icon: Icons.translate,
            label: "Dict",
            active: state.dictPath != null,
            onTap: controller.pickDict,
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.play_arrow),
            label: const Text("Align"),
            onPressed:
                (!state.isProcessing &&
                    state.textPath != null &&
                    state.audioPath != null)
                ? onRun
                : null,
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.download),
            label: const Text("Export JSON"),
            onPressed: state.fragments.isNotEmpty
                ? controller.exportJson
                : null,
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.teal,
              side: BorderSide(
                color: state.fragments.isNotEmpty
                    ? Colors.teal
                    : Colors.grey.shade300,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FileBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _FileBtn({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? Colors.teal : Colors.grey;
    return OutlinedButton.icon(
      icon: Icon(icon, size: 18),
      label: Text(label),
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color),
      ),
    );
  }
}
