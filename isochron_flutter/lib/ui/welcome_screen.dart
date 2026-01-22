import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:isochron_flutter/ui/project/creation_wizard.dart';
import 'package:isochron_flutter/ui/project/project_dashboard.dart';
import '../services/project_service.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final ProjectService _projectService = ProjectService();
  bool _isLoading = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 800),
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // --- Logo / Title ---
              const Icon(Icons.waves, size: 64, color: Colors.teal),
              const SizedBox(height: 16),
              const Text(
                "Isochron Studio",
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.w300),
              ),
              const SizedBox(height: 8),
              Text(
                "Forced Alignment & Audio Timings Editor",
                style: TextStyle(color: Colors.grey.shade600),
              ),
              const SizedBox(height: 48),

              // --- Action Cards ---
              if (_isLoading)
                const CircularProgressIndicator()
              else
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildActionCard(
                      icon: Icons.create_new_folder_outlined,
                      title: "New Project",
                      subtitle: "Import audio & text pairs",
                      onTap: _startNewProject,
                    ),
                    const SizedBox(width: 24),
                    _buildActionCard(
                      icon: Icons.folder_open_outlined,
                      title: "Open Project",
                      subtitle: "Select a project.json file",
                      onTap: _openProject,
                    ),
                  ],
                ),

              // --- Error Message ---
              if (_error != null) ...[
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Text(
                    _error!,
                    style: TextStyle(color: Colors.red.shade800),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 2,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 240,
          height: 180,
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 48, color: Colors.teal),
              const SizedBox(height: 16),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _startNewProject() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const ProjectCreationWizard()));
  }

  Future<void> _openProject() async {
    setState(() {
      _error = null;
      _isLoading = true;
    });

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        dialogTitle: "Select Project File",
      );

      if (result != null && result.files.single.path != null) {
        final path = result.files.single.path!;

        // Load the project using your service
        final project = await _projectService.loadProject(path);

        if (mounted) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ProjectDashboard(project: project),
            ),
          );
        }
      }
    } catch (e) {
      setState(() {
        _error = "Failed to load project: $e";
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }
}
