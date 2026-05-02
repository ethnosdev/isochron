// import 'dart:convert';
// import 'dart:io';

// import 'package:file_picker/file_picker.dart';
// import 'package:flutter/foundation.dart';
// import 'package:flutter/material.dart';
// import 'package:isochron_cli/isochron_cli.dart';
// import 'package:isochron_flutter/services/user_settings_service.dart';
// import 'package:isochron_flutter/ui/dialogs/transliteration_preview_dialog.dart';
// import 'package:isochron_flutter/ui/project/project_dashboard.dart';
// import 'package:path/path.dart' as p;
// import '../../services/project_service.dart';

// class ProjectCreationWizard extends StatefulWidget {
//   const ProjectCreationWizard({super.key});

//   @override
//   State<ProjectCreationWizard> createState() => _ProjectCreationWizardState();
// }

// class _ProjectCreationWizardState extends State<ProjectCreationWizard> {
//   final _projectNameCtrl = TextEditingController();
//   final _idPrefixCtrl = TextEditingController();

//   int _idMode = 0; // 0 = None, 1 = In Text, 2 = Auto-Generate
//   bool _isAnalyzing = false;

//   List<String> _audioFiles = [];
//   List<String> _textFiles = [];
//   String? _dictPath;

//   int _currentStep = 0;

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(title: const Text("New Project Setup")),
//       body: Stack(
//         children: [
//           Stepper(
//             type: StepperType.horizontal,
//             currentStep: _currentStep,
//             onStepContinue: _nextStep,
//             onStepCancel: _prevStep,
//             controlsBuilder: (context, details) {
//               return Padding(
//                 padding: const EdgeInsets.only(top: 20),
//                 child: Row(
//                   children: [
//                     FilledButton(
//                       onPressed: details.onStepContinue,
//                       child: Text(
//                         _currentStep == 1 ? "Create Project" : "Next",
//                       ),
//                     ),
//                     const SizedBox(width: 12),
//                     if (_currentStep > 0)
//                       TextButton(
//                         onPressed: details.onStepCancel,
//                         child: const Text("Back"),
//                       ),
//                   ],
//                 ),
//               );
//             },
//             steps: [
//               // STEP 1: INPUTS
//               Step(
//                 title: const Text("Select Files"),
//                 content: Column(
//                   crossAxisAlignment: CrossAxisAlignment.start,
//                   children: [
//                     TextField(
//                       controller: _projectNameCtrl,
//                       decoration: const InputDecoration(
//                         labelText: "Project Name",
//                       ),
//                     ),
//                     const SizedBox(height: 20),
//                     _buildFileSelector(
//                       "Audio Files",
//                       _audioFiles,
//                       FileType.audio,
//                       (files) => setState(() => _audioFiles = files),
//                     ),
//                     const SizedBox(height: 20),
//                     _buildFileSelector(
//                       "Transcripts (Text)",
//                       _textFiles,
//                       FileType.custom,
//                       (files) => setState(() => _textFiles = files),
//                       extensions: ['txt', 'phrases'],
//                     ),
//                     const SizedBox(height: 24),

//                     // --- ID STRATEGY BLOCK ---
//                     Container(
//                       padding: const EdgeInsets.all(16),
//                       decoration: BoxDecoration(
//                         border: Border.all(
//                           color: Theme.of(context).colorScheme.outlineVariant,
//                         ),
//                         borderRadius: BorderRadius.circular(8),
//                       ),
//                       child: Column(
//                         crossAxisAlignment: CrossAxisAlignment.start,
//                         children: [
//                           const Text(
//                             "Verse ID Strategy",
//                             style: TextStyle(
//                               fontWeight: FontWeight.bold,
//                               fontSize: 16,
//                             ),
//                           ),
//                           const SizedBox(height: 8),
//                           RadioListTile<int>(
//                             title: const Text("None"),
//                             subtitle: const Text("Do not use verse IDs"),
//                             value: 0,
//                             groupValue: _idMode,
//                             onChanged: (v) => setState(() => _idMode = v!),
//                           ),
//                           RadioListTile<int>(
//                             title: const Text("IDs are in the text files"),
//                             subtitle: const Text(
//                               "e.g. '40001001 In the beginning...'",
//                             ),
//                             value: 1,
//                             groupValue: _idMode,
//                             onChanged: (v) => setState(() => _idMode = v!),
//                           ),
//                           RadioListTile<int>(
//                             title: const Text("Auto-Generate IDs"),
//                             subtitle: const Text(
//                               "Based on book prefix + file order + line number",
//                             ),
//                             value: 2,
//                             groupValue: _idMode,
//                             onChanged: (v) => setState(() => _idMode = v!),
//                           ),
//                           if (_idMode == 2)
//                             Padding(
//                               padding: const EdgeInsets.only(
//                                 left: 32,
//                                 right: 32,
//                                 top: 8,
//                               ),
//                               child: TextField(
//                                 controller: _idPrefixCtrl,
//                                 decoration: const InputDecoration(
//                                   labelText: "Fixed Book Prefix (e.g. 40)",
//                                   border: OutlineInputBorder(),
//                                 ),
//                               ),
//                             ),
//                         ],
//                       ),
//                     ),

//                     // -------------------------
//                     const SizedBox(height: 24),
//                     const Text(
//                       "Optional:",
//                       style: TextStyle(fontWeight: FontWeight.bold),
//                     ),
//                     const SizedBox(height: 8),
//                     _buildSingleFileSelector(
//                       "Transliteration Dictionary (JSON)",
//                       _dictPath,
//                       (path) => setState(() => _dictPath = path),
//                     ),
//                   ],
//                 ),
//                 isActive: _currentStep >= 0,
//               ),

//               // STEP 2: PAIRING & FINALIZE
//               Step(
//                 title: const Text("Verify Pairs"),
//                 content: Column(
//                   children: [
//                     SizedBox(
//                       height: 400, // Fixed height for list
//                       child: _PairingList(
//                         audioFiles: _audioFiles,
//                         textFiles: _textFiles,
//                         onReorderText: (oldIdx, newIdx) {
//                           setState(() {
//                             if (newIdx > oldIdx) newIdx -= 1;
//                             final item = _textFiles.removeAt(oldIdx);
//                             _textFiles.insert(newIdx, item);
//                           });
//                         },
//                       ),
//                     ),
//                     // Warning section
//                     if (_audioFiles.length != _textFiles.length)
//                       Container(
//                         margin: const EdgeInsets.only(top: 16),
//                         padding: const EdgeInsets.all(12),
//                         decoration: BoxDecoration(
//                           color: Theme.of(context).colorScheme.errorContainer,
//                           borderRadius: BorderRadius.circular(8),
//                           border: Border.all(
//                             color: Theme.of(
//                               context,
//                             ).colorScheme.error.withOpacity(0.5),
//                           ),
//                         ),
//                         child: Row(
//                           children: [
//                             Icon(
//                               Icons.warning,
//                               color: Theme.of(context).colorScheme.error,
//                             ),
//                             const SizedBox(width: 12),
//                             Expanded(
//                               child: Text(
//                                 "Warning: File counts do not match. Only pairs will be imported; orphan files will be ignored.",
//                                 style: TextStyle(
//                                   fontSize: 13,
//                                   color: Theme.of(
//                                     context,
//                                   ).colorScheme.onErrorContainer,
//                                 ),
//                               ),
//                             ),
//                           ],
//                         ),
//                       ),
//                   ],
//                 ),
//                 isActive: _currentStep >= 1,
//               ),
//             ],
//           ),

//           if (_isAnalyzing)
//             Container(
//               color: Colors.black54,
//               child: const Center(
//                 child: Column(
//                   mainAxisSize: MainAxisSize.min,
//                   children: [
//                     CircularProgressIndicator(color: Colors.white),
//                     SizedBox(height: 16),
//                     Text(
//                       "Analyzing dictionary matches...",
//                       style: TextStyle(
//                         color: Colors.white,
//                         fontWeight: FontWeight.bold,
//                       ),
//                     ),
//                   ],
//                 ),
//               ),
//             ),
//         ],
//       ),
//     );
//   }

//   void _nextStep() async {
//     if (_currentStep == 0) {
//       if (_audioFiles.isEmpty || _textFiles.isEmpty) {
//         ScaffoldMessenger.of(context).showSnackBar(
//           const SnackBar(content: Text("Please select audio and text files.")),
//         );
//         return;
//       }

//       if (_idMode == 2 && _idPrefixCtrl.text.trim().isEmpty) {
//         ScaffoldMessenger.of(context).showSnackBar(
//           const SnackBar(content: Text("Please enter a Fixed Book Prefix.")),
//         );
//         return;
//       }

//       if (_dictPath != null) {
//         setState(() => _isAnalyzing = true);

//         try {
//           // 1. Load Dictionary
//           final jsonString = await File(_dictPath!).readAsString();
//           final Map<String, dynamic> rawMap = jsonDecode(jsonString);
//           final rules = rawMap.map((k, v) => MapEntry(k, v.toString()));

//           // 2. Run Analysis on ALL files via Compute
//           final result = await compute(
//             _analyzeAllFiles,
//             _AnalysisRequest(_textFiles, rules, _idMode == 1),
//           );

//           setState(() => _isAnalyzing = false);

//           if (!mounted) return;

//           // 3. Show Result
//           final bool confirm =
//               await showDialog<bool>(
//                 context: context,
//                 barrierDismissible: false,
//                 builder: (_) => TransliterationPreviewDialog(
//                   dictName: p.basename(_dictPath!),
//                   previewLines: result.previewLines,
//                   unknownChars: result.unknownChars,
//                 ),
//               ) ??
//               false;

//           if (!confirm) return; // Stop if user cancels
//         } catch (e) {
//           setState(() => _isAnalyzing = false);
//           if (mounted) {
//             ScaffoldMessenger.of(context).showSnackBar(
//               SnackBar(content: Text("Error checking dictionary: $e")),
//             );
//           }
//           return; // Stop on error
//         }
//       }

//       // Sort initially for better UX before manual reordering
//       _audioFiles.sort((a, b) => p.basename(a).compareTo(p.basename(b)));
//       _textFiles.sort((a, b) => p.basename(a).compareTo(p.basename(b)));

//       setState(() => _currentStep = 1);
//     } else if (_currentStep == 1) {
//       // CREATE PROJECT
//       final service = ProjectService();
//       final project = await service.createNewProject(
//         _projectNameCtrl.text,
//         _audioFiles,
//         _textFiles,
//         _dictPath,
//         _idMode == 1, // hasIds
//         _idMode == 2, // generateIds
//         _idMode == 2 ? _idPrefixCtrl.text.trim() : null, // generatedIdPrefix
//       );

//       if (project != null && mounted) {
//         Navigator.of(context).pushReplacement(
//           MaterialPageRoute(builder: (_) => ProjectDashboard(project: project)),
//         );
//       }
//     }
//   }

//   void _prevStep() {
//     if (_currentStep > 0) setState(() => _currentStep--);
//   }

//   Widget _buildFileSelector(
//     String title,
//     List<String> current,
//     FileType type,
//     Function(List<String>) onSelected, {
//     List<String>? extensions,
//   }) {
//     return Column(
//       crossAxisAlignment: CrossAxisAlignment.start,
//       children: [
//         Row(
//           mainAxisAlignment: MainAxisAlignment.spaceBetween,
//           children: [
//             Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
//             OutlinedButton(
//               onPressed: () async {
//                 final settings = UserSettingsService();
//                 final result = await FilePicker.pickFiles(
//                   type: type,
//                   allowMultiple: true,
//                   allowedExtensions: extensions,
//                   initialDirectory: settings.lastSourceDir,
//                 );
//                 if (result != null) {
//                   if (result.files.isNotEmpty &&
//                       result.files.first.path != null) {
//                     final parent = File(result.files.first.path!).parent.path;
//                     await settings.setLastSourceDir(parent);
//                   }
//                   onSelected(result.paths.whereType<String>().toList());
//                 }
//               },
//               child: const Text("Browse..."),
//             ),
//           ],
//         ),
//         if (current.isNotEmpty)
//           Text(
//             "${current.length} files selected",
//             style: TextStyle(color: Theme.of(context).colorScheme.primary),
//           ),
//       ],
//     );
//   }

//   Widget _buildSingleFileSelector(
//     String title,
//     String? current,
//     Function(String?) onSelected,
//   ) {
//     return Column(
//       crossAxisAlignment: CrossAxisAlignment.start,
//       children: [
//         Row(
//           mainAxisAlignment: MainAxisAlignment.spaceBetween,
//           children: [
//             Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
//             OutlinedButton(
//               onPressed: () async {
//                 final settings = UserSettingsService();
//                 final result = await FilePicker.pickFiles(
//                   type: FileType.custom,
//                   allowedExtensions: ['json'],
//                   initialDirectory: settings.lastDictDir,
//                 );
//                 if (result != null && result.files.single.path != null) {
//                   final path = result.files.single.path!;
//                   await settings.setLastDictDir(File(path).parent.path);
//                   onSelected(path);
//                 }
//               },
//               child: const Text("Browse..."),
//             ),
//           ],
//         ),
//         if (current != null)
//           Text(
//             p.basename(current),
//             style: TextStyle(color: Theme.of(context).colorScheme.primary),
//           ),
//       ],
//     );
//   }
// }

// class _PairingList extends StatelessWidget {
//   final List<String> audioFiles;
//   final List<String> textFiles;
//   final Function(int, int) onReorderText;

//   const _PairingList({
//     required this.audioFiles,
//     required this.textFiles,
//     required this.onReorderText,
//   });

//   @override
//   Widget build(BuildContext context) {
//     // We visualize based on the longer list to show gaps
//     final int count = audioFiles.length > textFiles.length
//         ? audioFiles.length
//         : textFiles.length;

//     return Row(
//       children: [
//         // Left Column: Audio (Fixed)
//         Expanded(
//           child: Column(
//             children: [
//               const Padding(
//                 padding: EdgeInsets.all(8.0),
//                 child: Text(
//                   "Audio (Fixed Order)",
//                   style: TextStyle(fontWeight: FontWeight.bold),
//                 ),
//               ),
//               Expanded(
//                 child: ListView.builder(
//                   itemCount: count,
//                   itemExtent: 50,
//                   itemBuilder: (context, i) {
//                     final name = i < audioFiles.length
//                         ? p.basename(audioFiles[i])
//                         : "-";
//                     return Container(
//                       alignment: Alignment.centerLeft,
//                       padding: const EdgeInsets.symmetric(horizontal: 8),
//                       decoration: BoxDecoration(
//                         border: Border(
//                           bottom: BorderSide(
//                             color: Theme.of(context).dividerColor,
//                           ),
//                         ),
//                       ),
//                       child: Text(name, style: const TextStyle(fontSize: 12)),
//                     );
//                   },
//                 ),
//               ),
//             ],
//           ),
//         ),

//         // Divider
//         Container(width: 1, color: Theme.of(context).dividerColor),

//         // Right Column: Text (Reorderable)
//         Expanded(
//           child: Column(
//             children: [
//               const Padding(
//                 padding: EdgeInsets.all(8.0),
//                 child: Text(
//                   "Text (Drag to Align)",
//                   style: TextStyle(fontWeight: FontWeight.bold),
//                 ),
//               ),
//               Expanded(
//                 child: ReorderableListView.builder(
//                   itemCount: textFiles.length,
//                   itemExtent: 50,
//                   onReorder: onReorderText,
//                   itemBuilder: (context, i) {
//                     return Container(
//                       key: ValueKey(
//                         textFiles[i],
//                       ), // Key must be unique based on path
//                       alignment: Alignment.centerLeft,
//                       padding: const EdgeInsets.symmetric(horizontal: 8),
//                       decoration: BoxDecoration(
//                         color: Theme.of(context).colorScheme.surface,
//                         border: Border(
//                           bottom: BorderSide(
//                             color: Theme.of(context).dividerColor,
//                           ),
//                         ),
//                       ),
//                       child: Row(
//                         children: [
//                           Icon(
//                             Icons.drag_handle,
//                             size: 16,
//                             color: Theme.of(
//                               context,
//                             ).colorScheme.onSurfaceVariant,
//                           ),
//                           const SizedBox(width: 8),
//                           Expanded(
//                             child: Text(
//                               p.basename(textFiles[i]),
//                               style: const TextStyle(fontSize: 12),
//                             ),
//                           ),
//                         ],
//                       ),
//                     );
//                   },
//                 ),
//               ),
//             ],
//           ),
//         ),
//       ],
//     );
//   }
// }

// // --- BACKGROUND ISOLATE LOGIC ---

// class _AnalysisRequest {
//   final List<String> filePaths;
//   final Map<String, String> rules;
//   final bool hasIds;
//   _AnalysisRequest(this.filePaths, this.rules, this.hasIds);
// }

// class _AnalysisResult {
//   final List<String> previewLines;
//   final List<String> unknownChars;
//   _AnalysisResult(this.previewLines, this.unknownChars);
// }

// Future<_AnalysisResult> _analyzeAllFiles(_AnalysisRequest req) async {
//   final Set<String> unknownSet = {};
//   final List<String> previewLines = [];
//   final nonLatinRegex = RegExp(r'[^\x00-\x7F]'); // Detects non-ASCII

//   // Loop through ALL files
//   for (int i = 0; i < req.filePaths.length; i++) {
//     final file = File(req.filePaths[i]);
//     if (!file.existsSync()) continue;

//     final lines = await file.readAsLines();

//     for (var line in lines) {
//       if (line.trim().isEmpty) continue;

//       String textToProcess = line;

//       // Strip IDs
//       if (req.hasIds) {
//         final parts = line.trim().split(' ');
//         if (parts.length > 1) {
//           textToProcess = parts.sublist(1).join(' ');
//         }
//       }

//       // Transliterate
//       final converted = Transliterator.convert(textToProcess, req.rules);

//       // Collect Unknowns
//       final matches = nonLatinRegex.allMatches(converted);
//       for (var m in matches) {
//         unknownSet.add(m.group(0)!);
//       }

//       // Save Preview (Only from the first file, first 5 lines)
//       if (i == 0 && previewLines.length < 5) {
//         previewLines.add(converted);
//       }
//     }
//   }

//   final sortedUnknowns = unknownSet.toList()..sort();
//   return _AnalysisResult(previewLines, sortedUnknowns);
// }
