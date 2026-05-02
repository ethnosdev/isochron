// import 'package:flutter/material.dart';
// import 'package:flutter/services.dart';
// import 'package:isochron_flutter/ui/models/project_model.dart';
// import 'package:isochron_flutter/ui/waveform/fragment_list.dart';
// import 'package:isochron_flutter/ui/widgets/theme_toggle_button.dart';
// import 'package:path/path.dart' as p;
// import 'home_manager.dart';
// import 'models/app_state.dart';
// import 'control_bar/control_bar.dart';
// import 'waveform/waveform_view.dart';
// import 'waveform/waveform_controls.dart';

// class MainScreen extends StatefulWidget {
//   final Project? project;
//   final int? initialItemIndex;
//   final Function(int index)? onNotifySaved;

//   const MainScreen({
//     super.key,
//     this.project,
//     this.initialItemIndex,
//     this.onNotifySaved,
//   });

//   @override
//   State<MainScreen> createState() => _MainScreenState();
// }

// class _MainScreenState extends State<MainScreen> {
//   final HomeManager _controller = HomeManager();
//   final ScrollController _waveScroll = ScrollController();

//   int? _currentIndex;

//   @override
//   void initState() {
//     super.initState();
//     _currentIndex = widget.initialItemIndex;

//     // Wire up the save callback to pass the current index
//     _controller.onSaveCallback = () {
//       if (_currentIndex != null && widget.onNotifySaved != null) {
//         widget.onNotifySaved!(_currentIndex!);
//       }
//     };

//     // Load initial item
//     if (widget.project != null && _currentIndex != null) {
//       WidgetsBinding.instance.addPostFrameCallback((_) {
//         _controller.loadProjectItem(
//           widget.project!.items[_currentIndex!],
//           widget.project!.directoryPath,
//           dictPath: widget.project!.dictionaryPath,
//         );
//       });
//     }
//   }

//   Future<bool> _handleUnsavedChanges() async {
//     if (!_controller.value.hasUnsavedChanges) return true;

//     final result = await showDialog<String>(
//       context: context,
//       builder: (context) => AlertDialog(
//         title: const Text("Unsaved Changes"),
//         content: const Text(
//           "You have unsaved changes. What would you like to do?",
//         ),
//         actions: [
//           TextButton(
//             onPressed: () => Navigator.of(context).pop('cancel'),
//             child: const Text("Cancel"),
//           ),
//           TextButton(
//             onPressed: () => Navigator.of(context).pop('discard'),
//             child: const Text("Discard", style: TextStyle(color: Colors.red)),
//           ),
//           FilledButton(
//             onPressed: () => Navigator.of(context).pop('save'),
//             child: const Text("Save"),
//           ),
//         ],
//       ),
//     );

//     if (result == 'save') {
//       await _controller.saveProject();
//       return true; // Proceed after saving
//     } else if (result == 'discard') {
//       await _controller.discardChanges();
//       return true; // Proceed and lose changes
//     }

//     return false; // User cancelled
//   }

//   Future<void> _goToNextFile() async {
//     if (widget.project == null || _currentIndex == null) return;

//     // Prevent going out of bounds if they press Cmd+N on the last file
//     if (_currentIndex! >= widget.project!.items.length - 1) return;

//     final canProceed = await _handleUnsavedChanges();
//     if (!canProceed) return;

//     setState(() {
//       _currentIndex = _currentIndex! + 1;
//     });

//     _controller.loadProjectItem(
//       widget.project!.items[_currentIndex!],
//       widget.project!.directoryPath,
//       dictPath: widget.project!.dictionaryPath,
//     );

//     // Reset scroll to start for the new file
//     if (_waveScroll.hasClients) {
//       _waveScroll.jumpTo(0);
//     }
//   }

//   void _handleSave() {
//     // Only save if there's actually data and it has been modified
//     final state = _controller.value;
//     if (state.fragments.isNotEmpty && state.hasUnsavedChanges) {
//       _controller.saveProject();
//     }
//   }

//   @override
//   Widget build(BuildContext context) {
//     // Generate App Bar Title
//     String appBarTitle = 'Isochron Studio';
//     bool hasNextFile = false;

//     if (widget.project != null && _currentIndex != null) {
//       final item = widget.project!.items[_currentIndex!];
//       appBarTitle = p.basename(item.audioPath);
//       hasNextFile = _currentIndex! < widget.project!.items.length - 1;
//     }

//     return CallbackShortcuts(
//       bindings: {
//         // Space: Play/Pause
//         const SingleActivator(LogicalKeyboardKey.space): () =>
//             _controller.togglePlay(),

//         // Right/Left Arrows: Skip Next/Prev
//         const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
//             _handleSkipNext(_controller.value),
//         const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
//             _handleSkipPrev(_controller.value),

//         // Command/Ctrl + Right: Move current segment start +100ms
//         const SingleActivator(LogicalKeyboardKey.arrowRight, meta: true): () =>
//             _handleNudge(0.15),
//         const SingleActivator(
//           LogicalKeyboardKey.arrowRight,
//           control: true,
//         ): () =>
//             _handleNudge(0.15),

//         // Command/Ctrl + Left: Move current segment start -100ms
//         const SingleActivator(LogicalKeyboardKey.arrowLeft, meta: true): () =>
//             _handleNudge(-0.15),
//         const SingleActivator(
//           LogicalKeyboardKey.arrowLeft,
//           control: true,
//         ): () =>
//             _handleNudge(-0.15),

//         // Save (Command/Ctrl + S)
//         const SingleActivator(LogicalKeyboardKey.keyS, meta: true): _handleSave,
//         const SingleActivator(LogicalKeyboardKey.keyS, control: true):
//             _handleSave,

//         // Next File (Command/Ctrl + N)
//         const SingleActivator(LogicalKeyboardKey.keyN, meta: true):
//             _goToNextFile,
//         const SingleActivator(LogicalKeyboardKey.keyN, control: true):
//             _goToNextFile,

//         // L: Lock / unlock the hovered (or focused) fragment's timing pin
//         const SingleActivator(LogicalKeyboardKey.keyL): () {
//           final idx =
//               _controller.hoveredFragmentIndex ??
//               _controller.value.focusedFragmentIndex;
//           if (idx != null) _controller.lockFragmentsUntil(idx);
//         },

//         // Shift + L: Toggle individual pin
//         const SingleActivator(LogicalKeyboardKey.keyL, shift: true): () {
//           final idx =
//               _controller.hoveredFragmentIndex ??
//               _controller.value.focusedFragmentIndex;
//           if (idx != null) _controller.toggleFragmentPin(idx);
//         },

//         // Enter: Capture timing manually
//         const SingleActivator(LogicalKeyboardKey.enter): () =>
//             _controller.captureFragmentTiming(context),
//       },
//       child: Focus(
//         autofocus: true,
//         child: ValueListenableBuilder<AppState>(
//           valueListenable: _controller,
//           builder: (context, state, _) {
//             return PopScope(
//               canPop: !state.hasUnsavedChanges,
//               onPopInvokedWithResult: (didPop, result) async {
//                 if (didPop) return;

//                 final canProceed = await _handleUnsavedChanges();
//                 if (canProceed && context.mounted) {
//                   Navigator.of(context).pop();
//                 }
//               },
//               child: Scaffold(
//                 appBar: AppBar(
//                   leading: Navigator.canPop(context)
//                       ? IconButton(
//                           icon: const Icon(Icons.arrow_back),
//                           onPressed: () => Navigator.maybePop(context),
//                         )
//                       : null,
//                   title: Text(appBarTitle),
//                   actions: [
//                     const ThemeToggleButton(),
//                     if (hasNextFile)
//                       TextButton.icon(
//                         icon: const Icon(Icons.skip_next),
//                         label: const Text("Next File"),
//                         onPressed: _goToNextFile,
//                       ),
//                     const SizedBox(width: 8),
//                   ],
//                 ),
//                 body: Column(
//                   children: [
//                     ControlBar(
//                       controller: _controller,
//                       state: state,
//                       onRun: () => _controller.runAlignment(
//                         context,
//                         snapMode: widget.project?.snapMode ?? 'onset',
//                         snapOffsetMs: widget.project?.snapOffset ?? 0,
//                       ),
//                     ),
//                     if (state.isProcessing)
//                       LinearProgressIndicator(value: state.progress),
//                     if (state.waveform != null) ...[
//                       WaveformControls(
//                         isPlaying: state.isPlaying,
//                         zoom: state.zoomLevel,
//                         onPlayPause: _controller.togglePlay,
//                         onSkipNext: () => _handleSkipNext(state),
//                         onSkipPrev: () => _handleSkipPrev(state),
//                         onZoom: (z) => _controller.setZoom(z.toDouble()),
//                       ),
//                       Expanded(
//                         flex: 1,
//                         child: Container(
//                           color: Theme.of(context).colorScheme.surface,
//                           child: WaveformView(
//                             controller: _controller,
//                             state: state,
//                             scrollController: _waveScroll,
//                           ),
//                         ),
//                       ),
//                     ],
//                     Expanded(
//                       flex: 2,
//                       child: FragmentList(
//                         fragments: state.fragments,
//                         currentPos: state.currentPlaybackPosition,
//                         rules: state.transliterationRules,
//                         selectedIndex: state.selectedFragmentIndex,
//                         onSelect: _controller.selectFragment,
//                         onCapture: (i) =>
//                             _controller.captureFragmentTiming(context, i),
//                         onClear: _controller.clearFragmentTiming,
//                         onJumpTo: (idx) {
//                           _controller.exitFocusMode();
//                           _jumpTo(idx, state);
//                         },
//                         onDoubleTap: (idx) {
//                           _controller.enterFocusMode(idx);
//                         },
//                       ),
//                     ),
//                   ],
//                 ),
//               ),
//             );
//           },
//         ),
//       ),
//     );
//   }

//   // --- Keyboard Nav Handlers ---
//   void _handleNudge(double deltaSeconds) {
//     final state = _controller.value;
//     if (state.fragments.isEmpty) return;
//     final currentMs = state.currentPlaybackPosition.inMilliseconds;
//     final index = state.fragments.indexWhere(
//       (f) =>
//           currentMs >= (f.realStart * 1000) && currentMs <= (f.realEnd * 1000),
//     );
//     if (index != -1) {
//       final frag = state.fragments[index];
//       _controller.updateFragment(
//         index,
//         frag.realStart + deltaSeconds,
//         frag.realEnd,
//       );
//     }
//   }

//   void _handleSkipNext(AppState state) {
//     if (state.fragments.isEmpty) return;
//     final currentMs = state.currentPlaybackPosition.inMilliseconds;
//     final nextIndex = state.fragments.indexWhere(
//       (f) => (f.realStart * 1000) > currentMs + 100,
//     );
//     if (nextIndex != -1) {
//       _controller.exitFocusMode();
//       _jumpTo(nextIndex, state);
//     }
//   }

//   void _handleSkipPrev(AppState state) {
//     if (state.fragments.isEmpty) return;
//     final currentMs = state.currentPlaybackPosition.inMilliseconds;
//     final prevIndex = state.fragments.lastIndexWhere(
//       (f) => (f.realStart * 1000) < currentMs - 100,
//     );
//     if (prevIndex != -1) {
//       _controller.exitFocusMode();
//       _jumpTo(prevIndex, state);
//     } else {
//       _jumpTo(0, state);
//     }
//   }

//   void _jumpTo(int index, AppState state) {
//     final frag = state.fragments[index];
//     final ms = (frag.realStart * 1000).toInt();
//     _controller.seekTo(Duration(milliseconds: ms));

//     if (state.audioDuration.inMilliseconds > 0 && _waveScroll.hasClients) {
//       final viewportWidth = _waveScroll.position.viewportDimension;
//       final totalContentWidth = viewportWidth * state.zoomLevel;
//       final totalMs = state.audioDuration.inMilliseconds;
//       final pct = ms / totalMs;
//       final targetPixel = totalContentWidth * pct;
//       final centeredScrollPos = targetPixel - (viewportWidth / 2);

//       _waveScroll.jumpTo(
//         centeredScrollPos.clamp(0.0, _waveScroll.position.maxScrollExtent),
//       );
//     }
//   }
// }
