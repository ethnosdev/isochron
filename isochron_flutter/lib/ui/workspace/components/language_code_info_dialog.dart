import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:isochron_flutter/ui/components/macos_dialogs.dart';
import 'package:isochron_flutter/ui/theme/app_theme.dart';
import 'package:macos_ui/macos_ui.dart';

class LanguageCodeInfoDialog extends StatelessWidget {
  const LanguageCodeInfoDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showAppSheet(
      context: context,
      barrierDismissible: true,
      builder: (_) => const MacosSheet(
        child: SizedBox(
          width: 580,
          height: 520,
          child: LanguageCodeInfoDialog(),
        ),
      ),
    );
  }

  void _openUromanDocs() {
    const url = 'https://github.com/ethnosdev/uroman';
    if (Platform.isMacOS) {
      Process.run('open', [url]);
    } else if (Platform.isWindows) {
      Process.run('start', [url], runInShell: true);
    } else if (Platform.isLinux) {
      Process.run('xdg-open', [url]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = MacosTheme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                CupertinoIcons.globe,
                size: 28,
                color: AppTheme.accent(context),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Language Support in Forced Alignment',
                  style: theme.typography.title2.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Isochron aligns audio to text using Meta MMS-300M and uroman universal romanization. '
            'Text written in the Latin alphabet (e.g. English, Spanish, French, Swahili, Indonesian) '
            'or standard alphabets aligns automatically without needing a language code.',
            style: TextStyle(
              fontSize: 12.5,
              color: theme.typography.body.color?.withValues(alpha: 0.85),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Specifying a 3-letter ISO 639-3 code is only needed for languages that have custom '
            'romanization or pronunciation rules in uroman:',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: theme.typography.body.color,
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF1E1E1E)
                    : const Color(0xFFF7F7F7),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: theme.dividerColor),
              ),
              child: ListView(
                children: [
                  _buildCategory('Greek Script', [
                    ('ell', 'Modern Greek'),
                    ('grc', 'Ancient / Biblical Greek'),
                    ('pnt', 'Pontic Greek'),
                  ], context),
                  const SizedBox(height: 12),
                  _buildCategory('Middle Eastern & Perso-Arabic Scripts', [
                    ('ara', 'Arabic'),
                    ('fas', 'Persian / Farsi'),
                    ('pus', 'Pashto'),
                    ('uig', 'Uyghur'),
                    ('yid', 'Yiddish'),
                  ], context),
                  const SizedBox(height: 12),
                  _buildCategory('Cyrillic Script', [
                    ('rus', 'Russian'),
                    ('ukr', 'Ukrainian'),
                    ('bel', 'Belarusian'),
                    ('bul', 'Bulgarian'),
                    ('mkd', 'Macedonian (mkd / mkd2)'),
                    ('srp', 'Serbian (srp / srp2)'),
                    ('kaz', 'Kazakh'),
                    ('kir', 'Kyrgyz'),
                    ('oss', 'Ossetic'),
                  ], context),
                  const SizedBox(height: 12),
                  _buildCategory('European & Turkic Exceptions', [
                    ('deu', 'German (umlauts / ß expansion)'),
                    ('tur', 'Turkish (dotted / dotless i)'),
                    ('lav', 'Latvian (macron vowels)'),
                    ('lit', 'Lithuanian (nasal / ogonek letters)'),
                    ('eng', 'English (Braille Grade 2 contractions)'),
                  ], context),
                  const SizedBox(height: 12),
                  _buildCategory(
                    'South Asian (Schwa / Inherent Vowel Handling)',
                    [
                      ('san', 'Sanskrit (preserves final inherent "a")'),
                      ('asm', 'Assamese'),
                      ('ben', 'Bengali'),
                      ('guj', 'Gujarati'),
                      ('kas', 'Kashmiri'),
                      ('pan', 'Punjabi'),
                    ],
                    context,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              PushButton(
                controlSize: ControlSize.regular,
                secondary: true,
                onPressed: _openUromanDocs,
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('View uroman Documentation'),
                    SizedBox(width: 4),
                    Icon(CupertinoIcons.arrow_up_right, size: 12),
                  ],
                ),
              ),
              PushButton(
                controlSize: ControlSize.regular,
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCategory(
    String title,
    List<(String, String)> languages,
    BuildContext context,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: languages.map((item) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.accent(context).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '${item.$1} (${item.$2})',
                style: const TextStyle(fontSize: 11.5),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}
