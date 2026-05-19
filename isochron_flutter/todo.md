Here is a detailed technical roadmap outlining the remaining architectural and performance tasks. This document serves as a blueprint for scaling Isochron from a standard utility into a professional-grade application capable of handling massive, multi-year translation projects (e.g., 60+ collections, 2,000+ tracks).

---

# Isochron Technical Roadmap: Scaling for Large Projects

As users begin utilizing Isochron for full-Bible translations or massive audiobook projects, the sheer volume of data will expose several bottlenecks in the current architecture. The following tasks address UI thread blocking, memory spikes, and disk I/O limitations.

## 1. Flatten the Sidebar Tree (UI Thread Optimization)
**The Problem:** 
Currently, inside `WorkspaceScreen._buildTreeSidebar`, the entire visual tree (`List<Widget> rows`) is eagerly constructed synchronously on the main thread every time `setState` is called. For a project with 1,500 tracks, Flutter generates 1,500 heavy `GestureDetector` and `Row` widgets in a fraction of a second. This causes the UI to freeze/stutter whenever the user clicks a file, expands a folder, or types a letter.

**The Solution:** 
Flatten the data model, not the widgets. Leverage `ListView.builder`'s lazy rendering.

**Implementation Steps:**
1. Create a lightweight `NodeData` class that holds references to what should be drawn (e.g., `NodeType`, depth level, label, icon, associated track/collection).
2. Create a flat `List<NodeData>` based *only* on the current `_expandedNodes` state.
3. Pass this flat list to the `ListView.builder`.
4. In the `itemBuilder`, instantiate the actual `_buildTreeRow` widget on-demand. Flutter will now only build the ~30 widgets currently visible on the screen, completely eliminating UI lag regardless of project size.

## 2. Decouple and Background JSON Saves (Disk I/O Optimization)
**The Problem:**
Every time a user tweaks a setting, adds a file, or deletes a track, the app calls `_project!.save()`. This serializes the *entire* project hierarchy into one massive JSON string and writes it to disk synchronously. As `project.json` grows to several megabytes, `jsonEncode` and file writing will cause noticeable frame drops.

**The Solution:**
Move serialization off the main thread and break up the monolithic JSON file.

**Implementation Steps:**
1. **Short-Term:** Wrap the JSON encoding step inside Flutter's `compute()` function to run it on a background Isolate.
2. **Long-Term:** Stop saving tracks inside the master `project.json`. 
   * The master `project.json` should only store global settings and a list of Collection IDs/Names.
   * Inside each `collections/<ID>/` folder, save a separate `collection.json` that contains the tracks.
   * When a track is modified, only rewrite that specific `collection.json`, reducing the disk write payload from megabytes to kilobytes.

## 3. Schwartzian Transform for File Sorting (CPU Optimization)
**The Problem:**
In `CollectionBatchView`, the `naturalCompare` function uses `RegExp` to intelligently sort files (e.g., ensuring "Track 2" comes before "Track 10"). Because Dart's `List.sort()` compares items $O(N \log N)$ times, the regex engine is evaluated thousands of times during a bulk import. Importing 500 files can lock the main thread for 1–3 seconds.

**The Solution:**
Implement a Schwartzian transform (decorate-sort-undecorate).

**Implementation Steps:**
1. Pre-calculate the regex match arrays for every filename *once*.
2. Store the filename and its pre-calculated regex array in a temporary wrapper object (`{ file: String, parts: List<String> }`).
3. Sort the wrapper objects using simple string/integer comparisons.
4. Extract the sorted filenames back into a standard list. This reduces regex evaluations from $O(N \log N)$ to exactly $O(N)$.

## 4. Stream CSV Exports (Memory Optimization)
**The Problem:**
`ExportService.buildCombinedCsv` iterates through every track in the project, reads the alignment JSON, decodes it into memory, and appends the resulting text to a giant `StringBuffer`. For massive projects, holding thousands of parsed JSON maps and a massive CSV string in RAM simultaneously can cause Garbage Collection (GC) spikes or crash older machines with Out-Of-Memory (OOM) errors.

**The Solution:**
Write the CSV file directly to the disk in chunks via an `IOSink`.

**Implementation Steps:**
1. Change the export method to accept the `File` output path rather than returning a `String`.
2. Open an `IOSink` using `file.openWrite()`.
3. Process one track at a time: read it, decode it, generate the CSV chunk, write it to the `IOSink`, and immediately discard the JSON map.
4. Close the sink. The memory footprint will remain near zero.

## 5. Bulk Relink Tool for Absolute Paths (UX / Resilience)
**The Problem:**
While we recently added the ability to copy media directly into the project (relative paths), many users will still choose "Keep in Place" to save disk space. If a user reorganizes their hard drive (e.g., renaming a folder from `Raw_Audio` to `Translated_Audio`), all absolute paths break. Currently, the user would have to click "Replace File" manually for every single track.

**The Solution:**
Add a "Heal Broken Links" feature.

**Implementation Steps:**
1. Add a visual indicator (like a red warning triangle) on the Collection node if any of its tracks have missing files.
2. Add a "Locate Missing Media..." button in the Collection toolbar.
3. Prompt the user to select the new root folder where the files were moved.
4. Recursively scan the selected folder for filenames that match the broken paths, and automatically update the absolute paths for all missing tracks in one pass.

---

### Recommended Execution Order
If tackling these in phases, the recommended order is:
1. **Task 1 (Sidebar Flattening):** Best immediate ROI for user experience; fixes the most noticeable UI jank.
2. **Task 3 (Regex Sorting):** Quickest win; requires very few lines of code to fix a major import freeze.
3. **Task 5 (Bulk Relinker):** Vital for users working with large datasets who prefer not to duplicate files.
4. **Task 2 & 4 (I/O & Memory):** Can be deferred until users explicitly complain about saving stutters or export crashes on massive datasets.