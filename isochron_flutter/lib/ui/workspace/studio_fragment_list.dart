import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart'; // Needed for ListView/ScrollController
import 'package:macos_ui/macos_ui.dart';
import 'package:isochron_cli/isochron_cli.dart';

class StudioFragmentList extends StatefulWidget {
  final List<Fragment> fragments;
  final Duration currentPos;
  final Map<String, String>? rules;
  final int? selectedIndex;

  final Function(int) onSelect;
  final Function(int) onJumpTo;
  final Function(int) onDoubleTap;
  final Function(int) onCapture;
  final Function(int) onClear;

  const StudioFragmentList({
    super.key,
    required this.fragments,
    required this.currentPos,
    this.rules,
    this.selectedIndex,
    required this.onSelect,
    required this.onJumpTo,
    required this.onDoubleTap,
    required this.onCapture,
    required this.onClear,
  });

  @override
  State<StudioFragmentList> createState() => _StudioFragmentListState();
}

class _StudioFragmentListState extends State<StudioFragmentList> {
  final ScrollController _scrollController = ScrollController();

  // Row height is fixed for native feeling lists
  final double _rowHeight = 56.0;

  @override
  void didUpdateWidget(StudioFragmentList oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldIndex = _getActiveIndex(oldWidget.fragments, oldWidget.currentPos);
    final newIndex = _getActiveIndex(widget.fragments, widget.currentPos);

    // Auto-scroll to the currently playing fragment
    if (newIndex != -1 && newIndex != oldIndex) {
      _scrollToIndex(newIndex);
    }
  }

  int _getActiveIndex(List<Fragment> frags, Duration pos) {
    final ms = pos.inMilliseconds;
    return frags.indexWhere(
      (f) => ms >= (f.realStart * 1000) && ms <= (f.realEnd * 1000),
    );
  }

  void _scrollToIndex(int index) {
    if (!_scrollController.hasClients) return;
    final targetIndex = index > 2
        ? index - 2
        : 0; // Keep active item slightly down from top
    final idealOffset = targetIndex * _rowHeight;
    final min = _scrollController.position.minScrollExtent;
    final max = _scrollController.position.maxScrollExtent;

    _scrollController.animateTo(
      idealOffset.clamp(min, max),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.fragments.isEmpty) {
      return Center(
        child: Text(
          "No text fragments available.",
          style: MacosTheme.of(
            context,
          ).typography.callout.copyWith(color: CupertinoColors.systemGrey),
        ),
      );
    }

    final theme = MacosTheme.of(context);

    return ListView.builder(
      controller: _scrollController,
      itemCount: widget.fragments.length,
      itemExtent: _rowHeight,
      itemBuilder: (ctx, i) {
        final f = widget.fragments[i];
        final hasTime = f.realStart >= 0;

        String? transliteratedText;
        if (widget.rules != null) {
          transliteratedText = Transliterator.convert(f.text, widget.rules!);
        }

        final isPlaying =
            hasTime &&
            widget.currentPos.inMilliseconds >= (f.realStart * 1000) &&
            widget.currentPos.inMilliseconds <= (f.realEnd * 1000);

        final isSelected = widget.selectedIndex == i;

        // macOS selection styling:
        final bgColor = isSelected ? theme.primaryColor : Colors.transparent;
        final textColor = isSelected
            ? CupertinoColors.white
            : theme.typography.body.color;
        final subTextColor = isSelected
            ? CupertinoColors.white.withValues(alpha: 0.8)
            : CupertinoColors.systemGrey;

        return GestureDetector(
          onTap: () {
            widget.onSelect(i);
            if (hasTime) widget.onJumpTo(i);
          },
          onDoubleTap: () {
            if (hasTime) widget.onDoubleTap(i);
          },
          child: Container(
            height: _rowHeight,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: bgColor,
              border: Border(bottom: BorderSide(color: theme.dividerColor)),
            ),
            child: Row(
              children: [
                // 1. STATUS & INDEX COLUMN
                SizedBox(
                  width: 32,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (isPlaying)
                        Icon(
                          CupertinoIcons.speaker_2_fill,
                          size: 14,
                          color: isSelected
                              ? CupertinoColors.white
                              : theme.primaryColor,
                        )
                      else if (f.isPinned)
                        Icon(
                          CupertinoIcons.lock_fill,
                          size: 12,
                          color: isSelected
                              ? CupertinoColors.white
                              : CupertinoColors.systemYellow,
                        )
                      else
                        Text(
                          "${f.index}",
                          style: TextStyle(
                            fontSize: 11,
                            color: subTextColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                    ],
                  ),
                ),

                // 2. TEXT COLUMN
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (f.id != null && f.id!.isNotEmpty) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? CupertinoColors.white.withValues(
                                        alpha: 0.2,
                                      )
                                    : CupertinoColors.systemGrey6,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                f.id!,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: textColor,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          Expanded(
                            child: Text(
                              f.text,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: textColor,
                                fontSize: 13,
                                fontWeight: isPlaying
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (transliteratedText != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          transliteratedText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: subTextColor,
                            fontFamily: 'Courier',
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                // 3. TIMING / ACTIONS COLUMN
                SizedBox(
                  width: 140,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (hasTime) ...[
                        Text(
                          "${f.realStart.toStringAsFixed(2)}s ➝ ${f.realEnd.toStringAsFixed(2)}s",
                          style: TextStyle(
                            fontSize: 11,
                            color: subTextColor,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        const SizedBox(width: 8),
                        MacosIconButton(
                          icon: Icon(
                            CupertinoIcons.clear_circled_solid,
                            color: isSelected
                                ? CupertinoColors.white
                                : CupertinoColors.destructiveRed,
                            size: 16,
                          ),
                          onPressed: () => widget.onClear(i),
                        ),
                      ] else ...[
                        PushButton(
                          controlSize: ControlSize.small,
                          secondary: true,
                          onPressed: () => widget.onCapture(i),
                          child: const Text("Capture"),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
