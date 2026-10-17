import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:isochron_flutter/ui/app_manager.dart';
import 'package:isochron_flutter/ui/models/app_state.dart';
import 'package:macos_ui/macos_ui.dart';
import 'waveform_painter.dart';
import 'dart:math' as math;
import 'package:isochron_flutter/ui/theme/app_theme.dart';

class WaveformView extends StatefulWidget {
  final AppManager controller;
  final AppState state;
  final ScrollController scrollController;
  final ValueNotifier<Duration> playbackNotifier;

  static const double hPadding = 40.0;

  static double calculateCenterOffset({
    required double anchorTime,
    required double totalDurationSeconds,
    required double viewportWidth,
    required double zoomLevel,
  }) {
    if (totalDurationSeconds <= 0) return 0.0;
    final contentWidth = viewportWidth * zoomLevel;
    final targetPixel =
        (anchorTime / totalDurationSeconds) * contentWidth + hPadding;
    return targetPixel - (viewportWidth / 2);
  }

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

class _WaveformViewState extends State<WaveformView>
    with TickerProviderStateMixin {
  int? _dragIndex;
  bool _dragStart = true;
  static const double _hPadding = WaveformView.hPadding;
  SystemMouseCursor _cursor = SystemMouseCursors.basic;
  static const double _hoverThresholdPx = 10.0;
  bool _isPanZooming = false;
  late final AnimationController _flingController;
  double _flingVelocity = 0.0;
  VelocityTracker? _panVelocityTracker;

  @override
  void initState() {
    super.initState();
    _flingController = AnimationController.unbounded(vsync: this)
      ..addListener(_handleFlingTick);
    widget.playbackNotifier.addListener(_autoScrollOnPlayback);
  }

  @override
  void didUpdateWidget(WaveformView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Auto-center if the system changed focus via a double click
    if (oldWidget.state.focusedFragmentIndex !=
            widget.state.focusedFragmentIndex &&
        widget.state.focusedFragmentIndex != null) {
      final idx = widget.state.focusedFragmentIndex!;
      if (idx < widget.state.fragments.length) {
        _centerOnTime(widget.state.fragments[idx].realStart);
      }
    } else if (oldWidget.state.fragments != widget.state.fragments) {
      // Timing was edited: if playhead went off screen, move to beginning of view, otherwise don't move
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _ensurePlayheadVisible();
      });
    }
  }

  void _centerOnTime(double anchorTime) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!widget.scrollController.hasClients ||
          widget.state.audioDuration.inMilliseconds == 0) {
        return;
      }

      final viewportWidth = widget.scrollController.position.viewportDimension;
      final totalDuration = widget.state.audioDuration.inMilliseconds / 1000.0;
      final centerOffset = WaveformView.calculateCenterOffset(
        anchorTime: anchorTime,
        totalDurationSeconds: totalDuration,
        viewportWidth: viewportWidth,
        zoomLevel: widget.state.zoomLevel,
      );

      _stopFling();
      final target = centerOffset.clamp(
        0.0,
        widget.scrollController.position.maxScrollExtent,
      );

      widget.scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _handleFlingTick() {
    if (!widget.scrollController.hasClients) {
      _stopFling();
      return;
    }
    final maxScroll = widget.scrollController.position.maxScrollExtent;
    final current = _flingController.value;
    final target = current.clamp(0.0, maxScroll);
    widget.scrollController.jumpTo(target);
    if ((_flingVelocity < 0 && current <= 0.0) ||
        (_flingVelocity > 0 && current >= maxScroll)) {
      _stopFling();
    }
  }

  void _applyFling(double velocity) {
    if (!widget.scrollController.hasClients ||
        widget.state.audioDuration.inMilliseconds == 0) {
      return;
    }

    _stopFling();

    final currentOffset = widget.scrollController.offset;
    final maxScroll = widget.scrollController.position.maxScrollExtent;

    if ((currentOffset <= 0.0 && velocity < 0) ||
        (currentOffset >= maxScroll && velocity > 0)) {
      return;
    }

    final simulation = ClampingScrollSimulation(
      position: currentOffset,
      velocity: velocity,
      friction: 0.015,
    );

    _flingVelocity = velocity;
    _flingController.animateWith(simulation);
  }

  void _stopFling() {
    if (_flingController.isAnimating) {
      _flingController.stop();
    }
  }

  @override
  void dispose() {
    _stopFling();
    _flingController.dispose();
    widget.playbackNotifier.removeListener(_autoScrollOnPlayback);
    super.dispose();
  }

  void _autoScrollOnPlayback() {
    // Only auto-scroll on playback tick if audio is actively playing
    if (!widget.state.isPlaying) return;
    _ensurePlayheadVisible();
  }

  void _ensurePlayheadVisible() {
    if (!widget.scrollController.hasClients ||
        widget.state.audioDuration.inMilliseconds == 0) {
      return;
    }

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

    // If the playhead goes off screen to the right, align with beginning of waveform view
    if (absolutePlayhead >= currentScroll + viewportWidth) {
      widget.scrollController.animateTo(
        playheadContentPixel.clamp(
          0.0,
          widget.scrollController.position.maxScrollExtent,
        ),
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
    // If the playhead goes off screen to the left, align with beginning of waveform view
    else if (absolutePlayhead < currentScroll) {
      widget.scrollController.animateTo(
        playheadContentPixel.clamp(
          0.0,
          widget.scrollController.position.maxScrollExtent,
        ),
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
    // Otherwise, playhead is within visible screen: do not move the view
  }

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

        // --- HELPER: Perfectly Anchored Exponential Zoom ---
        void applyZoom(double zoomIntensity, double viewportX) {
          if (zoomIntensity == 0) return;
          _stopFling();

          final currentZoom = widget.state.zoomLevel;

          // Exponential zoom ensures the visual scale change feels identical
          // whether you are at 1x or 100x zoom.
          final multiplier = math.exp(zoomIntensity);
          final newZoom = (currentZoom * multiplier).clamp(1.0, 500.0);

          if (newZoom != currentZoom) {
            // 1. Where exactly is the mouse hovering as a percentage of the audio?
            final absoluteX = widget.scrollController.offset + viewportX;
            final effectiveX = absoluteX - _hPadding;
            final hoverRatio = effectiveX / contentWidth;

            // 2. What will the dimensions be AFTER the zoom?
            final newContentWidth = viewportWidth * newZoom;
            final newEffectiveX = hoverRatio * newContentWidth;
            final newAbsoluteX = newEffectiveX + _hPadding;

            // 3. Calculate the offset required to keep that exact spot under the mouse
            final newScrollOffset = newAbsoluteX - viewportX;

            // 4. Predict the new max scroll extent manually so we can jump IMMEDIATELY
            final newMaxScrollExtent =
                (newContentWidth + (_hPadding * 2) - viewportWidth);

            // 5. Apply zoom and jump simultaneously! (No post-frame jitter)
            widget.controller.setZoom(newZoom);
            widget.scrollController.jumpTo(
              newScrollOffset.clamp(0.0, math.max(0.0, newMaxScrollExtent)),
            );
          }
        }

        // --- HELPER: Handles horizontal panning ---
        void applyPan(double panDelta) {
          if (panDelta == 0) return;
          _stopFling();
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
          onPointerDown: (_) => _stopFling(),

          // 1. STANDARD MOUSE WHEELS
          onPointerSignal: (event) {
            if (event is PointerScrollEvent) {
              _stopFling();
              final keys = HardwareKeyboard.instance.logicalKeysPressed;
              final isControl =
                  keys.contains(LogicalKeyboardKey.controlLeft) ||
                  keys.contains(LogicalKeyboardKey.controlRight) ||
                  keys.contains(LogicalKeyboardKey.metaLeft) ||
                  keys.contains(LogicalKeyboardKey.metaRight);

              if (isControl ||
                  event.scrollDelta.dy.abs() > event.scrollDelta.dx.abs()) {
                // Negative dy means scrolling UP. We want wheel up = Zoom IN.
                applyZoom(-event.scrollDelta.dy * 0.01, event.localPosition.dx);
              } else {
                applyPan(event.scrollDelta.dx);
              }
            }
          },

          // 2. MAC TRACKPADS (Two-finger swipe)
          onPointerPanZoomStart: (_) {
            _isPanZooming = true;
            _stopFling();
            _panVelocityTracker =
                VelocityTracker.withKind(PointerDeviceKind.trackpad);
            // Force-drop any marker if user drops a 2nd finger to scroll
            if (_dragIndex != null) {
              setState(() {
                _dragIndex = null;
                _cursor = SystemMouseCursors.basic;
              });
            }
          },
          onPointerPanZoomEnd: (_) {
            _isPanZooming = false;
            final v =
                _panVelocityTracker?.getVelocity().pixelsPerSecond.dx ?? 0.0;
            if (v.abs() > 50.0) {
              _applyFling(-v);
            }
          },
          onPointerPanZoomUpdate: (event) {
            _panVelocityTracker?.addPosition(event.timeStamp, event.position);
            final keys = HardwareKeyboard.instance.logicalKeysPressed;
            final isControl =
                keys.contains(LogicalKeyboardKey.controlLeft) ||
                keys.contains(LogicalKeyboardKey.controlRight) ||
                keys.contains(LogicalKeyboardKey.metaLeft) ||
                keys.contains(LogicalKeyboardKey.metaRight);

            // Vertical 2-finger swipe OR holding control = ZOOM
            if (isControl ||
                event.panDelta.dy.abs() > event.panDelta.dx.abs()) {
              _stopFling();
              _panVelocityTracker = null;
              applyZoom(-event.panDelta.dy * 0.015, event.localPosition.dx);
            }
            // Horizontal 2-finger swipe = PAN
            else if (event.panDelta.dx.abs() > 0) {
              applyPan(-event.panDelta.dx);
            }
          },

          child: MacosScrollbar(
            controller: widget.scrollController,
            child: SingleChildScrollView(
              controller: widget.scrollController,
              scrollDirection: Axis.horizontal,
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
                  onTapUp: (d) =>
                      _handleTap(d.localPosition.dx, contentWidth, totalSec),
                  onSecondaryTapDown: (d) => _handleRightClick(
                    d.localPosition.dx,
                    contentWidth,
                    totalSec,
                  ),
                  onHorizontalDragStart: (d) {
                    if (_isPanZooming) return;
                    _stopFling();
                    _handleDragStart(
                      d.localPosition.dx,
                      contentWidth,
                      totalSec,
                    );
                  },
                  onHorizontalDragUpdate: (d) {
                    if (_isPanZooming) return;
                    if (_dragIndex != null) {
                      _handleDragUpdate(
                        d.localPosition.dx,
                        contentWidth,
                        totalSec,
                      );
                    } else {
                      applyPan(-d.delta.dx);
                    }
                  },
                  onHorizontalDragEnd: (d) {
                    if (_isPanZooming) return;
                    if (_dragIndex != null) {
                      setState(() {
                        _dragIndex = null;
                        _cursor = SystemMouseCursors.basic;
                      });
                      widget.controller.saveProject();
                    } else {
                      final v = d.primaryVelocity ?? 0.0;
                      if (v.abs() > 50.0) {
                        _applyFling(-v);
                      }
                    }
                  },
                  onHorizontalDragCancel: () {
                    if (_dragIndex != null) {
                      setState(() {
                        _dragIndex = null;
                        _cursor = SystemMouseCursors.basic;
                      });
                      widget.controller.saveProject();
                    }
                  },
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
                              accentColor: AppTheme.accent(context),
                              waveColor: AppTheme.grey(context).withValues(
                                alpha: 0.5,
                              ),
                              playheadColor: AppTheme.playhead(context),
                              contentWidth: contentWidth,
                              padding: _hPadding,
                            ),
                          );
                        },
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
      if (f.realStart < 0) continue;
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

  void _handleRightClick(double x, double contentWidth, double totalSec) {
    final time = _pxToSeconds(x, contentWidth, totalSec);
    final double thresholdSeconds =
        (_hoverThresholdPx / contentWidth) * totalSec;

    for (var f in widget.state.fragments) {
      if (f.realStart < 0) continue;
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

    for (var f in widget.state.fragments) {
      if (f.realStart < 0) continue;

      if ((f.realStart - time).abs() < thresholdSec) {
        setState(() {
          _dragIndex = f.index;
          _dragStart = true;
        });
        return;
      }
      if ((f.realEnd - time).abs() < thresholdSec) {
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
