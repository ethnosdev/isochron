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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
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
              Text(
                "First 5 lines (Transliterated):",
                style: textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  // Use a subtle container color that adapts to dark/light
                  color: colorScheme.surfaceContainerHighest,
                  border: Border.all(color: colorScheme.outlineVariant),
                  borderRadius: BorderRadius.circular(8),
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
                        style: textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                          color: colorScheme.onSurfaceVariant,
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
                    Icon(Icons.warning_amber_rounded, color: colorScheme.error),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "Warning: The following characters were found in the full text but are not handled by your dictionary.",
                        style: textTheme.labelLarge?.copyWith(
                          color: colorScheme.error,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  "Select and copy these to add them to your JSON rules:",
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    border: Border.all(
                      color: colorScheme.error.withValues(alpha: 0.5),
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SelectableText(
                    unknownChars.join('  '),
                    style: textTheme.headlineSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
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
            backgroundColor: hasErrors
                ? colorScheme.error
                : colorScheme.primary,
            foregroundColor: hasErrors
                ? colorScheme.onError
                : colorScheme.onPrimary,
          ),
          child: Text(hasErrors ? "Use Anyway" : "Confirm"),
        ),
      ],
    );
  }
}
