import 'package:flutter/material.dart';

class TextPreviewDialog extends StatefulWidget {
  final String filename;
  final List<String> previewLines;

  const TextPreviewDialog({
    super.key,
    required this.filename,
    required this.previewLines,
  });

  @override
  State<TextPreviewDialog> createState() => _TextPreviewDialogState();
}

class _TextPreviewDialogState extends State<TextPreviewDialog> {
  bool _hasIds = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text("Import ${widget.filename}"),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Preview of first 5 lines:",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainer,
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: widget.previewLines
                    .map(
                      (l) => Text(
                        l,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
            const SizedBox(height: 16),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text("Lines start with an ID prefix?"),
              subtitle: const Text("e.g. '40001001 Text...'"),
              value: _hasIds,
              onChanged: (val) => setState(() => _hasIds = val ?? false),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null), // Cancel
          child: const Text("Cancel"),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_hasIds),
          child: const Text("Import"),
        ),
      ],
    );
  }
}
