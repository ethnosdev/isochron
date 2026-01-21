import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:isochron_cli/isochron_cli.dart';
import '../../../controllers/alignment_controller.dart';
import '../../../models/app_state.dart';
import '../../painters/waveform_painter.dart';

class WaveformView extends StatefulWidget {
  final AlignmentController controller;
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

        return SingleChildScrollView(
          controller: widget.scrollController,
          scrollDirection: Axis.horizontal,
          physics: const ClampingScrollPhysics(),
          child: MouseRegion(
            cursor: _cursor,
            // We use opaque to catch hover events everywhere in the box
            hitTestBehavior: HitTestBehavior.opaque,
            onHover: (event) =>
                _handleHover(event.localPosition.dx, contentWidth, totalSec),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (d) =>
                  _handleSeek(d.localPosition.dx, contentWidth, totalSec),
              onHorizontalDragStart: (d) =>
                  _handleDragStart(d.localPosition.dx, contentWidth, totalSec),
              onHorizontalDragUpdate: (d) =>
                  _handleDragUpdate(d.localPosition.dx, contentWidth, totalSec),
              onHorizontalDragEnd: (_) => setState(() {
                _dragIndex = null;
                _cursor = SystemMouseCursors.basic;
              }),
              child: CustomPaint(
                size: Size(fullPainterWidth, constraints.maxHeight),
                painter: IsochronWaveformPainter(
                  waveform: wf,
                  fragments: widget.state.fragments,
                  playbackPosSeconds:
                      widget.state.currentPlaybackPosition.inMilliseconds /
                      1000.0,
                  totalSeconds: totalSec,
                  zoomLevel: widget.state.zoomLevel,
                  accentColor: Theme.of(context).primaryColor,
                  // NEW PARAMS
                  contentWidth: contentWidth,
                  padding: _hPadding,
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

    // 3. Calculate the time difference equivalent to our pixel threshold.
    // Logic: (Pixels / TotalWidth) * TotalSeconds
    final double thresholdSeconds =
        (_hoverThresholdPx / contentWidth) * totalSec;

    bool isNearBoundary = false;

    // 4. Check all fragments
    // (Optimization note: For huge lists, we could optimize this to only check
    // fragments currently in the viewport, but for <5000 lines this is fast enough)
    for (var f in widget.state.fragments) {
      if ((f.realStart - hoverTime).abs() < thresholdSeconds ||
          (f.realEnd - hoverTime).abs() < thresholdSeconds) {
        isNearBoundary = true;
        break;
      }
    }

    // 5. Update state only if changed to avoid unnecessary rebuilds
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

  void _handleDragStart(double x, double contentWidth, double totalSec) {
    final time = _pxToSeconds(x, contentWidth, totalSec);

    // Pixels per second calculation needs to account for contentWidth
    final pixelsPerSecond = contentWidth / totalSec;
    // Threshold in seconds (e.g. 15 pixels worth of time)
    final thresholdSec = 15.0 / pixelsPerSecond;

    for (var f in widget.state.fragments) {
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
