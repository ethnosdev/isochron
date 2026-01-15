import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:isochron_cli/isochron_cli.dart';
import 'package:path/path.dart' as p;

void main() {
  runApp(const IsochronApp());
}

class IsochronApp extends StatelessWidget {
  const IsochronApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Isochron',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  // State
  String? _textPath;
  String? _audioPath;
  List<Fragment> _results = [];
  bool _isProcessing = false;
  String _status = "Select files to begin.";
  String? _dictPath;

  // Settings
  final TextEditingController _ffmpegController = TextEditingController(
    text: 'ffmpeg',
  );
  final TextEditingController _espeakController = TextEditingController(
    text: 'espeak-ng',
  );

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _ffmpegController.text = prefs.getString('ffmpeg_path') ?? 'ffmpeg';
      _espeakController.text = prefs.getString('espeak_path') ?? 'espeak-ng';
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ffmpeg_path', _ffmpegController.text);
    await prefs.setString('espeak_path', _espeakController.text);
    if (mounted) Navigator.pop(context);
  }

  // File Picking
  Future<void> _pickFile(bool isAudio) async {
    final result = await FilePicker.platform.pickFiles(
      type: isAudio ? FileType.audio : FileType.custom,
      allowedExtensions: isAudio ? null : ['txt'],
    );
    if (result != null && result.files.single.path != null) {
      setState(() {
        if (isAudio)
          _audioPath = result.files.single.path;
        else
          _textPath = result.files.single.path;
        _status = "Ready to align.";
      });
    }
  }

  Future<void> _pickDict() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (result != null) {
      setState(() => _dictPath = result.files.single.path);
    }
  }

  // The Heavy Lifting
  Future<void> _runAlignment() async {
    if (_textPath == null || _audioPath == null) return;

    setState(() {
      _isProcessing = true;
      _status = "Processing... (This runs in background)";
      _results = [];
    });

    try {
      // Read and Parse JSON Rule file (if exists)
      Map<String, String>? rules;
      if (_dictPath != null) {
        final content = await File(_dictPath!).readAsString();
        final rawMap = jsonDecode(content) as Map<String, dynamic>;
        rules = rawMap.map((key, value) => MapEntry(key, value.toString()));
      }

      // Prepare arguments for the Isolate
      final args = {
        'textPath': _textPath!,
        'audioPath': _audioPath!,
        'ffmpeg': _ffmpegController.text,
        'espeak': _espeakController.text,
        'rulesJson': _dictPath != null
            ? await File(_dictPath!).readAsString()
            : null, // Pass Raw JSON content
      };

      // Run in background thread so UI doesn't freeze
      final fragments = await compute(_isolateEntry, args);

      setState(() {
        _results = fragments;
        _status = "Success! Aligned ${_results.length} fragments.";
      });
    } catch (e) {
      setState(() => _status = "Error: $e");
      _showErrorDialog(e.toString());
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  // Isolate Entry Point (Must be static/top-level)
  static Future<List<Fragment>> _isolateEntry(Map<String, dynamic> args) async {
    final workDir = Directory.systemTemp.createTempSync('iso_gui_');

    // Parse Rules
    Map<String, String>? rules;
    if (args['rulesJson'] != null) {
      final rawMap = jsonDecode(args['rulesJson']) as Map<String, dynamic>;
      rules = rawMap.map((key, value) => MapEntry(key, value.toString()));
    }

    try {
      final textFile = File(args['textPath']);
      final text = await textFile.readAsString();

      return await IsochronProcessor.process(
        text: text,
        audioPath: args['audioPath'],
        workDir: workDir,
        ffmpegPath: args['ffmpeg'],
        espeakPath: args['espeak'],
        transliterationRules: rules, // <--- Pass Map
      );
    } finally {
      workDir.deleteSync(recursive: true);
    }
  }

  // Save Output
  Future<void> _saveJson() async {
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Save Alignment JSON',
      fileName: 'alignment.json',
    );

    if (path != null) {
      final jsonOutput = _results
          .map(
            (f) => {
              'id': f.index,
              'text': f.text,
              'start': double.parse(f.realStart.toStringAsFixed(3)),
              'end': double.parse(f.realEnd.toStringAsFixed(3)),
            },
          )
          .toList();

      await File(path).writeAsString(jsonEncode(jsonOutput));
      setState(() => _status = "Saved to $path");
    }
  }

  void _showSettings() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Dependencies Configuration"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "Specify paths to binaries if they are not in your system PATH.",
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _ffmpegController,
              decoration: const InputDecoration(labelText: "FFmpeg Path"),
            ),
            TextField(
              controller: _espeakController,
              decoration: const InputDecoration(labelText: "eSpeak-ng Path"),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel"),
          ),
          ElevatedButton(onPressed: _saveSettings, child: const Text("Save")),
        ],
      ),
    );
  }

  void _showErrorDialog(String msg) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Alignment Failed"),
        content: Text(msg),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Isochron Aligner'),
        actions: [
          IconButton(
            onPressed: _showSettings,
            icon: const Icon(Icons.settings),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Input Area
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.description),
                      title: Text(
                        _textPath != null
                            ? p.basename(_textPath!)
                            : "No Text File Selected",
                      ),
                      trailing: ElevatedButton(
                        onPressed: () => _pickFile(false),
                        child: const Text("Browse"),
                      ),
                    ),
                    const Divider(),
                    ListTile(
                      leading: const Icon(Icons.audio_file),
                      title: Text(
                        _audioPath != null
                            ? p.basename(_audioPath!)
                            : "No Audio File Selected",
                      ),
                      trailing: ElevatedButton(
                        onPressed: () => _pickFile(true),
                        child: const Text("Browse"),
                      ),
                    ),
                    const Divider(),
                    ListTile(
                      leading: const Icon(Icons.translate),
                      title: Text(
                        _dictPath != null
                            ? p.basename(_dictPath!)
                            : "Optional: Select Transliteration JSON",
                      ),
                      subtitle: const Text(
                        "Map characters (e.g. Cyrillic) to Latin for eSpeak",
                      ),
                      trailing: _dictPath == null
                          ? ElevatedButton(
                              onPressed: _pickDict,
                              child: const Text("Browse"),
                            )
                          : IconButton(
                              onPressed: () => setState(() => _dictPath = null),
                              icon: const Icon(Icons.clear),
                            ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Action Button
            ElevatedButton(
              onPressed:
                  (_isProcessing || _textPath == null || _audioPath == null)
                  ? null
                  : _runAlignment,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.all(16),
              ),
              child: _isProcessing
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text("ALIGN TEXT & AUDIO"),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(_status, style: const TextStyle(color: Colors.grey)),
            ),
            const SizedBox(height: 16),

            // Results List
            Expanded(
              child: _results.isEmpty
                  ? const Center(child: Text("Results will appear here."))
                  : ListView.separated(
                      itemCount: _results.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final item = _results[index];
                        return ListTile(
                          dense: true,
                          leading: CircleAvatar(child: Text("${item.index}")),
                          title: Text(item.text),
                          subtitle: Text(
                            "${item.realStart.toStringAsFixed(2)}s  ➝  ${item.realEnd.toStringAsFixed(2)}s",
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.teal,
                            ),
                          ),
                        );
                      },
                    ),
            ),

            // Save Button
            if (_results.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: OutlinedButton.icon(
                  onPressed: _saveJson,
                  icon: const Icon(Icons.save),
                  label: const Text("Export JSON"),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
