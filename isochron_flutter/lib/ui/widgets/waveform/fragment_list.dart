import 'package:flutter/material.dart';
import 'package:isochron_cli/isochron_cli.dart';

class FragmentList extends StatefulWidget {
  final List<Fragment> fragments;
  final Duration currentPos;
  final Function(int) onJumpTo;

  const FragmentList({
    super.key,
    required this.fragments,
    required this.currentPos,
    required this.onJumpTo,
  });

  @override
  State<FragmentList> createState() => _FragmentListState();
}

class _FragmentListState extends State<FragmentList> {
  final ScrollController _scrollController = ScrollController();

  // Standard height for a dense, two-line ListTile
  static const double _itemHeight = 64.0;

  @override
  void didUpdateWidget(FragmentList oldWidget) {
    super.didUpdateWidget(oldWidget);

    // 1. Calculate which index was active before
    final oldIndex = _getActiveIndex(oldWidget.fragments, oldWidget.currentPos);

    // 2. Calculate which index is active now
    final newIndex = _getActiveIndex(widget.fragments, widget.currentPos);

    // 3. If the active index changed, scroll to the new one
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

    // 1. Target the previous item to keep context
    final targetIndex = index > 0 ? index - 1 : 0;

    // 2. Calculate ideal pixel offset
    final idealOffset = targetIndex * _itemHeight;

    // 3. Get physical limits of the scroll view
    final min = _scrollController.position.minScrollExtent;
    final max = _scrollController.position.maxScrollExtent;

    // 4. Clamp the offset so we don't try to scroll past the bottom
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

    // We use ListView.builder with itemExtent instead of separated.
    // itemExtent enforces fixed height, allowing precise scrolling.
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
          // Simulate the Divider using a bottom border
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
            color: isActive ? Colors.teal.withOpacity(0.1) : null,
          ),
          child: ListTile(
            dense: true,
            // Remove default content padding to fit the fixed height better if needed
            visualDensity: VisualDensity.compact,
            selected: isActive,
            selectedTileColor: Colors.transparent, // Handled by Container
            leading: CircleAvatar(
              radius: 12,
              backgroundColor: isActive ? Colors.teal : Colors.grey.shade300,
              foregroundColor: isActive ? Colors.white : Colors.black87,
              child: Text(
                "${f.index}",
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            title: Text(
              f.text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            subtitle: Text(
              "${f.realStart.toStringAsFixed(2)}s  ➝  ${f.realEnd.toStringAsFixed(2)}s",
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            trailing: isActive
                ? const Icon(Icons.volume_up, size: 16, color: Colors.teal)
                : null,
            onTap: () => widget.onJumpTo(i),
          ),
        );
      },
    );
  }
}
