// import 'package:flutter/material.dart';
// import 'package:file_picker/file_picker.dart';
// import 'package:isochron_flutter/services/user_settings_service.dart';

// class GlobalSettingsDialog extends StatefulWidget {
//   const GlobalSettingsDialog({super.key});

//   @override
//   State<GlobalSettingsDialog> createState() => _GlobalSettingsDialogState();
// }

// class _GlobalSettingsDialogState extends State<GlobalSettingsDialog> {
//   late TextEditingController _ffmpegCtrl;
//   late TextEditingController _espeakCtrl;
//   final _settings = UserSettingsService();

//   @override
//   void initState() {
//     super.initState();
//     _ffmpegCtrl = TextEditingController(text: _settings.ffmpegPath);
//     _espeakCtrl = TextEditingController(text: _settings.espeakPath);
//   }

//   @override
//   void dispose() {
//     _ffmpegCtrl.dispose();
//     _espeakCtrl.dispose();
//     super.dispose();
//   }

//   Future<void> _browseForExecutable(TextEditingController controller) async {
//     final result = await FilePicker.platform.pickFiles(
//       type: FileType.any, // Executables often have no extension on Mac/Linux
//       dialogTitle: "Select Executable",
//     );

//     if (result != null && result.files.single.path != null) {
//       setState(() {
//         controller.text = result.files.single.path!;
//       });
//     }
//   }

//   @override
//   Widget build(BuildContext buildContext) {
//     return AlertDialog(
//       title: const Text("App Settings"),
//       content: SizedBox(
//         width: 500,
//         child: Column(
//           mainAxisSize: MainAxisSize.min,
//           crossAxisAlignment: CrossAxisAlignment.start,
//           children: [
//             const Text(
//               "External Tools",
//               style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
//             ),
//             const SizedBox(height: 8),
//             const Text(
//               "Isochron requires FFmpeg (for audio processing) and eSpeak-ng (for synthesis). "
//               "If they are not in your system PATH, specify their absolute paths here.",
//               style: TextStyle(fontSize: 12, color: Colors.grey),
//             ),
//             const SizedBox(height: 16),

//             // --- FFmpeg ---
//             Row(
//               children: [
//                 Expanded(
//                   child: TextField(
//                     controller: _ffmpegCtrl,
//                     decoration: const InputDecoration(
//                       labelText: "FFmpeg Path",
//                       border: OutlineInputBorder(),
//                       isDense: true,
//                     ),
//                   ),
//                 ),
//                 const SizedBox(width: 8),
//                 OutlinedButton(
//                   onPressed: () => _browseForExecutable(_ffmpegCtrl),
//                   child: const Text("Browse"),
//                 ),
//               ],
//             ),
//             const SizedBox(height: 16),

//             // --- eSpeak ---
//             Row(
//               children: [
//                 Expanded(
//                   child: TextField(
//                     controller: _espeakCtrl,
//                     decoration: const InputDecoration(
//                       labelText: "eSpeak-ng Path",
//                       border: OutlineInputBorder(),
//                       isDense: true,
//                     ),
//                   ),
//                 ),
//                 const SizedBox(width: 8),
//                 OutlinedButton(
//                   onPressed: () => _browseForExecutable(_espeakCtrl),
//                   child: const Text("Browse"),
//                 ),
//               ],
//             ),
//           ],
//         ),
//       ),
//       actions: [
//         TextButton(
//           onPressed: () => Navigator.of(context).pop(),
//           child: const Text("Cancel"),
//         ),
//         FilledButton(
//           onPressed: () async {
//             // Save settings globally
//             await _settings.setFfmpegPath(_ffmpegCtrl.text.trim());
//             await _settings.setEspeakPath(_espeakCtrl.text.trim());
//             if (mounted) Navigator.of(context).pop();
//           },
//           child: const Text("Save"),
//         ),
//       ],
//     );
//   }
// }
