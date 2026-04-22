import 'package:flutter/material.dart';
import 'package:isochron_cli/isochron_cli.dart';

class FragmentList extends StatefulWidget {
  final List<Fragment> fragments;
  final Duration currentPos;
  final Map<String, String>? rules;
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
    this.rules,
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
  final ScrollController _scrollController = ScrollController();

  // Conditionally increase item height to accommodate 3 lines
  double get _itemHeight => widget.rules != null ? 84.0 : 64.0;

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
    if (!_scrollController.hasClients) return;
    final targetIndex = index > 0 ? index - 1 : 0;
    final idealOffset = targetIndex * _itemHeight;
    final min = _scrollController.position.minScrollExtent;
    final max = _scrollController.position.maxScrollExtent;
    final clampedOffset = idealOffset.clamp(min, max);

    _scrollController.animateTo(
      clampedOffset,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
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
      return const Center(child: Text("No alignment data."));
    }

    final colorScheme = Theme.of(context).colorScheme;

    return ListView.builder(
      controller: _scrollController,
      itemCount: widget.fragments.length,
      itemExtent: _itemHeight,
      itemBuilder: (ctx, i) {
        final f = widget.fragments[i];

        String? transliteratedText;
        if (widget.rules != null) {
          transliteratedText = Transliterator.convert(f.text, widget.rules!);
        }

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
              isThreeLine: transliteratedText != null,

              // --- 1. LEADING (The Circle Number) ---
              leading: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircleAvatar(
                    radius: 10,
                    backgroundColor: f.isPinned
                        ? const Color(0xFFFFC107)
                        : isActive
                        ? colorScheme.primary
                        : colorScheme.surfaceContainerHighest,
                    foregroundColor: f.isPinned
                        ? Colors.black
                        : isActive
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
                  if (f.isPinned) ...[
                    const SizedBox(height: 4),
                    const Icon(Icons.lock, size: 12, color: Color(0xFFFFC107)),
                  ],
                ],
              ),

              // --- 2. TITLE (The Original Text & ID) ---
              title: Row(
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
                    child: Text(
                      f.text, // <--- THIS IS THE ORIGINAL TEXT
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: colorScheme.onSurface),
                    ),
                  ),
                ],
              ),

              // --- 3. SUBTITLE (Transliteration & Timing/Capture) ---
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Transliteration Inject
                  if (transliteratedText != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      transliteratedText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: colorScheme.onSurfaceVariant.withValues(
                          alpha: 0.8,
                        ),
                      ),
                    ),
                  ],
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
