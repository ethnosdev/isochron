
import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:isochron_flutter/services/user_settings_service.dart';
import 'package:isochron_flutter/ui/components/macos_dialogs.dart';
import 'package:isochron_flutter/ui/workspace/models/workspace_models.dart';
import 'package:isochron_flutter/ui/workspace/views/welcome_view.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:path/path.dart' as p;

// --- Workspace Architecture ---
import 'workspace_manager.dart';
import 'components/workspace_sidebar.dart';
import 'components/workspace_router.dart';
import 'components/workspace_toolbar.dart';
import 'components/workspace_menu_bar.dart';
import 'components/group_export_dialog.dart';
import 'components/new_project_dialog.dart';

class WorkspaceScreen extends StatefulWidget {
  const WorkspaceScreen({super.key});

  @override
  State<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

class _WorkspaceScreenState extends State<WorkspaceScreen> {
  late final WorkspaceManager _manager;

  @override
  void initState() {
    super.initState();
    _manager = WorkspaceManager();
    // Rebuild the UI when the manager's state changes
    _manager.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _manager.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // PROJECT UI ACTIONS (Dialogs & File Pickers)
  // ---------------------------------------------------------------------------

  Future<void> _createNewProject() async {
    final result = await NewProjectDialog.show(context);
    if (result == null) return;

    final settings = UserSettingsService();
    settings.setLastProjectDir(p.dirname(result.projectPath));

    await _manager.createProject(
      result.projectPath,
      result.projectName,
      firstCollectionName: result.collectionName,
      initialTracks: result.initialTracks,
    );
    if (_manager.project != null) {
      await settings.addRecentProject(_manager.project!.projectFilePath);
    }
  }

  Future<void> _openProject() async {
    try {
      final settings = UserSettingsService();
      final result = await FilePicker.pickFiles(
        dialogTitle: 'Open Project',
        type: FileType.custom,
        allowedExtensions: ['json'],
        initialDirectory: settings.lastProjectDir,
      );

      if (result != null && result.files.single.path != null) {
        final path = result.files.single.path!;
        settings.setLastProjectDir(p.dirname(path));
        await _manager.openProject(path);
        await settings.addRecentProject(path);
      }
    } catch (e) {
      debugPrint("Error: $e");
    }
  }

  Future<void> _openRecentProject(String path) async {
    try {
      final settings = UserSettingsService();
      settings.setLastProjectDir(p.dirname(path));
      await _manager.openProject(path);
      await settings.addRecentProject(path);
    } catch (e) {
      debugPrint("Error: $e");
    }
  }

  Future<void> _importCollectionsFromProject() async {
    if (_manager.project == null) return;

    final settings = UserSettingsService();
    final result = await FilePicker.pickFiles(
      dialogTitle: 'Import Collections from Project',
      type: FileType.custom,
      allowedExtensions: ['json'],
      initialDirectory: settings.lastProjectDir,
    );

    if (result != null && result.files.single.path != null) {
      try {
        final importResult = await _manager.importCollections(
          result.files.single.path!,
        );

        if (mounted) {
          showAppAlertDialog(
            context: context,
            builder: (context) => MacosAlertDialog(
              appIcon: const MacosIcon(CupertinoIcons.check_mark_circled),
              title: const Text('Import Complete'),
              message: Text(
                'Successfully imported ${importResult.collectionsCount} collection(s) containing ${importResult.tracksCount} tracks.',
                textAlign: TextAlign.center,
              ),
              primaryButton: PushButton(
                controlSize: ControlSize.large,
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ),
          );
        }
      } catch (e) {
        debugPrint("Error importing collections: $e");
        if (mounted) {
          showAppAlertDialog(
            context: context,
            builder: (context) => MacosAlertDialog(
              appIcon: const MacosIcon(CupertinoIcons.exclamationmark_triangle),
              title: const Text('Import Failed'),
              message: Text(
                'Could not parse the selected project file.\n\nError: $e',
                textAlign: TextAlign.center,
              ),
              primaryButton: PushButton(
                controlSize: ControlSize.large,
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ),
          );
        }
      }
    }
  }

  // ---------------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    // 1. Uninitialized State (Welcome View)
    if (_manager.project == null) {
      return WorkspaceMenuBar(
        manager: _manager,
        onCreateNewProject: _createNewProject,
        onOpenProject: _openProject,
        onImportCollections: () {},
        onCloseProject: () {},
        onOpenSettings: () {},
        child: WelcomeView(
          onCreateNewProject: _createNewProject,
          onOpenProject: _openProject,
          onOpenRecentProject: _openRecentProject,
        ),
      );
    }

    // 2. Initialized State (Main Workspace)
    return WorkspaceMenuBar(
      manager: _manager,
      onCreateNewProject: _createNewProject,
      onOpenProject: _openProject,
      onImportCollections: _importCollectionsFromProject,
      onExportCollectionTimings: _manager.selectedNode?.collection != null
          ? () => GroupExportDialog.show(
                context,
                project: _manager.project!,
                collection: _manager.selectedNode!.collection!,
              )
          : null,
      onExportProjectTimings: () => GroupExportDialog.show(
        context,
        project: _manager.project!,
      ),
      onCloseProject: () async {
        await _manager.homeManager.flushPendingAutoSave();
        _manager.closeProject();
      },
      onOpenSettings: () async {
        await _manager.homeManager.flushPendingAutoSave();
        _manager.selectNode(TreeSelection(type: NodeType.settings));
      },
      child: MacosWindow(
        key: const ValueKey('main_workspace_window'),
        sidebar: buildWorkspaceSidebar(context, _manager),
        child: MacosScaffold(
          toolBar: buildWorkspaceToolbar(context, _manager),
          children: [
            ContentArea(
              builder: (context, scrollController) =>
                  WorkspaceRouter(manager: _manager),
            ),
          ],
        ),
      ),
    );
  }
}
