import 'package:flutter/material.dart';
import 'package:isochron_cli/isochron_cli.dart';

class FragmentList extends StatefulWidget {
  final List<Fragment> fragments;
  final Duration currentPos;
  final Function(int) onJumpTo;
  final Function(int) onDoubleTap;

  const FragmentList({
    super.key,
    required this.fragments,
    required this.currentPos,
    required this.onJumpTo,
    required this.onDoubleTap,
  });

  @override
  State<FragmentList> createState() => _FragmentListState();
}

class _FragmentListState extends State<FragmentList> {
  final ScrollController _scrollController = ScrollController();
  static const double _itemHeight = 64.0;

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
        final isActive =
            widget.currentPos.inMilliseconds >= (f.realStart * 1000) &&
            widget.currentPos.inMilliseconds <= (f.realEnd * 1000);

        return Container(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: Theme.of(context).dividerColor),
            ),
            // A beautiful dynamic highlight color for both light/dark mode
            color: isActive
                ? colorScheme.primaryContainer.withValues(alpha: 0.5)
                : null,
          ),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => widget.onJumpTo(i),
            onDoubleTap: () => widget.onDoubleTap(i),
            child: ListTile(
              enabled: true,
              onTap: null,
              dense: true,
              visualDensity: VisualDensity.compact,
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
                      f.text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      // Removed hardcoded black so it turns white in Dark Mode automatically
                      style: TextStyle(color: colorScheme.onSurface),
                    ),
                  ),
                ],
              ),
              subtitle: Text(
                "${f.realStart.toStringAsFixed(2)}s  ➝  ${f.realEnd.toStringAsFixed(2)}s",
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              trailing: isActive
                  ? Icon(Icons.volume_up, size: 16, color: colorScheme.primary)
                  : null,
            ),
          ),
        );
      },
    );
  }
}
