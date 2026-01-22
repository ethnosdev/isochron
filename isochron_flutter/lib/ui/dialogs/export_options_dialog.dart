import 'package:flutter/material.dart';

class ExportOptionsDialog extends StatefulWidget {
  final String defaultRecordingId;

  const ExportOptionsDialog({super.key, required this.defaultRecordingId});

  @override
  State<ExportOptionsDialog> createState() => _ExportOptionsDialogState();
}

class _ExportOptionsDialogState extends State<ExportOptionsDialog> {
  late TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.defaultRecordingId);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Export CSV"),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text("Enter the Recording ID to appear in the CSV:"),
          const SizedBox(height: 16),
          TextField(
            controller: _ctrl,
            decoration: const InputDecoration(
              labelText: "Recording ID",
              border: OutlineInputBorder(),
              hintText: "e.g. MAT_01",
            ),
            autofocus: true,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("Cancel"),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _ctrl.text),
          child: const Text("Export"),
        ),
      ],
    );
  }
}
