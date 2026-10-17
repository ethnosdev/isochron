# Isochron Studio — UI/UX Modernization & Simplification Spec

## Overview & Objective
Refactor `isochron_flutter` to eliminate redundant screens/settings, streamline the workspace navigation tree, introduce visible transport/triage controls, upgrade the waveform visual hierarchy, fix scannability and selection bugs in the fragment list, and add non-destructive editing (Undo/Redo + inline text editing).

### Architectural Guardrails
1. **Design System:** Strictly use `macos_ui` components, `CupertinoIcons`, and the semantic color resolvers in `AppTheme` (`lib/ui/theme/app_theme.dart`). Do **not** introduce Material (`package:flutter/material.dart`) widgets (`ListTile`, `ElevatedButton`, `Slider`, `CircleAvatar`, `InkWell`) into UI views.
2. **State Management:** Keep existing `ValueNotifier<AppState>` (`AppManager`) and `ChangeNotifier` (`WorkspaceManager`) patterns intact.
3. **Zero Data Loss:** Removing UI wizards or raw file inspector views must not break underlying JSON serialization (`project.json`, `collection.json`, or track alignment `.json` files).

---

## Phase 1: Dead Code Removal & Tree Simplification

### Step 1.1: Delete Legacy Material Widgets
1. Delete `lib/ui/editor/components/fragment_list.dart` (the legacy Material `FragmentList` widget).
2. Delete `lib/ui/waveform/waveform_controls.dart` (the legacy Material `WaveformControls` widget).
3. Remove any unused imports referencing these two files across the repository.

### Step 1.2: Flatten Sidebar Tree to Depth 1 (Collections & Tracks Only)
Users should interact with **Collections** and **Tracks**, not raw file-system nodes.

1. **Update `lib/ui/workspace/models/sidebar_node.dart`:**
   - Change `enum SidebarNodeType { collection, track, audio, text }` to `enum SidebarNodeType { collection, track }`.
2. **Update `lib/ui/workspace/models/workspace_models.dart`:**
   - Change `enum NodeType { collection, track, audio, text, settings }` to `enum NodeType { collection, track, settings }`.
3. **Update `lib/ui/workspace/workspace_manager.dart`:**
   - Remove `String? expandedTrackId;` and `void setExpandedTrack(String? trackId)`.
   - In `selectNode(TreeSelection selection)`, remove the logic that sets `expandedTrackId`.
   - Add a helper method `Future<void> replaceTrackAudio(Track track, Collection col, String newSourcePath)` and `Future<void> replaceTrackText(Track track, Collection col, String newSourcePath)` that handle copying media (if `project.copyMediaIntoProject` is true), updating `track.audioPath` / `track.textPath`, saving the collection, and reloading the track if it is currently active.
4. **Update `lib/ui/workspace/components/workspace_router.dart`:**
   - Remove `case NodeType.audio:` and `case NodeType.text:` from `WorkspaceRouter.build`.
   - Delete `lib/ui/workspace/views/audio_inspector_view.dart` and `lib/ui/workspace/views/text_editor_view.dart` once their file-replacement logic is moved to context menus and `StudioEditor` empty/missing states.

### Step 1.3: Fix Sidebar Interactions, Context Menus & Pinned Footer
1. **Update `lib/ui/workspace/components/workspace_sidebar.dart`:**
   - **Remove Depth-2 Node Generation:** In `_getFlatNodes`, stop emitting `SidebarNodeType.audio` and `SidebarNodeType.text` children under tracks. Tracks are now leaf nodes (`hasChildren: false`, `depth: 1`).
   - **Missing File Indicator on Track Row:** In `case SidebarNodeType.track:`, check if `resolvedAudio` or `resolvedText` is missing (`!File(resolved).existsSync()`). If either file is missing, pass a warning icon (`CupertinoIcons.exclamationmark_triangle_fill` colored with `AppTheme.destructive(context)`) to the `trailing` slot of `_buildTreeRow`.
   - **Fix Click vs. Chevron Expansion:**
     - In `_buildTreeRow`, wrap the chevron `Icon` (when `hasChildren == true`) in its own `GestureDetector` that exclusively calls `onToggleExpand` (`manager.toggleExpandedNode(col.id)`).
     - Clicking the main row selects the node (`manager.selectNode(...)`).
     - For `SidebarNodeType.collection`, double-clicking the row should toggle expansion (`manager.toggleExpandedNode(col.id)`), matching macOS Finder conventions.
   - **Add Native Right-Click Context Menus (`onSecondaryTapDown`):**
     - Add `GestureDetector.onSecondaryTapDown` to `_buildTreeRow` and use `showMacosContextMenu` (or a custom overlay menu / `CupertinoActionSheet` anchored to the tap offset):
       - **For Collections:** `Rename`, `Import Files...`, `Run Alignment on All`, `Reveal in Finder`, `Delete Collection`.
       - **For Tracks:** `Rename`, `Run Auto-Align`, `Replace Audio File...`, `Replace Transcript File...`, `Reveal in Finder`, `Delete Track`.
   - **Add Pinned Sidebar Footer:**
     - Use the `bottom` property of `Sidebar` in `buildWorkspaceSidebar` to render a pinned footer bar with two compact action buttons:
       1. **Project Settings** (`CupertinoIcons.gear_alt` -> selects `TreeSelection(type: NodeType.settings)`).
       2. **Acoustic Model** (`CupertinoIcons.waveform_circle` -> calls `ModelPanel.show(context)`).

---

## Phase 2: Eliminate the 3-Step Wizard & Automate ID Detection

### Step 2.1: Automate Verse ID Detection Globally
Users should not have to configure whether their text files contain IDs.

1. **Update `lib/ui/workspace/views/project_settings_view.dart`:**
   - Remove the **"Verse ID Strategy"** dropdown section (`None`, `IDs are included`, `Auto-Generate`), keeping only an optional **"Default ID Prefix"** text field (`_prefixController`) under File Management for when files do not contain embedded IDs.
2. **Update `lib/ui/app_manager.dart` (`loadTrack` and `initManualAlignment`) & `lib/ui/workspace/workspace_manager.dart` (`runBatch`):**
   - Always inspect the transcript file using `detectTabDelimitedIds(sample)` or line-by-line `extractIdFromLine(line)`.
   - If lines contain leading IDs, extract and preserve them automatically.
   - If lines do not contain leading IDs and `project.defaultIdPrefix` is non-empty (or auto-generation is desired), generate sequential IDs (`$prefix$recStr$verseStr`) automatically.

### Step 2.2: Replace Collection Wizard with Instant Dropzone & Triage Dashboard
1. **Update `lib/ui/workspace/workspace_manager.dart` (`addCollection`):**
   - When `addCollection()` is called, create the new `Collection`, add it to `project.collections`, select it immediately (`selectNode(TreeSelection(type: NodeType.collection, collection: newCol))`), and set `editingNodeId = newCol.id` so the user can immediately type the collection name in the sidebar and press Enter.
2. **Refactor `lib/ui/workspace/views/collection_batch_view.dart`:**
   - **Delete the 3-step wizard state and methods:** Remove `_showWizard`, `_currentStep`, `_buildStep0`, `_buildStep1`, `_buildStep2`, `_buildWizardSidebar`, `_buildWizardNavigation`, and `_buildWizardView`.
   - **Direct Import Flow:** Keep `_naturalSort` and `_updatePairing`. When the user clicks **"Import Files..."** (or drops files onto the view), immediately run `_pickFilesAndCreateTracks()`:
     - Open `FilePicker.pickFiles(allowMultiple: true)` (or accept dropped files).
     - Separate audio (`.mp3`, `.wav`, `.m4a`) and text (`.txt`, `.phrases`), run `_naturalSort`, pair them by index, copy media if `widget.project.copyMediaIntoProject` is true, create `Track` instances, append to `widget.collection.tracks`, and call `widget.onChanged()`.
   - **Empty Collection State:** When `widget.collection.tracks.isEmpty`, display a clean, centered dropzone container (`border: Border.all(color: theme.dividerColor)`, rounded corners) with `CupertinoIcons.tray_arrow_down`, explanatory text (*"Select or drop audio (.mp3, .wav, .m4a) and transcript (.txt) files. Files will be naturally sorted and paired automatically."*), and a primary **"Select Audio & Text Files..."** `PushButton`.
   - **Upgrade Populated View to a Review Triage Dashboard:**
     - **Summary Header Bar:** Compute counts across `widget.collection.tracks`:
       - `totalTracks`, `reviewedCount`, `doneCount`, `pendingCount`, `errorCount`.
       - Also read or cache fragment flag counts per track (or display track status pills).
       - Render a segmented visual progress bar showing Reviewed (`AppTheme.success`), Done (`AppTheme.accent`), Error (`AppTheme.destructive`), and Pending (`AppTheme.grey`).
     - **Action Row:**
       - Primary `PushButton`: **"Run Alignment on All"** (or **"Stop Batch"** when `widget.isRunning`).
       - Secondary `PushButton`: **"Import More Files..."** (directly opens file picker and appends paired tracks).
     - **Richer Track Rows:** In the `ListView.builder`:
       - Left: Status icon (`CupertinoIcons.checkmark_seal_fill` in `AppTheme.success` for `reviewed`, `CupertinoIcons.checkmark_circle` in `AppTheme.accent` for `done`, `CupertinoIcons.exclamationmark_circle` in `AppTheme.destructive` for `error`, `CupertinoIcons.clock` in `AppTheme.warning` for `pending`, or `ProgressCircle` for `processing`).
       - Middle: Track Name (`fontWeight: FontWeight.bold`) + subtitle showing resolved audio filename and text filename (or red warning text if either is missing).
       - Right: Status badge pill + a quick-action `MacosIconButton` (`CupertinoIcons.chevron_right`) to open the track in `StudioEditor`.

---

## Phase 3: Modernize the Welcome Screen (`WelcomeView`)

### Step 3.1: Add Recent Projects Tracking to `UserSettingsService`
1. In `lib/services/user_settings_service.dart` (inspect existing implementation and extend it):
   - Add a `List<String> get recentProjectPaths` getter and `Future<void> addRecentProject(String projectJsonPath)` method persisted in `SharedPreferences` (max 10 entries, deduplicated, filtering out paths where `!File(path).existsSync()`).
2. In `WorkspaceScreen._createNewProject` and `WorkspaceScreen._openProject`:
   - Call `UserSettingsService().addRecentProject(projectJsonPath)` whenever a project is created or opened.

### Step 3.2: Redesign `lib/ui/workspace/views/welcome_view.dart`
1. Convert `WelcomeView` into a `StatefulWidget` so it can check acoustic model status via `ModelManager().checkStatus(ModelVariant.int8)` and load `recentProjectPaths`.
2. **Update Constructor:** Accept `final ValueChanged<String> onOpenRecentProject;` in addition to `onCreateNewProject` and `onOpenProject`.
3. **Two-Column Layout (constrained to `maxWidth: 760, maxHeight: 460`):**
   - **Left Column (Width 280px, padded 24px):**
     - App Icon (`CupertinoIcons.waveform_path_ecg`, size 56, `AppTheme.accent(context)`).
     - Title: `"Isochron Studio"` (`largeTitle`, bold) + Subtitle: `"Multilingual Forced Alignment"` (`subheadline`, `AppTheme.grey(context)`).
     - Primary `PushButton`: **"Create New Project..."**
     - Secondary `PushButton`: **"Open Project..."**
     - `Spacer()`
     - **Acoustic Model Status Card:** A clickable container at the bottom of the left column that displays a status dot (`AppTheme.success` if `ModelStatus.ready`, `AppTheme.warning` if `notDownloaded`) and label (`"MMS Acoustic Model: Ready"` or `"MMS Model Required — Setup..."`). Clicking it opens `ModelPanel.show(context, onModelReady: () => setState(() {}))`.
   - **Right Column (Expanded, surface container background):**
     - Header: `"Recent Projects"` (`headline`).
     - A `ListView` of recent projects from `UserSettingsService().recentProjectPaths`. Each row displays the folder/project name in bold, the truncated directory path in `AppTheme.grey(context)`, and opens the project on single click via `onOpenRecentProject(path)`.
     - If `recentProjectPaths` is empty, show a subtle empty state message: *"No recent projects."*

---

## Phase 4: Undo/Redo Stack & Non-Destructive Editing in `AppManager`

### Step 4.1: Add Undo/Redo History to `lib/ui/app_manager.dart`
1. Add two private stacks in `AppManager`:
   ```dart
   final List<List<Fragment>> _undoStack = [];
   final List<List<Fragment>> _redoStack = [];
   static const int _maxHistoryDepth = 30;

   bool get canUndo => _undoStack.isNotEmpty;
   bool get canRedo => _redoStack.isNotEmpty;
   ```
2. Create a helper `void _recordUndoSnapshot()`:
   - Deep-copy `value.fragments` (e.g., `value.fragments.map((f) => f.copyWith()).toList()`) and push onto `_undoStack`.
   - If `_undoStack.length > _maxHistoryDepth`, remove the oldest entry (`_undoStack.removeAt(0)`).
   - Clear `_redoStack`.
3. Call `_recordUndoSnapshot()` before mutating fragments in:
   - `captureFragmentTiming`
   - `clearFragmentTiming`
   - `markReviewedAndAdvance`
   - `updateFragmentText` (new method, see Step 4.2)
   - `onDragStart` / boundary drag start (add a method `beginBoundaryEdit()` called from `WaveformView._handleDragStart` and `nudgeActiveBoundary` when `_latchedNudgeFragmentIndex == null` so a continuous drag or held nudge records as a single undo step).
4. Implement `void undo()` and `void redo()`:
   - `undo()`: If `_undoStack.isEmpty`, return. Push current `value.fragments` to `_redoStack`, pop the last snapshot from `_undoStack`, set `value = value.copyWith(fragments: snapshot, hasUnsavedChanges: true)`, and call `scheduleNudgeAutoSave()`.
   - `redo()`: If `_redoStack.isEmpty`, return. Push current `value.fragments` to `_undoStack`, pop from `_redoStack`, set `value = value.copyWith(fragments: snapshot, hasUnsavedChanges: true)`, and call `scheduleNudgeAutoSave()`.
5. Clear `_undoStack` and `_redoStack` inside `loadTrack()`.

### Step 4.2: Add Inline Fragment Text Editing Support
1. In `AppManager` (`lib/ui/app_manager.dart`), add:
   ```dart
   void updateFragmentText(int index, String newText) {
     final trimmed = newText.trim();
     if (index < 0 || index >= value.fragments.length) return;
     if (trimmed.isEmpty || trimmed == value.fragments[index].text) return;

     _recordUndoSnapshot();
     final frags = List<Fragment>.from(value.fragments);
     frags[index] = frags[index].copyWith(text: trimmed);
     value = value.copyWith(fragments: frags, hasUnsavedChanges: true);
     saveProject();
   }
   ```
2. Add a method `void toggleFragmentReviewed(int index)` in `AppManager` so users can toggle a single row's `FragmentStatus.reviewed` status directly from the list row button without advancing the playhead if clicked via mouse.

### Step 4.3: Add Filter Mode to `AppState`
1. In `lib/ui/models/app_state.dart`, add an enum:
   ```dart
   enum FragmentFilter { all, unreviewed, flagged }
   ```
2. Add `final FragmentFilter filter;` (default `FragmentFilter.all`) to `AppState` and `copyWith`.
3. In `AppManager`, add `void setFilter(FragmentFilter filter) => value = value.copyWith(filter: filter);`.

---

## Phase 5: Studio Editor Transport & Triage Bar (`StudioEditor`)

### Step 5.1: Add Transport & Triage Bar + Undo Shortcuts
Update `lib/ui/editor/studio_editor.dart`:

1. **Add Keyboard Shortcuts in `CallbackShortcuts`:**
   - `SingleActivator(LogicalKeyboardKey.keyZ, meta: true)`: `() => widget.homeManager.undo()`
   - `SingleActivator(LogicalKeyboardKey.keyZ, meta: true, shift: true)`: `() => widget.homeManager.redo()`
2. **Missing File Fallback Banner:**
   - If `state.audioPath == null || state.textPath == null`, display an inline banner inside `StudioEditor` with buttons to attach/replace the missing Audio or Text file directly.
3. **Insert the Transport & Triage Control Bar (Height: 42px):**
   Place a horizontal control bar between `WaveformView` and `StudioFragmentList` with top and bottom borders (`MacosTheme.of(context).dividerColor`) and background `AppTheme.selectionBg(context).withValues(alpha: 0.35)`:
   - **Left Group (Transport & Timecode):**
     - **Play / Pause Button (`MacosIconButton`):** Shows `CupertinoIcons.pause_fill` or `CupertinoIcons.play_arrow_solid` colored with `AppTheme.accent(context)`. Tooltip: `"Play / Pause (Space)"`. Calls `widget.homeManager.togglePlay()`.
     - **Audition Fragment Button (`MacosIconButton`):** Icon `CupertinoIcons.Selection_pin_in_out` or `CupertinoIcons.repeat_1`. Tooltip: `"Play Current Fragment (P)"`. Calls `widget.homeManager.playCurrentFragment()`.
     - **Skip Prev / Next Buttons (`MacosIconButton`):** `CupertinoIcons.backward_end_fill` and `CupertinoIcons.forward_end_fill`. Tooltips: `"Previous (←)"`, `"Next (→)"`.
     - **Live Timecode Display:** Wrap in `ValueListenableBuilder<Duration>(valueListenable: widget.homeManager.playbackPosition, ...)`. Format `currentPos` and `state.audioDuration` as `MM:SS.cc / MM:SS.cc` using `FontFeature.tabularFigures()`.
   - **Center Group (Filter Pills & Flag Navigation):**
     - Segmented filter pills for `FragmentFilter.all`, `FragmentFilter.unreviewed`, and `FragmentFilter.flagged` showing live counts, e.g., `All (34)`, `Unreviewed (12)`, `Flagged (3)`.
     - If flagged count > 0, render a compact button: `⚠️ Next Flag (F)` calling `widget.homeManager.jumpToNextFlaggedVerse()`.
   - **Right Group (Review & Undo/Zoom):**
     - **Mark Reviewed Button (`PushButton` secondary):** `"✓ Mark Reviewed (R)"` calling `widget.homeManager.markReviewedAndAdvance()`.
     - **Undo / Redo Buttons (`MacosIconButton`):** `CupertinoIcons.arrow_turn_up_left` and `CupertinoIcons.arrow_turn_up_right` bound to `undo()` and `redo()` (disabled when `!canUndo` / `!canRedo`).

---

## Phase 6: Waveform Timeline Ruler, Status Colors & Context Menu

### Step 6.1: Upgrade `IsochronWaveformPainter` (`lib/ui/waveform/waveform_painter.dart`)
1. **Add New Constructor Parameters to `IsochronWaveformPainter`:**
   - `final int? selectedFragmentIndex;`
   - `final int? hoveredFragmentIndex;`
   - `final double? hoveredBoundaryTime;`
   - `final Color reviewedColor;` (`AppTheme.success(context)`)
   - `final Color warningColor;` (`AppTheme.warning(context)`)
   - `final Color destructiveColor;` (`AppTheme.destructive(context)`)
   - `final Color textColor;`
2. **Reserve Top 22px for a Timeline Ruler (`_drawTimelineRuler`):**
   - Draw a subtle header strip (`height: 22`) along the top of the canvas with a 1px bottom border.
   - Calculate an adaptive tick interval based on `pixelsPerSecond = size.width / totalSeconds`:
     - If `pixelsPerSecond > 150`: major tick every `1s`, minor tick every `0.2s`.
     - Else if `pixelsPerSecond > 40`: major tick every `5s`, minor tick every `1s`.
     - Else if `pixelsPerSecond > 10`: major tick every `15s`, minor tick every `5s`.
     - Else: major tick every `60s`, minor tick every `15s`.
   - Draw tick marks and `MM:SS` (or `MM:SS.d` when zoomed in) labels using `TextPainter`.
3. **Color-Code Fragment Regions by Status (`_drawFragments`):**
   - Offset the waveform and fragment body to start below the 22px ruler (`top = 22.0`).
   - Choose region color per fragment:
     - If `frag.flags.isNotEmpty`: `destructiveColor` (or `warningColor`).
     - Else if `frag.status == FragmentStatus.reviewed`: `reviewedColor`.
     - Else if `frag.status == FragmentStatus.edited`: `warningColor`.
     - Else: `accentColor`.
   - **Selected & Hovered Emphasis:**
     - If `frag.index == selectedFragmentIndex`, increase fill alpha from `0.12` to `0.24` and draw a 2px top highlight bar across `[xStart, xEnd]`.
     - If `frag.index == hoveredFragmentIndex`, use `0.18` fill alpha.
   - **Hovered Boundary Handle Glow:**
     - If `hoveredBoundaryTime != null` and `(frag.realStart - hoveredBoundaryTime!).abs() < 0.001` or `(frag.realEnd - hoveredBoundaryTime!).abs() < 0.001`, draw that boundary line with `strokeWidth = 3.5` and a circular grab handle at the vertical midpoint so the user clearly sees which boundary will move.
   - **Label Badge:** Paint `#${frag.index + 1}` (and `frag.id` if enough width) inside a small rounded pill at `(xStart + 4, 26)`.
4. **Optimize `shouldRepaint`:**
   - Replace `=> true` with field comparisons (`old.playbackPosSeconds != playbackPosSeconds || old.zoomLevel != zoomLevel || old.fragments != fragments || old.selectedFragmentIndex != selectedFragmentIndex || old.hoveredFragmentIndex != hoveredFragmentIndex || old.hoveredBoundaryTime != hoveredBoundaryTime`).

### Step 6.2: Upgrade `WaveformView` Interactions (`lib/ui/waveform/waveform_view.dart`)
1. **Track `_hoveredBoundaryTime` in State:**
   - In `_handleHover`, store the closest boundary time within `_hoverThresholdPx` in `double? _hoveredBoundaryTime` and pass it to `IsochronWaveformPainter`.
2. **Ruler Scrubbing vs. Waveform Clicking:**
   - If the user clicks or drags in the top 22px ruler area (`localPosition.dy <= 22`), immediately scrub the playhead (`_handleSeek`) continuously during drag.
   - If the user clicks in the main waveform body (`localPosition.dy > 22`), seek to that time **and** select the fragment containing that timestamp (`widget.controller.selectFragment(clickedIdx)`).
3. **Record Undo Snapshot on Drag Start:**
   - In `_handleDragStart`, when a boundary is grabbed (`_dragIndex = f.index`), call `widget.controller.beginBoundaryEdit()` so the pre-drag state is pushed onto the undo stack once.
4. **Replace Instant Right-Click Delete with a Context Menu:**
   - In `_handleRightClick(TapDownDetails d, double contentWidth, double totalSec)`:
     - Do **not** immediately call `clearFragmentTiming`.
     - Identify the fragment under the cursor (`time >= f.realStart && time <= f.realEnd`) or near a boundary.
     - Show a context menu with options:
       - **Play Fragment (`P`)** -> selects fragment and calls `playCurrentFragment()`
       - **Mark Reviewed (`R`)** -> calls `toggleFragmentReviewed(f.index)`
       - **Snap Start to Playhead (`Enter`)** -> calls `captureFragmentTiming(context, f.index)`
       - **Reset to Auto Boundary** (enabled if `f.autoStart != null`) -> calls `updateFragment(f.index, f.autoStart!, f.realEnd)`
       - **Clear Timing** (destructive) -> calls `clearFragmentTiming(f.index)`

---

## Phase 7: Refactor `StudioFragmentList` Layout, Theme & Bugs

Update `lib/ui/editor/components/studio_fragment_list.dart`:

### Step 7.1: Fix the Selection Highlight Bug & Theme Colors
1. **Fix Selection Highlighting (Current Bug on Line 264):**
   - Replace `final bool isHighlighted = isPlaying || (isSelected && !hasTime);` with distinct visual states for **Playing** and **Selected**:
     - `isPlaying`: Tint row background with `AppTheme.accent(context).withValues(alpha: 0.14)`.
     - `isSelected`: Tint row background with `AppTheme.selectionBg(context)` (or if both `isPlaying && isSelected`, `AppTheme.accent(context).withValues(alpha: 0.22)`) and draw a **4px left accent border** (`BorderSide(color: AppTheme.accent(context), width: 4)`).
2. **Use `AppTheme` Semantic Colors Everywhere:**
   - Replace all hardcoded `CupertinoColors.systemOrange`, `systemGreen`, `systemBlue`, `systemRed` in `_buildStatusBadge`, `_buildConfidenceBadge`, and `_buildFlagBadge` with `AppTheme.warning(context)`, `AppTheme.success(context)`, `AppTheme.accent(context)`, and `AppTheme.destructive(context)`.
   - Use **`AppTheme.romanizedText(context)`** for the `f.romanizedText!` `TextStyle.color` (fixing the bug where `lightRomanized` / `darkRomanized` in `AppTheme` were unused).

### Step 7.2: Prevent Auto-Scroll Whiplash During Manual User Scrolling
1. Add a `DateTime? _lastUserScrollTime;` field in `_StudioFragmentListState`.
2. Wrap `ScrollablePositionedList.builder` in a `Listener`:
   - On `onPointerSignal` (when `event is PointerScrollEvent`) or `onPointerPanZoomUpdate`: set `_lastUserScrollTime = DateTime.now()`.
3. In `_onPlaybackPositionChanged()`:
   - Check if `_lastUserScrollTime != null && DateTime.now().difference(_lastUserScrollTime!) < const Duration(seconds: 4)`. If true, skip calling `_scrollToIndex(newIndex)` so the user can freely inspect other verses while audio plays.

### Step 7.3: Re-Architect Row Layout for Strict Vertical Text Alignment
Currently, inline badges push `f.text` horizontally by varying amounts on every row. Restructure each item row into 3 clean, aligned columns:

1. **Apply Active Filter (`FragmentFilter`):**
   - Accept `final FragmentFilter filter;` in `StudioFragmentList`.
   - Filter the displayed indices (while preserving each fragment's true index `i` for callbacks!) based on `all`, `unreviewed` (`status != FragmentStatus.reviewed`), or `flagged` (`flags.isNotEmpty || warnings.isNotEmpty`).
2. **Column 1: Index & Playback Indicator (`width: 40`)**
   - Displays `CupertinoIcons.speaker_2_fill` (colored `AppTheme.accent(context)`) if `isPlaying`, otherwise `"${f.index + 1}"` in tabular figures.
3. **Column 2: Uniform Left-Aligned Script & Metadata (`Expanded`)**
   - A vertical `Column(crossAxisAlignment: CrossAxisAlignment.start)` where every child starts at the exact same X coordinate:
     - **Sub-row A (Metadata Header — only rendered if `f.id != null`, `f.status != legacy`, `f.confidence != null`, or `f.flags.isNotEmpty`):**
       - `Row` containing: Verse ID pill (`f.id`), `_buildStatusBadge`, `_buildConfidenceBadge`, `_buildFlagBadge` chips, and warning tooltip icon.
       - `const SizedBox(height: 4)` spacing below the badges.
     - **Sub-row B (Primary Transcript Text):**
       - If `_editingFragmentIndex == i`, render `InlineTextEditor(initialText: f.text, onComplete: (val) => ...)` so the user can fix transcript typos inline without invalidating timing!
       - Otherwise, render `Text(f.text, style: TextStyle(color: textColor, fontSize: 13.5, height: 1.4))`.
     - **Sub-row C (Romanized Text — if `f.romanizedText != null`):**
       - `const SizedBox(height: 3)`
       - `Text(f.romanizedText!, style: TextStyle(color: AppTheme.romanizedText(context), fontSize: 13, fontWeight: FontWeight.w500, height: 1.35))`
4. **Column 3: Timing & Quick Actions (`width: 210`)**
   - Right-aligned `Row`:
     - If `hasTime`:
       - Column or Row showing formatted start time (`_formatTimestamp(f.realStart)`) and a subtle duration pill (`"${(f.realEnd - f.realStart).toStringAsFixed(1)}s"`).
       - **Edit Text Button (`MacosIconButton`):** `CupertinoIcons.pencil` (sets `_editingFragmentIndex = i`).
       - **Review Checkmark Toggle (`MacosIconButton`):** `CupertinoIcons.checkmark_circle_fill` (colored `AppTheme.success(context)` if `f.status == FragmentStatus.reviewed`, else `AppTheme.grey(context).withValues(alpha: 0.4)`). Calls `onToggleReviewed(i)`.
       - **Clear Timing Button (`MacosIconButton`):** `CupertinoIcons.clear_circled_solid` (colored `AppTheme.destructive(context)`). Calls `onClear(i)`.
     - Else (`!hasTime`):
       - PushButton (`ControlSize.small`, `secondary: true`): `"Capture (Enter)"` calling `onCapture(i)`.

---

## Phase 8: Verification Checklist
After completing all phases, verify the following:
1. `flutter analyze` passes with zero errors or unused import warnings.
2. All existing unit and widget tests in `test/` pass (update any tests that referenced removed `SidebarNodeType.audio`/`text` or `FragmentList`).
3. Creating a new collection no longer opens a 3-step wizard; importing files pairs them immediately via natural sort and auto-detects tab/space delimited IDs.
4. Clicking a timed fragment in `StudioFragmentList` clearly highlights the selected row even when audio is paused.
5. Pressing `Cmd+Z` / `Cmd+Shift+Z` undoes and redoes boundary drags, nudges, captures, and inline text edits.