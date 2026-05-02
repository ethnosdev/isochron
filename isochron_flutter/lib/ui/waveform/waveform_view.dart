import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:isochron_flutter/ui/app_manager.dart';
import 'package:isochron_flutter/ui/models/app_state.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:isochron_cli/isochron_cli.dart';
import 'waveform_painter.dart';

class WaveformView extends StatefulWidget {
  final AppManager controller;
  final AppState state;
  final ScrollController scrollController;
  final ValueNotifier<Duration> playbackNotifier;

  const WaveformView({
    super.key,
    required this.controller,
    required this.state,
    required this.scrollController,
    required this.playbackNotifier,
  });

  @override
  State<WaveformView> createState() => _WaveformViewState();
}

class _WaveformViewState extends State<WaveformView> {
  int? _dragIndex;
  bool _dragStart = true;
  static const double _hPadding = 40.0;
  SystemMouseCursor _cursor = SystemMouseCursors.basic;
  static const double _hoverThresholdPx = 10.0;

  @override
  void initState() {
    super.initState();
    widget.playbackNotifier.addListener(_autoScrollOnPlayback);
  }

  @override
  void didUpdateWidget(WaveformView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only auto-center if the system changed focus via a double click
    if (oldWidget.state.focusedFragmentIndex !=
            widget.state.focusedFragmentIndex &&
        widget.state.focusedFragmentIndex != null) {
      final idx = widget.state.focusedFragmentIndex!;
      if (idx < widget.state.fragments.length) {
        _centerOnTime(widget.state.fragments[idx].realStart);
      }
    }
  }

  void _centerOnTime(double anchorTime) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!widget.scrollController.hasClients ||
          widget.state.audioDuration.inMilliseconds == 0)
        return;

      final viewportWidth = widget.scrollController.position.viewportDimension;
      final totalDuration = widget.state.audioDuration.inMilliseconds / 1000.0;
      final contentWidth = viewportWidth * widget.state.zoomLevel;

      final targetPixel =
          (anchorTime / totalDuration) * contentWidth + _hPadding;
      final centerOffset = targetPixel - (viewportWidth / 2);

      widget.scrollController.jumpTo(
        centerOffset.clamp(
          0.0,
          widget.scrollController.position.maxScrollExtent,
        ),
      );
    });
  }

  @override
  void dispose() {
    widget.playbackNotifier.removeListener(_autoScrollOnPlayback);
    super.dispose();
  }

  void _autoScrollOnPlayback() {
    if (!widget.scrollController.hasClients ||
        widget.state.audioDuration.inMilliseconds == 0) {
      return;
    }

    // Only auto-scroll if audio is actually playing
    if (!widget.state.isPlaying) return;

    final viewportWidth = widget.scrollController.position.viewportDimension;
    final totalDuration = widget.state.audioDuration.inMilliseconds / 1000.0;
    final contentWidth = viewportWidth * widget.state.zoomLevel;

    final currentSeconds =
        widget.playbackNotifier.value.inMilliseconds / 1000.0;

    // Playhead pixel relative strictly to the audio block
    final playheadContentPixel =
        (currentSeconds / totalDuration) * contentWidth;

    // TRUE absolute pixel position inside the ScrollView (accounting for the 40px left padding)
    final absolutePlayhead = playheadContentPixel + _hPadding;

    final currentScroll = widget.scrollController.offset;

    // If the playhead touches the right edge of the visible screen
    if (absolutePlayhead >= currentScroll + viewportWidth) {
      widget.scrollController.animateTo(
        // Scroll exactly to the content pixel. This makes the visual playhead
        // align perfectly with the 40px left padding boundary on the screen.
        playheadContentPixel.clamp(
          0.0,
          widget.scrollController.position.maxScrollExtent,
        ),
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    } else if (absolutePlayhead < currentScroll) {
      // If playhead jumped backwards out of view
      widget.scrollController.jumpTo(
        (absolutePlayhead - (viewportWidth * 0.5)).clamp(
          0.0,
          widget.scrollController.position.maxScrollExtent,
        ),
      );
    }
  }

  // void _maintainCenterOnZoom() {
  //   if (!widget.scrollController.hasClients ||
  //       widget.state.audioDuration.inMilliseconds == 0) {
  //     return;
  //   }

  //   double anchorTime = 0.0;

  //   if (widget.state.focusedFragmentIndex != null) {
  //     final idx = widget.state.focusedFragmentIndex!;
  //     if (idx < widget.state.fragments.length) {
  //       anchorTime = widget.state.fragments[idx].realStart;
  //     }
  //   } else {
  //     final pos = widget.playbackNotifier.value.inMilliseconds / 1000.0;
  //     final currentFrag = widget.state.fragments.firstWhere(
  //       (f) => pos >= f.realStart && pos <= f.realEnd,
  //       orElse: () => widget.state.fragments.firstWhere(
  //         (f) => f.realStart > pos,
  //         orElse: () => widget.state.fragments.isEmpty
  //             ? Fragment(index: 0, text: "")
  //             : widget.state.fragments.last,
  //       ),
  //     );
  //     anchorTime = currentFrag.realStart;
  //   }

  //   WidgetsBinding.instance.addPostFrameCallback((_) {
  //     if (!widget.scrollController.hasClients) return;

  //     final viewportWidth = widget.scrollController.position.viewportDimension;
  //     final totalDuration = widget.state.audioDuration.inMilliseconds / 1000.0;
  //     final contentWidth = viewportWidth * widget.state.zoomLevel;
  //     final targetPixel = (anchorTime / totalDuration) * contentWidth;
  //     final centerOffset = targetPixel - (viewportWidth / 2);

  //     widget.scrollController.jumpTo(
  //       centerOffset.clamp(
  //         0.0,
  //         widget.scrollController.position.maxScrollExtent,
  //       ),
  //     );
  //   });
  // }

  @override
  Widget build(BuildContext context) {
    final wf = widget.state.waveform;
    if (wf == null) {
      return Center(
        child: Text(
          "Processing Waveform...",
          style: MacosTheme.of(context).typography.callout,
        ),
      );
    }

    return LayoutBuilder(
      builder: (ctx, constraints) {
        final totalSec = widget.state.audioDuration.inMilliseconds / 1000.0;
        if (totalSec <= 0) return const SizedBox();

        final viewportWidth = constraints.maxWidth;
        final contentWidth = viewportWidth * widget.state.zoomLevel;
        final fullPainterWidth = contentWidth + (_hPadding * 2);

        final theme = MacosTheme.of(context);

        // --- HELPER: Handles the math for zooming anchored to the mouse ---
        void applyZoom(double zoomDelta, double viewportX) {
          if (zoomDelta == 0) return;

          final currentZoom = widget.state.zoomLevel;
          final newZoom = (currentZoom - zoomDelta).clamp(1.0, 500.0);

          if (newZoom != currentZoom) {
            final absoluteX = widget.scrollController.offset + viewportX;
            final effectiveX = absoluteX - _hPadding;
            final timeAtMouse = (effectiveX / contentWidth) * totalSec;

            widget.controller.setZoom(newZoom);

            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!widget.scrollController.hasClients) return;

              final newContentWidth = viewportWidth * newZoom;
              final newEffectiveX = (timeAtMouse / totalSec) * newContentWidth;
              final newAbsoluteX = newEffectiveX + _hPadding;

              final newScrollOffset = newAbsoluteX - viewportX;
              widget.scrollController.jumpTo(
                newScrollOffset.clamp(
                  0.0,
                  widget.scrollController.position.maxScrollExtent,
                ),
              );
            });
          }
        }

        // --- HELPER: Handles the math for horizontal panning ---
        void applyPan(double panDelta) {
          if (panDelta == 0) return;
          final currentOffset = widget.scrollController.offset;
          widget.scrollController.jumpTo(
            (currentOffset + panDelta).clamp(
              0.0,
              widget.scrollController.position.maxScrollExtent,
            ),
          );
        }

        return Listener(
          behavior: HitTestBehavior.opaque,

          // 1. STANDARD MOUSE WHEELS
          onPointerSignal: (event) {
            if (event is PointerScrollEvent) {
              final keys = HardwareKeyboard.instance.logicalKeysPressed;
              final isControl =
                  keys.contains(LogicalKeyboardKey.controlLeft) ||
                  keys.contains(LogicalKeyboardKey.controlRight) ||
                  keys.contains(LogicalKeyboardKey.metaLeft) ||
                  keys.contains(LogicalKeyboardKey.metaRight);

              // Mouse wheel up/down (dy) or holding control = ZOOM
              if (isControl ||
                  event.scrollDelta.dy.abs() > event.scrollDelta.dx.abs()) {
                applyZoom(event.scrollDelta.dy * 0.02, event.localPosition.dx);
              } else {
                applyPan(event.scrollDelta.dx);
              }
            }
          },

          // 2. MAC TRACKPADS (Two-finger swipe & Pinch)
          onPointerPanZoomUpdate: (event) {
            final keys = HardwareKeyboard.instance.logicalKeysPressed;
            final isControl =
                keys.contains(LogicalKeyboardKey.controlLeft) ||
                keys.contains(LogicalKeyboardKey.controlRight) ||
                keys.contains(LogicalKeyboardKey.metaLeft) ||
                keys.contains(LogicalKeyboardKey.metaRight);

            // Native Pinch-to-Zoom
            if (event.scale != 1.0) {
              // scale > 1.0 means zooming in
              final zoomDelta = (1.0 - event.scale) * 2.0;
              applyZoom(zoomDelta, event.localPosition.dx);
            }
            // Vertical 2-finger swipe OR holding control = ZOOM
            else if (isControl ||
                event.panDelta.dy.abs() > event.panDelta.dx.abs()) {
              applyZoom(event.panDelta.dy * 0.05, event.localPosition.dx);
            }
            // Horizontal 2-finger swipe = PAN
            else if (event.panDelta.dx.abs() > 0) {
              // Trackpad panDelta is inverted relative to scrollDelta
              applyPan(-event.panDelta.dx);
            }
          },

          child: MacosScrollbar(
            controller: widget.scrollController,
            child: SingleChildScrollView(
              controller: widget.scrollController,
              scrollDirection: Axis.horizontal,
              // We take total control of trackpad events, so disable native physics
              physics: const NeverScrollableScrollPhysics(),
              child: MouseRegion(
                cursor: _cursor,
                hitTestBehavior: HitTestBehavior.opaque,
                onHover: (event) => _handleHover(
                  event.localPosition.dx,
                  contentWidth,
                  totalSec,
                ),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (d) =>
                      _handleTap(d.localPosition.dx, contentWidth, totalSec),
                  onDoubleTapDown: (d) => _handleDoubleTap(
                    d.localPosition.dx,
                    contentWidth,
                    totalSec,
                  ),
                  onSecondaryTapDown: (d) => _handleRightClick(
                    d.localPosition.dx,
                    contentWidth,
                    totalSec,
                  ),
                  onHorizontalDragStart: (d) => _handleDragStart(
                    d.localPosition.dx,
                    contentWidth,
                    totalSec,
                  ),
                  onHorizontalDragUpdate: (d) => _handleDragUpdate(
                    d.localPosition.dx,
                    contentWidth,
                    totalSec,
                  ),
                  onHorizontalDragEnd: (_) => setState(() {
                    _dragIndex = null;
                    _cursor = SystemMouseCursors.basic;
                  }),
                  child: Stack(
                    children: [
                      ValueListenableBuilder<Duration>(
                        valueListenable: widget.playbackNotifier,
                        builder: (context, currentPos, _) {
                          return CustomPaint(
                            size: Size(fullPainterWidth, constraints.maxHeight),
                            painter: IsochronWaveformPainter(
                              waveform: wf,
                              fragments: widget.state.fragments,
                              playbackPosSeconds:
                                  currentPos.inMilliseconds / 1000.0,
                              totalSeconds: totalSec,
                              zoomLevel: widget.state.zoomLevel,
                              accentColor: theme.primaryColor,
                              waveColor: CupertinoColors.systemGrey.withValues(
                                alpha: 0.5,
                              ),
                              playheadColor: CupertinoColors.destructiveRed,
                              contentWidth: contentWidth,
                              padding: _hPadding,
                            ),
                          );
                        },
                      ),
                      for (final f in widget.state.fragments)
                        if (f.isPinned)
                          Positioned(
                            left:
                                (f.realStart + f.realEnd) /
                                    2 /
                                    totalSec *
                                    contentWidth +
                                _hPadding -
                                8,
                            top: 4,
                            child: const Icon(
                              CupertinoIcons.lock_fill,
                              size: 14,
                              color: CupertinoColors.systemYellow,
                            ),
                          ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _handleHover(double x, double contentWidth, double totalSec) {
    if (_dragIndex != null) {
      if (_cursor != SystemMouseCursors.resizeLeftRight) {
        setState(() => _cursor = SystemMouseCursors.resizeLeftRight);
      }
      return;
    }

    final hoverTime = _pxToSeconds(x, contentWidth, totalSec);
    int? hoveredIdx;

    for (final f in widget.state.fragments) {
      if (f.realStart < 0) continue;
      if (hoverTime >= f.realStart && hoverTime <= f.realEnd) {
        hoveredIdx = f.index;
        break;
      }
    }
    widget.controller.setHoveredFragmentIndex(hoveredIdx);

    final double thresholdSeconds =
        (_hoverThresholdPx / contentWidth) * totalSec;
    bool isNearBoundary = false;

    for (final f in widget.state.fragments) {
      if (f.isPinned || f.realStart < 0) continue;
      if ((f.realStart - hoverTime).abs() < thresholdSeconds ||
          (f.realEnd - hoverTime).abs() < thresholdSeconds) {
        isNearBoundary = true;
        break;
      }
    }

    final newCursor = isNearBoundary
        ? SystemMouseCursors.resizeLeftRight
        : SystemMouseCursors.basic;

    if (_cursor != newCursor) {
      setState(() => _cursor = newCursor);
    }
  }

  void _handleSeek(double x, double contentWidth, double totalSec) {
    final clickedTime = _pxToSeconds(x, contentWidth, totalSec);
    if (clickedTime < 0 || clickedTime > totalSec) return;
    widget.controller.seekTo(
      Duration(milliseconds: (clickedTime * 1000).toInt()),
    );
  }

  void _handleTap(double x, double contentWidth, double totalSec) =>
      _handleSeek(x, contentWidth, totalSec);

  void _handleDoubleTap(double x, double contentWidth, double totalSec) {
    for (final f in widget.state.fragments) {
      if (f.realStart < 0) continue;
      final fragStartPx = (f.realStart / totalSec) * contentWidth + _hPadding;
      final fragEndPx = (f.realEnd / totalSec) * contentWidth + _hPadding;
      if (x >= fragStartPx && x <= fragEndPx) {
        widget.controller.toggleFragmentPin(f.index);
        return;
      }
    }
  }

  void _handleRightClick(double x, double contentWidth, double totalSec) {
    final time = _pxToSeconds(x, contentWidth, totalSec);
    final double thresholdSeconds =
        (_hoverThresholdPx / contentWidth) * totalSec;

    for (var f in widget.state.fragments) {
      if (f.realStart < 0 || f.isPinned) continue;
      if ((f.realStart - time).abs() < thresholdSeconds) {
        widget.controller.clearFragmentTiming(f.index);
        return;
      }
    }
  }

  void _handleDragStart(double x, double contentWidth, double totalSec) {
    final time = _pxToSeconds(x, contentWidth, totalSec);
    final pixelsPerSecond = contentWidth / totalSec;
    final thresholdSec = 15.0 / pixelsPerSecond;

    final pinnedPositions = <double>{};
    for (final f in widget.state.fragments) {
      if (f.isPinned && f.realStart >= 0) {
        pinnedPositions.add(f.realStart);
        pinnedPositions.add(f.realEnd);
      }
    }

    bool isNearPinned(double t) =>
        pinnedPositions.any((p) => (p - t).abs() < thresholdSec);

    for (var f in widget.state.fragments) {
      if (f.isPinned || f.realStart < 0) continue;

      if ((f.realStart - time).abs() < thresholdSec &&
          !isNearPinned(f.realStart)) {
        setState(() {
          _dragIndex = f.index;
          _dragStart = true;
        });
        return;
      }
      if ((f.realEnd - time).abs() < thresholdSec && !isNearPinned(f.realEnd)) {
        setState(() {
          _dragIndex = f.index;
          _dragStart = false;
        });
        return;
      }
    }
  }

  void _handleDragUpdate(double x, double contentWidth, double totalSec) {
    if (_dragIndex == null) return;
    final time = _pxToSeconds(x, contentWidth, totalSec).clamp(0.0, totalSec);
    final frag = widget.state.fragments.firstWhere(
      (f) => f.index == _dragIndex,
    );

    if (_dragStart) {
      widget.controller.updateFragment(_dragIndex!, time, frag.realEnd);
    } else {
      widget.controller.updateFragment(_dragIndex!, frag.realStart, time);
    }
  }

  double _pxToSeconds(double x, double contentWidth, double totalSeconds) {
    final effectiveX = x - _hPadding;
    final pct = effectiveX / contentWidth;
    return (pct * totalSeconds);
  }
}
