import 'package:flutter/material.dart';
import 'package:isochron_cli/isochron_cli.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';


class FragmentList extends StatefulWidget {
  final List<Fragment> fragments;
  final Duration currentPos;
  final int? selectedIndex;
  final Function(int) onJumpTo;
  final Function(int) onDoubleTap;
  final Function(int) onSelect;
  final Function(int) onCapture;
  final Function(int) onClear;

  const FragmentList({
    super.key,
    required this.fragments,
    required this.currentPos,
    this.selectedIndex,
    required this.onJumpTo,
    required this.onDoubleTap,
    required this.onSelect,
    required this.onCapture,
    required this.onClear,
  });

  @override
  State<FragmentList> createState() => _FragmentListState();
}

class _FragmentListState extends State<FragmentList> {
  final ItemScrollController _itemScrollController = ItemScrollController();
  final ItemPositionsListener _itemPositionsListener = ItemPositionsListener.create();

  @override
  void didUpdateWidget(FragmentList oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldIndex = _getActiveIndex(oldWidget.fragments, oldWidget.currentPos);
    final newIndex = _getActiveIndex(widget.fragments, widget.currentPos);

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
    if (!_itemScrollController.isAttached) return;
    _itemScrollController.scrollTo(
      index: index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      alignment: 0.15,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.fragments.isEmpty) {
      return const Center(child: Text("No alignment data."));
    }

    final colorScheme = Theme.of(context).colorScheme;

    return ScrollablePositionedList.builder(
      itemScrollController: _itemScrollController,
      itemPositionsListener: _itemPositionsListener,
      itemCount: widget.fragments.length,
      itemBuilder: (ctx, i) {
        final f = widget.fragments[i];

        final isActive =
            f.realStart >= 0 &&
            widget.currentPos.inMilliseconds >= (f.realStart * 1000) &&
            widget.currentPos.inMilliseconds <= (f.realEnd * 1000);

        final isSelected = widget.selectedIndex == i;
        final hasTime = f.realStart >= 0;

        return Container(
          decoration: BoxDecoration(
            border: Border(
              // Change border color if selected for capture
              left: isSelected
                  ? BorderSide(color: colorScheme.primary, width: 4)
                  : BorderSide.none,
              bottom: BorderSide(color: Theme.of(context).dividerColor),
            ),
            color: isActive
                ? colorScheme.primaryContainer.withValues(alpha: 0.5)
                : isSelected
                ? colorScheme
                      .surfaceContainerHighest // Highlight selected row
                : null,
          ),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              widget.onSelect(i);
              if (hasTime) widget.onJumpTo(i); // Only jump if it has a time
            },
            onDoubleTap: () {
              if (hasTime) widget.onDoubleTap(i);
            },
            child: ListTile(
              enabled: true,
              onTap: null,
              dense: true,
              visualDensity: VisualDensity.compact,

              // --- 1. LEADING (The Circle Number) ---
              leading: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircleAvatar(
                    radius: 10,
                    backgroundColor: isActive
                        ? colorScheme.primary
                        : colorScheme.surfaceContainerHighest,
                    foregroundColor: isActive
                        ? colorScheme.onPrimary
                        : colorScheme.onSurfaceVariant,
                    child: Text(
                      "${f.index}",
                      style: const TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),

              // --- 2. TITLE (The Original Text & ID & Romanized) ---
              title: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (f.id != null && f.id!.isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainer,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: colorScheme.outlineVariant),
                      ),
                      child: Text(
                        f.id!,
                        style: TextStyle(
                          fontSize: 11,
                          color: colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          f.text, // <--- THIS IS THE ORIGINAL TEXT
                          style: TextStyle(
                            color: colorScheme.onSurface,
                            height: 1.35,
                          ),
                        ),
                        if (f.romanizedText != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            f.romanizedText!,
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w500,
                              color: colorScheme.onSurface,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),

              // --- 3. SUBTITLE (Timing/Capture) ---
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 4),

                  // Timing Data OR Capture Button
                  if (hasTime)
                    Row(
                      children: [
                        Text(
                          "${f.realStart.toStringAsFixed(2)}s  ➝  ${f.realEnd.toStringAsFixed(2)}s",
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(width: 8),
                        InkWell(
                          onTap: () => widget.onClear(i),
                          child: Icon(
                            Icons.close,
                            size: 14,
                            color: colorScheme.error,
                          ),
                        ),
                      ],
                    )
                  else
                    ElevatedButton.icon(
                      icon: const Icon(Icons.timer, size: 14),
                      label: const Text("Capture"),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 0,
                        ),
                        minimumSize: const Size(80, 24),
                        textStyle: const TextStyle(fontSize: 12),
                      ),
                      onPressed: () => widget.onCapture(i),
                    ),
                ],
              ),
              trailing: isActive && hasTime
                  ? Icon(Icons.volume_up, size: 16, color: colorScheme.primary)
                  : null,
            ),
          ),
        );
      },
    );
  }
}
