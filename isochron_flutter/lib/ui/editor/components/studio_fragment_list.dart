import 'package:flutter/cupertino.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:isochron_cli/isochron_cli.dart';
import 'package:isochron_flutter/ui/theme/app_theme.dart';

class StudioFragmentList extends StatefulWidget {
  final List<Fragment> fragments;
  final ValueNotifier<Duration> playbackNotifier;
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
    required this.playbackNotifier,
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
  final double _rowHeight = 56.0;
  int _lastActiveIndex = -1;

  @override
  void initState() {
    super.initState();
    // Listen directly to the playhead for auto-scrolling
    widget.playbackNotifier.addListener(_onPlaybackPositionChanged);
  }

  @override
  void dispose() {
    widget.playbackNotifier.removeListener(_onPlaybackPositionChanged);
    _scrollController.dispose();
    super.dispose();
  }

  void _onPlaybackPositionChanged() {
    final newIndex = _getActiveIndex(
      widget.fragments,
      widget.playbackNotifier.value,
    );
    if (newIndex != -1 && newIndex != _lastActiveIndex) {
      _lastActiveIndex = newIndex;
      _scrollToIndex(newIndex);
    }
  }

  int _getActiveIndex(List<Fragment> frags, Duration pos) {
    final ms = pos.inMilliseconds;
    return frags.indexWhere(
      (f) => ms >= (f.realStart * 1000) && ms < (f.realEnd * 1000),
    );
  }

  void _scrollToIndex(int index) {
    if (!_scrollController.hasClients) return;

    // Put the active item exactly at the top (or 1 row down for slight context)
    final targetIndex = index > 0 ? index - 1 : 0;
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
  Widget build(BuildContext context) {
    if (widget.fragments.isEmpty) {
      return Center(
        child: Text(
          "No text fragments available.",
          style: MacosTheme.of(
            context,
          ).typography.callout.copyWith(color: AppTheme.grey(context)),
        ),
      );
    }

    final theme = MacosTheme.of(context);

    return ValueListenableBuilder<Duration>(
      valueListenable: widget.playbackNotifier,
      builder: (context, currentPos, _) {
        return ListView.builder(
          controller: _scrollController,
          itemCount: widget.fragments.length,
          itemExtent: _rowHeight,
          itemBuilder: (ctx, i) {
            final f = widget.fragments[i];
            final hasTime = f.realStart >= 0;

            String? transliteratedText;
            if (widget.rules != null) {
              transliteratedText = Transliterator.convert(
                f.text,
                widget.rules!,
              );
            }

            final isPlaying =
                hasTime &&
                currentPos.inMilliseconds >= (f.realStart * 1000) &&
                currentPos.inMilliseconds < (f.realEnd * 1000);

            final isSelected = widget.selectedIndex == i;

            final bool isHighlighted = isPlaying || (isSelected && !hasTime);

            final macBlue = AppTheme.accent(context);
            final bgColor = isHighlighted
                ? macBlue.withValues(alpha: 0.15)
                : CupertinoColors.transparent;

            final textColor = theme.typography.body.color;
            final subTextColor = AppTheme.grey(context);

            final badgeBgColor = macBlue.withValues(alpha: 0.15);
            final badgeTextColor = macBlue;

            return GestureDetector(
              behavior: HitTestBehavior.opaque,
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
                              color: macBlue,
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
                          // Display the lock independently so the index is never hidden
                          if (f.isPinned) ...[
                            const SizedBox(height: 2),
                            Icon(
                              CupertinoIcons.lock_fill,
                              size: 10,
                              color: AppTheme.warning(context),
                            ),
                          ],
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
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: badgeBgColor,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    f.id!,
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: badgeTextColor,
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
                      width: 180,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (hasTime) ...[
                            Text(
                              "${f.realStart.toStringAsFixed(2)}s ➝ ${f.realEnd.toStringAsFixed(2)}s",
                              style: TextStyle(
                                fontSize: 11,
                                color: subTextColor,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            MacosIconButton(
                              icon: Icon(
                                CupertinoIcons.clear_circled_solid,
                                color: AppTheme.destructive(context),
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
      },
    );
  }
}
