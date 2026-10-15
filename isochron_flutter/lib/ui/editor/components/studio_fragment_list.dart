import 'package:flutter/cupertino.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:isochron_cli/isochron_cli.dart';
import 'package:isochron_flutter/ui/theme/app_theme.dart';

class StudioFragmentList extends StatefulWidget {
  final List<Fragment> fragments;
  final ValueNotifier<Duration> playbackNotifier;
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

  Widget _buildStatusBadge(BuildContext context, FragmentStatus status) {
    Color bg;
    Color fg;
    String label;

    switch (status) {
      case FragmentStatus.edited:
        bg = CupertinoColors.systemOrange.withValues(alpha: 0.18);
        fg = CupertinoColors.systemOrange;
        label = "Edited";
        break;
      case FragmentStatus.reviewed:
        bg = CupertinoColors.systemGreen.withValues(alpha: 0.18);
        fg = CupertinoColors.systemGreen;
        label = "Reviewed";
        break;
      case FragmentStatus.auto:
        bg = CupertinoColors.systemBlue.withValues(alpha: 0.15);
        fg = CupertinoColors.systemBlue;
        label = "Auto";
        break;
      case FragmentStatus.legacy:
        return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9.5,
          color: fg,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildConfidenceBadge(BuildContext context, double? conf) {
    if (conf == null) return const SizedBox.shrink();
    Color fg;
    if (conf >= 0.85) {
      fg = CupertinoColors.systemGreen;
    } else if (conf >= 0.60) {
      fg = CupertinoColors.systemOrange;
    } else {
      fg = CupertinoColors.systemRed;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
      decoration: BoxDecoration(
        color: fg.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        "${(conf * 100).toStringAsFixed(0)}%",
        style: TextStyle(
          fontSize: 9.5,
          color: fg,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildFlagBadge(BuildContext context, String flag) {
    Color color;
    String label;
    switch (flag) {
      case 'omitted':
        color = CupertinoColors.systemRed;
        label = "Omitted";
        break;
      case 'not_at_pause':
        color = CupertinoColors.systemOrange;
        label = "No Pause";
        break;
      case 'poor_text_match':
        color = CupertinoColors.systemOrange;
        label = "Poor Match";
        break;
      case 'long_verse':
        color = CupertinoColors.systemPurple;
        label = "Long";
        break;
      case 'short_verse':
        color = CupertinoColors.systemPurple;
        label = "Short";
        break;
      default:
        color = CupertinoColors.systemGrey;
        label = flag;
    }

    return Container(
      margin: const EdgeInsets.only(right: 4),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9,
          color: color,
          fontWeight: FontWeight.bold,
        ),
      ),
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
                              _buildStatusBadge(context, f.status),
                              if (f.status != FragmentStatus.legacy)
                                const SizedBox(width: 6),
                              if (f.confidence != null) ...[
                                _buildConfidenceBadge(context, f.confidence),
                                const SizedBox(width: 6),
                              ],
                              for (final flag in f.flags) ...[
                                _buildFlagBadge(context, flag),
                              ],
                              if (f.warnings.isNotEmpty) ...[
                                MacosTooltip(
                                  message: f.warnings.join('\n'),
                                  child: Icon(
                                    CupertinoIcons.exclamationmark_triangle_fill,
                                    size: 12,
                                    color: CupertinoColors.systemYellow,
                                  ),
                                ),
                                const SizedBox(width: 6),
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
                          ] else if (f.flags.contains('omitted')) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: CupertinoColors.systemRed
                                    .withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                "Omitted",
                                style: TextStyle(
                                  fontSize: 10,
                                  color: CupertinoColors.systemRed,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            PushButton(
                              controlSize: ControlSize.small,
                              secondary: true,
                              onPressed: () => widget.onCapture(i),
                              child: const Text("Capture"),
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
