import 'package:flutter/cupertino.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:isochron_flutter/ui/theme/app_theme.dart';

abstract class MacosContextMenuEntry {
  const MacosContextMenuEntry();
}

class MacosContextMenuItem extends MacosContextMenuEntry {
  final String title;
  final IconData? icon;
  final String? shortcut;
  final bool isDestructive;
  final bool enabled;
  final VoidCallback? onTap;

  const MacosContextMenuItem({
    required this.title,
    this.icon,
    this.shortcut,
    this.isDestructive = false,
    this.enabled = true,
    this.onTap,
  });
}

class MacosContextMenuDivider extends MacosContextMenuEntry {
  const MacosContextMenuDivider();
}

Future<void> showMacosContextMenu({
  required BuildContext context,
  required Offset position,
  required List<MacosContextMenuEntry> items,
  double width = 210,
}) {
  return showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Dismiss Context Menu',
    barrierColor: CupertinoColors.transparent,
    transitionDuration: const Duration(milliseconds: 100),
    pageBuilder: (dialogContext, animation, secondaryAnimation) {
      final mediaQuery = MediaQuery.of(dialogContext);
      final screenSize = mediaQuery.size;

      // Estimate menu height: ~26px per item, ~9px per divider, 8px padding
      double estimatedHeight = 8.0;
      for (final it in items) {
        if (it is MacosContextMenuDivider) {
          estimatedHeight += 9.0;
        } else {
          estimatedHeight += 26.0;
        }
      }

      double left = position.dx;
      double top = position.dy;

      if (left + width > screenSize.width - 12) {
        left = screenSize.width - width - 12;
      }
      if (left < 12) left = 12;

      if (top + estimatedHeight > screenSize.height - 12) {
        top = screenSize.height - estimatedHeight - 12;
      }
      if (top < 12) top = 12;

      final theme = MacosTheme.of(dialogContext);
      final isDark = theme.brightness == Brightness.dark;

      return Stack(
        children: [
          Positioned(
            left: left,
            top: top,
            width: width,
            child: FadeTransition(
              opacity: animation,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xE8262626)
                      : const Color(0xF6F2F2F4),
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(
                    color: isDark
                        ? const Color(0x33FFFFFF)
                        : const Color(0x22000000),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: CupertinoColors.black.withValues(alpha: 0.22),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: items.map((entry) {
                    if (entry is MacosContextMenuDivider) {
                      return Container(
                        height: 1,
                        margin: const EdgeInsets.symmetric(
                          vertical: 4,
                          horizontal: 4,
                        ),
                        color: theme.dividerColor,
                      );
                    }
                    final item = entry as MacosContextMenuItem;
                    return _ContextMenuItemRow(item: item);
                  }).toList(),
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
}

class _ContextMenuItemRow extends StatefulWidget {
  final MacosContextMenuItem item;

  const _ContextMenuItemRow({required this.item});

  @override
  State<_ContextMenuItemRow> createState() => _ContextMenuItemRowState();
}

class _ContextMenuItemRowState extends State<_ContextMenuItemRow> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final enabled = item.enabled;
    final theme = MacosTheme.of(context);
    final accent = AppTheme.accent(context);

    Color textColor;
    if (!enabled) {
      textColor = AppTheme.grey(context).withValues(alpha: 0.5);
    } else if (_isHovered) {
      textColor = CupertinoColors.white;
    } else if (item.isDestructive) {
      textColor = AppTheme.destructive(context);
    } else {
      textColor = theme.typography.body.color ?? CupertinoColors.black;
    }

    return MouseRegion(
      onEnter: enabled ? (_) => setState(() => _isHovered = true) : null,
      onExit: enabled ? (_) => setState(() => _isHovered = false) : null,
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled
            ? () {
                Navigator.of(context).pop();
                item.onTap?.call();
              }
            : null,
        child: Container(
          height: 24,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: _isHovered && enabled ? accent : CupertinoColors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            children: [
              if (item.icon != null) ...[
                Icon(
                  item.icon,
                  size: 13,
                  color: textColor,
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w400,
                    color: textColor,
                  ),
                ),
              ),
              if (item.shortcut != null) ...[
                const SizedBox(width: 8),
                Text(
                  item.shortcut!,
                  style: TextStyle(
                    fontSize: 11,
                    color: _isHovered && enabled
                        ? CupertinoColors.white.withValues(alpha: 0.8)
                        : AppTheme.grey(context),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
