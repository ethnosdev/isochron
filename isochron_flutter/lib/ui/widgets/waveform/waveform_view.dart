import 'package:flutter/material.dart';
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
        final width = constraints.maxWidth * widget.state.zoomLevel;
        final totalSec = widget.state.audioDuration.inMilliseconds / 1000.0;
        if (totalSec <= 0) return const SizedBox();

        return SingleChildScrollView(
          controller: widget.scrollController,
          scrollDirection: Axis.horizontal,
          child: GestureDetector(
            onTapUp: (d) => _handleSeek(d.localPosition.dx, width, totalSec),
            onHorizontalDragStart: (d) =>
                _handleDragStart(d.localPosition.dx, width, totalSec),
            onHorizontalDragUpdate: (d) =>
                _handleDragUpdate(d.localPosition.dx, width, totalSec),
            onHorizontalDragEnd: (_) => setState(() => _dragIndex = null),
            child: CustomPaint(
              size: Size(width, constraints.maxHeight),
              painter: IsochronWaveformPainter(
                waveform: wf,
                fragments: widget.state.fragments,
                playbackPosSeconds:
                    widget.state.currentPlaybackPosition.inMilliseconds /
                    1000.0,
                totalSeconds: totalSec,
                zoomLevel: widget.state.zoomLevel,
                accentColor: Theme.of(context).primaryColor,
              ),
            ),
          ),
        );
      },
    );
  }

  // 1. REFACTOR: Handle Tap Up
  void _handleTap(double x, double width, double duration) {
    final clickedTime = (x / width) * duration;

    // Check if we are in Focus Mode
    if (widget.state.focusedFragmentIndex != null) {
      _handleFocusClick(clickedTime);
    } else {
      // Standard Behavior: Seek
      final ms = (clickedTime * 1000).toInt();
      widget.controller.seekTo(Duration(milliseconds: ms));
    }
  }

  // 2. NEW: Focus Logic
  void _handleFocusClick(double newStartTime) {
    final idx = widget.state.focusedFragmentIndex!;
    final frag = widget.state.fragments[idx];

    // Validation: Start cannot be after End
    if (newStartTime >= frag.realEnd) return;

    // Validation: Start cannot be before previous fragment's end (optional, but good for safety)
    if (idx > 0) {
      final prevEnd = widget.state.fragments[idx - 1].realEnd;
      if (newStartTime <= prevEnd) return; // Or clamp it
    }

    // Update Timing
    widget.controller.updateFragment(idx, newStartTime, frag.realEnd);

    // Play immediately from the new start point
    widget.controller.seekTo(
      Duration(milliseconds: (newStartTime * 1000).toInt()),
    );
    // widget.controller.play();
  }

  void _handleSeek(double x, double width, double duration) {
    final clickedTime = (x / width) * duration;

    // CHANGED: Always just seek the audio playhead.
    // We no longer check for focusedFragmentIndex to move the start time.
    final ms = (clickedTime * 1000).toInt();
    widget.controller.seekTo(Duration(milliseconds: ms));
  }

  void _handleDragStart(double x, double width, double duration) {
    final time = (x / width) * duration;
    final threshold = 15.0 * (duration / width); // ~15px tolerance

    for (var f in widget.state.fragments) {
      if ((f.realStart - time).abs() < threshold) {
        setState(() {
          _dragIndex = f.index;
          _dragStart = true;
        });
        return;
      }
      if ((f.realEnd - time).abs() < threshold) {
        setState(() {
          _dragIndex = f.index;
          _dragStart = false;
        });
        return;
      }
    }
  }

  void _handleDragUpdate(double x, double width, double duration) {
    if (_dragIndex == null) return;
    final time = ((x / width) * duration).clamp(0.0, duration);
    final frag = widget.state.fragments.firstWhere(
      (f) => f.index == _dragIndex,
    );

    if (_dragStart) {
      widget.controller.updateFragment(_dragIndex!, time, frag.realEnd);
    } else {
      widget.controller.updateFragment(_dragIndex!, frag.realStart, time);
    }
  }
}
