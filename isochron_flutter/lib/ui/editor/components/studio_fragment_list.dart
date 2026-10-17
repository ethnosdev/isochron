import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:isochron_cli/isochron_cli.dart';
import 'package:isochron_flutter/ui/models/app_state.dart';
import 'package:isochron_flutter/ui/theme/app_theme.dart';
import 'package:isochron_flutter/ui/workspace/components/inline_text_editor.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

class StudioFragmentList extends StatefulWidget {
  final List<Fragment> fragments;
  final ValueNotifier<Duration> playbackNotifier;
  final int? selectedIndex;
  final FragmentFilter filter;

  final Function(int) onSelect;
  final Function(int) onJumpTo;
  final Function(int) onDoubleTap;
  final Function(int) onCapture;
  final Function(int) onClear;
  final Function(int)? onToggleReviewed;
  final Function(int, String)? onEditText;

  const StudioFragmentList({
    super.key,
    required this.fragments,
    required this.playbackNotifier,
    this.selectedIndex,
    this.filter = FragmentFilter.all,
    required this.onSelect,
    required this.onJumpTo,
    required this.onDoubleTap,
    required this.onCapture,
    required this.onClear,
    this.onToggleReviewed,
    this.onEditText,
  });

  @override
  State<StudioFragmentList> createState() => _StudioFragmentListState();
}

class _StudioFragmentListState extends State<StudioFragmentList> {
  final ItemScrollController _itemScrollController = ItemScrollController();
  final ItemPositionsListener _itemPositionsListener =
      ItemPositionsListener.create();
  int _lastActiveIndex = -1;
  DateTime? _lastUserScrollTime;
  int? _editingFragmentIndex;

  @override
  void initState() {
    super.initState();
    widget.playbackNotifier.addListener(_onPlaybackPositionChanged);
  }

  @override
  void dispose() {
    widget.playbackNotifier.removeListener(_onPlaybackPositionChanged);
    super.dispose();
  }

  void _onPlaybackPositionChanged() {
    if (_lastUserScrollTime != null &&
        DateTime.now().difference(_lastUserScrollTime!) <
            const Duration(seconds: 4)) {
      return;
    }

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

  List<int> _computeVisibleIndices() {
    final list = <int>[];
    for (int i = 0; i < widget.fragments.length; i++) {
      final f = widget.fragments[i];
      switch (widget.filter) {
        case FragmentFilter.all:
          list.add(i);
          break;
        case FragmentFilter.unreviewed:
          if (f.status != FragmentStatus.reviewed) {
            list.add(i);
          }
          break;
        case FragmentFilter.flagged:
          if (f.flags.isNotEmpty || f.warnings.isNotEmpty) {
            list.add(i);
          }
          break;
      }
    }
    return list;
  }

  static const double _targetAlignment = 0.15;

  void _scrollToIndex(int trueIndex) {
    if (!_itemScrollController.isAttached) return;
    final visibleIndices = _computeVisibleIndices();
    final listPos = visibleIndices.indexOf(trueIndex);
    if (listPos == -1) return;

    final positions = _itemPositionsListener.itemPositions.value;
    if (positions.isNotEmpty && visibleIndices.isNotEmpty) {
      final lastIndex = visibleIndices.length - 1;
      final lastItemPos =
          positions.where((p) => p.index == lastIndex).firstOrNull;

      if (lastItemPos != null) {
        final currentPos =
            positions.where((p) => p.index == listPos).firstOrNull;
        if (currentPos != null && currentPos.itemLeadingEdge >= 0) {
          if (lastItemPos.itemTrailingEdge > 1.001) {
            final lastItemHeight =
                lastItemPos.itemTrailingEdge - lastItemPos.itemLeadingEdge;
            final alignment = (1.0 - lastItemHeight).clamp(0.0, 1.0);
            _itemScrollController.scrollTo(
              index: lastIndex,
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
              alignment: alignment,
            );
          }
          return;
        }
      }
    }

    _itemScrollController.scrollTo(
      index: listPos,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      alignment: _targetAlignment,
    );
  }

  String _formatTimestamp(double seconds) {
    if (seconds < 0) return "--:--";
    final m = (seconds / 60).floor();
    final s = (seconds % 60).floor();
    final cs = ((seconds % 1) * 100).floor();
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}.${cs.toString().padLeft(2, '0')}';
  }

  Widget _buildStatusBadge(BuildContext context, FragmentStatus status) {
    Color bg;
    Color fg;
    String label;

    switch (status) {
      case FragmentStatus.edited:
        bg = AppTheme.warning(context).withValues(alpha: 0.18);
        fg = AppTheme.warning(context);
        label = "Edited";
        break;
      case FragmentStatus.reviewed:
        bg = AppTheme.success(context).withValues(alpha: 0.18);
        fg = AppTheme.success(context);
        label = "Reviewed";
        break;
      case FragmentStatus.auto:
        bg = AppTheme.accent(context).withValues(alpha: 0.15);
        fg = AppTheme.accent(context);
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
      fg = AppTheme.success(context);
    } else if (conf >= 0.60) {
      fg = AppTheme.warning(context);
    } else {
      fg = AppTheme.destructive(context);
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
        color = AppTheme.destructive(context);
        label = "Omitted";
        break;
      case 'not_at_pause':
        color = AppTheme.warning(context);
        label = "No Pause";
        break;
      case 'poor_text_match':
        color = AppTheme.warning(context);
        label = "Poor Match";
        break;
      case 'long_verse':
        color = AppTheme.accent(context);
        label = "Long";
        break;
      case 'short_verse':
        color = AppTheme.accent(context);
        label = "Short";
        break;
      default:
        color = AppTheme.grey(context);
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
        final visibleIndices = _computeVisibleIndices();
        if (visibleIndices.isEmpty) {
          return Center(
            child: Text(
              "No fragments match the active filter.",
              style: MacosTheme.of(context).typography.callout.copyWith(
                    color: AppTheme.grey(context),
                  ),
            ),
          );
        }

        return Listener(
          behavior: HitTestBehavior.translucent,
          onPointerSignal: (event) {
            if (event is PointerScrollEvent) {
              _lastUserScrollTime = DateTime.now();
            }
          },
          onPointerPanZoomUpdate: (_) {
            _lastUserScrollTime = DateTime.now();
          },
          child: ScrollablePositionedList.builder(
            itemScrollController: _itemScrollController,
            itemPositionsListener: _itemPositionsListener,
            itemCount: visibleIndices.length,
            itemBuilder: (ctx, listIdx) {
              final i = visibleIndices[listIdx];
              final f = widget.fragments[i];
              final hasTime = f.realStart >= 0;

              final isPlaying =
                  hasTime &&
                  currentPos.inMilliseconds >= (f.realStart * 1000) &&
                  currentPos.inMilliseconds < (f.realEnd * 1000);

              final isSelected = widget.selectedIndex == i;

              Color bgColor;
              if (isPlaying && isSelected) {
                bgColor = AppTheme.accent(context).withValues(alpha: 0.22);
              } else if (isPlaying) {
                bgColor = AppTheme.accent(context).withValues(alpha: 0.14);
              } else if (isSelected) {
                bgColor = AppTheme.selectionBg(context);
              } else {
                bgColor = CupertinoColors.transparent;
              }

              final textColor = theme.typography.body.color;
              final subTextColor = AppTheme.grey(context);

              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  if (_editingFragmentIndex != i) {
                    widget.onSelect(i);
                    if (hasTime) widget.onJumpTo(i);
                  }
                },
                onDoubleTap: () {
                  if (hasTime) widget.onDoubleTap(i);
                },
                child: Container(
                  constraints: const BoxConstraints(minHeight: 52.0),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: bgColor,
                    border: Border(
                      left: BorderSide(
                        color: isSelected
                            ? AppTheme.accent(context)
                            : CupertinoColors.transparent,
                        width: 4,
                      ),
                      bottom: BorderSide(color: theme.dividerColor),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // 1. STATUS & INDEX COLUMN (width: 40)
                      SizedBox(
                        width: 40,
                        child: Center(
                          child: isPlaying
                              ? Icon(
                                  CupertinoIcons.speaker_2_fill,
                                  size: 14,
                                  color: AppTheme.accent(context),
                                )
                              : Text(
                                  "${f.index + 1}",
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: subTextColor,
                                    fontWeight: FontWeight.bold,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(width: 8),

                      // 2. UNIFORM LEFT-ALIGNED SCRIPT & METADATA (Expanded)
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Sub-row A: Metadata Header
                            if ((f.id != null && f.id!.isNotEmpty) ||
                                f.status != FragmentStatus.legacy ||
                                f.confidence != null ||
                                f.flags.isNotEmpty ||
                                f.warnings.isNotEmpty) ...[
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  if (f.id != null && f.id!.isNotEmpty) ...[
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AppTheme.accent(context)
                                            .withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        f.id!,
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: AppTheme.accent(context),
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                  ],
                                  if (f.status != FragmentStatus.legacy) ...[
                                    _buildStatusBadge(context, f.status),
                                    const SizedBox(width: 6),
                                  ],
                                  if (f.confidence != null) ...[
                                    _buildConfidenceBadge(
                                      context,
                                      f.confidence,
                                    ),
                                    const SizedBox(width: 6),
                                  ],
                                  for (final flag in f.flags) ...[
                                    _buildFlagBadge(context, flag),
                                  ],
                                  if (f.warnings.isNotEmpty) ...[
                                    MacosTooltip(
                                      message: f.warnings.join('\n'),
                                      child: Icon(
                                        CupertinoIcons
                                            .exclamationmark_triangle_fill,
                                        size: 12,
                                        color: AppTheme.warning(context),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 4),
                            ],

                            // Sub-row B: Primary Transcript Text
                            if (_editingFragmentIndex == i)
                              InlineTextEditor(
                                initialText: f.text,
                                onComplete: (newVal) {
                                  setState(() => _editingFragmentIndex = null);
                                  if (newVal.trim().isNotEmpty &&
                                      newVal != f.text) {
                                    widget.onEditText?.call(i, newVal);
                                  }
                                },
                              )
                            else
                              Text(
                                f.text,
                                style: TextStyle(
                                  color: textColor,
                                  fontSize: 13.5,
                                  height: 1.4,
                                ),
                              ),

                            // Sub-row C: Romanized Text
                            if (f.romanizedText != null) ...[
                              const SizedBox(height: 3),
                              Text(
                                f.romanizedText!,
                                style: TextStyle(
                                  color: AppTheme.romanizedText(context),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),

                      // 3. TIMING & QUICK ACTIONS (width: 210)
                      SizedBox(
                        width: 210,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            if (hasTime) ...[
                              Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    _formatTimestamp(f.realStart),
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      color: subTextColor,
                                      fontFeatures: const [
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                      vertical: 1,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppTheme.grey(context)
                                          .withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                    child: Text(
                                      "${(f.realEnd - f.realStart).toStringAsFixed(1)}s",
                                      style: TextStyle(
                                        fontSize: 9,
                                        color: subTextColor,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(width: 6),
                              MacosTooltip(
                                message: "Edit Text",
                                child: MacosIconButton(
                                  padding: const EdgeInsets.all(4),
                                  boxConstraints: const BoxConstraints(
                                    minHeight: 24,
                                    minWidth: 24,
                                  ),
                                  icon: Icon(
                                    CupertinoIcons.pencil,
                                    color: subTextColor,
                                    size: 14,
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      _editingFragmentIndex = i;
                                    });
                                  },
                                ),
                              ),
                              const SizedBox(width: 2),
                              MacosTooltip(
                                message: f.status == FragmentStatus.reviewed
                                    ? "Mark Unreviewed"
                                    : "Mark Reviewed (R)",
                                child: MacosIconButton(
                                  padding: const EdgeInsets.all(4),
                                  boxConstraints: const BoxConstraints(
                                    minHeight: 24,
                                    minWidth: 24,
                                  ),
                                  icon: Icon(
                                    CupertinoIcons.checkmark_circle_fill,
                                    color: f.status == FragmentStatus.reviewed
                                        ? AppTheme.success(context)
                                        : AppTheme.grey(context)
                                            .withValues(alpha: 0.4),
                                    size: 15,
                                  ),
                                  onPressed: () =>
                                      widget.onToggleReviewed?.call(i),
                                ),
                              ),
                              const SizedBox(width: 2),
                              MacosTooltip(
                                message: "Clear Timing",
                                child: MacosIconButton(
                                  padding: const EdgeInsets.all(4),
                                  boxConstraints: const BoxConstraints(
                                    minHeight: 24,
                                    minWidth: 24,
                                  ),
                                  icon: Icon(
                                    CupertinoIcons.clear_circled_solid,
                                    color: AppTheme.destructive(context),
                                    size: 15,
                                  ),
                                  onPressed: () => widget.onClear(i),
                                ),
                              ),
                            ] else ...[
                              PushButton(
                                controlSize: ControlSize.small,
                                secondary: true,
                                onPressed: () => widget.onCapture(i),
                                child: const Text("Capture (Enter)"),
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
          ),
        );
      },
    );
  }
}
