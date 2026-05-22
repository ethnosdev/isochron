import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:isochron_flutter/services/user_settings_service.dart';
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
    final settings = UserSettingsService();

    final String? projectPath = await FilePicker.saveFile(
      dialogTitle: 'Create New Project',
      fileName: 'Untitled Project',
      initialDirectory: settings.lastProjectDir,
      lockParentWindow: true,
    );

    if (projectPath == null) return;

    final projectDir = Directory(projectPath);
    final projectName = p.basename(projectPath);

    if (await projectDir.exists()) {
      if (mounted) {
        showMacosAlertDialog(
          context: context,
          builder: (context) => MacosAlertDialog(
            appIcon: const MacosIcon(CupertinoIcons.folder_badge_minus),
            title: const Text('Folder Already Exists'),
            message: Text(
              'A project or folder named "$projectName" already exists in this location.\n\nPlease choose a different name or location.',
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
      return;
    }

    settings.setLastProjectDir(p.dirname(projectPath));
    await _manager.createProject(projectPath, projectName);
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
        settings.setLastProjectDir(p.dirname(result.files.single.path!));
        await _manager.openProject(result.files.single.path!);
      }
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
          showMacosAlertDialog(
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
          showMacosAlertDialog(
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

  Future<bool> _requestCloseEditor() async {
    if (_manager.selectedNode?.type == NodeType.track &&
        _manager.hasUnsavedChanges) {
      final result = await showCupertinoDialog<String>(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: const Text('Unsaved Changes'),
          content: const Text(
            'You have unsaved changes in your alignment. Save before leaving?',
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(context, 'cancel'),
              child: const Text('Cancel'),
            ),
            CupertinoDialogAction(
              isDestructiveAction: true,
              onPressed: () => Navigator.pop(context, 'discard'),
              child: const Text('Discard'),
            ),
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () => Navigator.pop(context, 'save'),
              child: const Text('Save'),
            ),
          ],
        ),
      );

      if (result == 'save') {
        _manager.saveProject();
        return true;
      } else if (result == 'discard') {
        await _manager.homeManager.discardChanges();
        return true;
      } else {
        return false;
      }
    }
    return true;
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
        ),
      );
    }

    // 2. Initialized State (Main Workspace)
    return WorkspaceMenuBar(
      manager: _manager,
      onCreateNewProject: _createNewProject,
      onOpenProject: _openProject,
      onImportCollections: _importCollectionsFromProject,
      onCloseProject: () async {
        if (await _requestCloseEditor()) _manager.closeProject();
      },
      onOpenSettings: () async {
        if (await _requestCloseEditor()) {
          _manager.selectNode(TreeSelection(type: NodeType.settings));
        }
      },
      child: MacosWindow(
        key: const ValueKey('main_workspace_window'),
        sidebar: buildWorkspaceSidebar(context, _manager, _requestCloseEditor),
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
