import 'package:flutter/material.dart';

class TransliterationPreviewDialog extends StatelessWidget {
  final String dictName;
  final List<String> previewLines;
  final List<String> unknownChars;

  const TransliterationPreviewDialog({
    super.key,
    required this.dictName,
    required this.previewLines,
    required this.unknownChars,
  });

  @override
  Widget build(BuildContext context) {
    final bool hasErrors = unknownChars.isNotEmpty;

    return AlertDialog(
      title: Text("Preview: $dictName"),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // --- PREVIEW SECTION ---
              const Text(
                "First 5 lines (Transliterated):",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: previewLines.map((line) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 4.0),
                      child: Text(
                        line,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),

              // --- WARNING SECTION ---
              if (hasErrors) ...[
                const SizedBox(height: 24),
                Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      color: Colors.orange.shade800,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "Warning: The following characters were found in the full text but are not handled by your dictionary or standard Latin transliteration.",
                        style: TextStyle(
                          color: Colors.orange.shade900,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  "Select and copy these to add them to your JSON rules:",
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    border: Border.all(color: Colors.orange.shade200),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: SelectableText(
                    unknownChars.join(
                      '  ',
                    ), // Space them out for easy selection
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2.0,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text("Cancel"),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: FilledButton.styleFrom(
            backgroundColor: hasErrors ? Colors.orange.shade800 : Colors.teal,
          ),
          child: Text(hasErrors ? "Use Anyway" : "Confirm"),
        ),
      ],
    );
  }
}
