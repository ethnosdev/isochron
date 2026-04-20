import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:isochron_cli/isochron_cli.dart';
import '../home_manager.dart';
import '../models/app_state.dart';
import 'waveform_painter.dart';

class WaveformView extends StatefulWidget {
  final HomeManager controller;
  final AppState state;
  final ScrollController scrollController;

  const WaveformView({
    super.key,
    required this.controller,
    required this.state,
    required this.scrollController,
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
  void didUpdateWidget(WaveformView oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Detect if Zoom Level Changed
    if (oldWidget.state.zoomLevel != widget.state.zoomLevel) {
      _maintainCenterOnZoom();
    }
  }

  void _maintainCenterOnZoom() {
    if (!widget.scrollController.hasClients ||
        widget.state.audioDuration.inMilliseconds == 0) {
      return;
    }

    // 1. Identify the "Anchor Time" we want to keep centered
    double anchorTime = 0.0;

    // Priority A: If explicitly focused (Double Clicked)
    if (widget.state.focusedFragmentIndex != null) {
      final idx = widget.state.focusedFragmentIndex!;
      if (idx < widget.state.fragments.length) {
        anchorTime = widget.state.fragments[idx].realStart;
      }
    }
    // Priority B: The fragment currently under the playhead
    else {
      final pos = widget.state.currentPlaybackPosition.inMilliseconds / 1000.0;
      final currentFrag = widget.state.fragments.firstWhere(
        (f) => pos >= f.realStart && pos <= f.realEnd,
        // Fallback: If between fragments, find the closest upcoming one or just use playhead
        orElse: () => widget.state.fragments.firstWhere(
          (f) => f.realStart > pos,
          orElse: () => widget.state.fragments.isEmpty
              ? Fragment(index: 0, text: "") // Dummy
              : widget.state.fragments.last,
        ),
      );
      // Use the start of that fragment (or 0 if dummy)
      anchorTime = currentFrag.realStart;
    }

    // 2. Perform the Scroll Adjustment after layout calculates the new width
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!widget.scrollController.hasClients) return;

      final viewportWidth = widget.scrollController.position.viewportDimension;
      final totalDuration = widget.state.audioDuration.inMilliseconds / 1000.0;

      // Calculate Content Width based on NEW zoom
      // Note: LayoutBuilder in build() determines width = viewport * zoom
      final contentWidth = viewportWidth * widget.state.zoomLevel;

      // Calculate where the anchor time is in pixels
      final targetPixel = (anchorTime / totalDuration) * contentWidth;

      // Calculate offset to center that pixel
      final centerOffset = targetPixel - (viewportWidth / 2);

      // Jump
      widget.scrollController.jumpTo(
        centerOffset.clamp(
          0.0,
          widget.scrollController.position.maxScrollExtent,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final wf = widget.state.waveform;
    if (wf == null) return const Center(child: Text("Processing Waveform..."));

    return LayoutBuilder(
      builder: (ctx, constraints) {
        final totalSec = widget.state.audioDuration.inMilliseconds / 1000.0;
        if (totalSec <= 0) return const SizedBox();

        final viewportWidth = constraints.maxWidth;

        // The audio itself takes up this much space:
        final contentWidth = viewportWidth * widget.state.zoomLevel;

        // The actual widget size needs room for padding on both sides:
        final fullPainterWidth = contentWidth + (_hPadding * 2);

        return Scrollbar(
          controller: widget.scrollController,
          thumbVisibility: true,
          trackVisibility: true,
          thickness: 10.0,
          radius: const Radius.circular(5.0),
          child: SingleChildScrollView(
            controller: widget.scrollController,
            scrollDirection: Axis.horizontal,
            physics: const ClampingScrollPhysics(),
            child: MouseRegion(
              cursor: _cursor,
              hitTestBehavior: HitTestBehavior.opaque,
              onHover: (event) =>
                  _handleHover(event.localPosition.dx, contentWidth, totalSec),
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
                    CustomPaint(
                      size: Size(fullPainterWidth, constraints.maxHeight),
                      painter: IsochronWaveformPainter(
                        waveform: wf,
                        fragments: widget.state.fragments,
                        playbackPosSeconds:
                            widget
                                .state
                                .currentPlaybackPosition
                                .inMilliseconds /
                            1000.0,
                        totalSeconds: totalSec,
                        zoomLevel: widget.state.zoomLevel,
                        accentColor: Theme.of(context).colorScheme.primary,
                        waveColor: Theme.of(
                          context,
                        ).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                        playheadColor: Theme.of(context).colorScheme.error,
                        contentWidth: contentWidth,
                        padding: _hPadding,
                      ),
                    ),
                    // Lock icon overlays for pinned fragments
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
                            Icons.lock,
                            size: 16,
                            color: Color(0xFFFFC107), // amber
                          ),
                        ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _handleHover(double x, double contentWidth, double totalSec) {
    // 1. If we are currently dragging, keep the resize cursor active
    if (_dragIndex != null) {
      if (_cursor != SystemMouseCursors.resizeLeftRight) {
        setState(() => _cursor = SystemMouseCursors.resizeLeftRight);
      }
      return;
    }

    // 2. Convert the hover X pixel to Audio Time
    final hoverTime = _pxToSeconds(x, contentWidth, totalSec);

    // 3. Track which fragment the cursor is currently inside (for L key)
    int? hoveredIdx;
    for (final f in widget.state.fragments) {
      if (f.realStart < 0) continue; // <--- CHANGED: Skip un-timed fragments

      if (hoverTime >= f.realStart && hoverTime <= f.realEnd) {
        hoveredIdx = f.index;
        break;
      }
    }
    widget.controller.setHoveredFragmentIndex(hoveredIdx);

    // 4. Calculate the time difference equivalent to our pixel threshold.
    final double thresholdSeconds =
        (_hoverThresholdPx / contentWidth) * totalSec;

    bool isNearBoundary = false;

    // 5. Check boundaries to change mouse cursor
    for (final f in widget.state.fragments) {
      if (f.isPinned || f.realStart < 0) continue;

      if ((f.realStart - hoverTime).abs() < thresholdSeconds ||
          (f.realEnd - hoverTime).abs() < thresholdSeconds) {
        isNearBoundary = true;
        break;
      }
    }

    // 6. Update state only if changed to avoid unnecessary rebuilds
    final newCursor = isNearBoundary
        ? SystemMouseCursors.resizeLeftRight
        : SystemMouseCursors.basic;

    if (_cursor != newCursor) {
      setState(() {
        _cursor = newCursor;
      });
    }
  }

  void _handleSeek(double x, double contentWidth, double totalSec) {
    final clickedTime = _pxToSeconds(x, contentWidth, totalSec);
    // Don't seek if we clicked in the padding area outside audio bounds
    if (clickedTime < 0 || clickedTime > totalSec) return;

    final ms = (clickedTime * 1000).toInt();
    widget.controller.seekTo(Duration(milliseconds: ms));
  }

  void _handleTap(double x, double contentWidth, double totalSec) {
    _handleSeek(x, contentWidth, totalSec);
  }

  // Double-tap anywhere inside a fragment region toggles its pin lock.
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
      if (f.realStart < 0 || f.isPinned) continue; // Skip un-timed and pinned

      if ((f.realStart - time).abs() < thresholdSeconds) {
        widget.controller.clearFragmentTiming(f.index);
        return;
      }
    }
  }

  void _handleDragStart(double x, double contentWidth, double totalSec) {
    final time = _pxToSeconds(x, contentWidth, totalSec);

    // Pixels per second calculation needs to account for contentWidth
    final pixelsPerSecond = contentWidth / totalSec;
    // Threshold in seconds (e.g. 15 pixels worth of time)
    final thresholdSec = 15.0 / pixelsPerSecond;

    // Collect all positions that are locked by a pin — no drag handle may
    // land within threshold of these, even if it belongs to a neighbour.
    final pinnedPositions = <double>{};
    for (final f in widget.state.fragments) {
      // SKIP un-timed fragments when checking pins
      if (f.isPinned && f.realStart >= 0) {
        pinnedPositions.add(f.realStart);
        pinnedPositions.add(f.realEnd);
      }
    }

    bool isNearPinned(double t) =>
        pinnedPositions.any((p) => (p - t).abs() < thresholdSec);

    for (var f in widget.state.fragments) {
      // Pinned fragments and un-timed fragments cannot be dragged
      if (f.isPinned || f.realStart < 0) continue; // <--- CHANGED HERE

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

    // Get time from x, but clamp it strictly to audio bounds
    // (allows dragging into the padding area to snap to 0.0 or end)
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

  // Helper: Convert X pixel coordinate to Time
  // Formula: time = ((x - padding) / contentWidth) * duration
  double _pxToSeconds(double x, double contentWidth, double totalSeconds) {
    final effectiveX = x - _hPadding;
    final pct = effectiveX / contentWidth;
    return (pct * totalSeconds);
  }
}
