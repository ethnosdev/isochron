import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:isochron_flutter/ui/workspace/models/workspace_models.dart';
import 'package:isochron_flutter/ui/workspace/workspace_manager.dart';

class WorkspaceMenuBar extends StatelessWidget {
  final Widget child;
  final WorkspaceManager manager;
  final VoidCallback onCreateNewProject;
  final VoidCallback onOpenProject;
  final VoidCallback onImportCollections;
  final VoidCallback onCloseProject;
  final VoidCallback onOpenSettings;

  const WorkspaceMenuBar({
    super.key,
    required this.child,
    required this.manager,
    required this.onCreateNewProject,
    required this.onOpenProject,
    required this.onImportCollections,
    required this.onCloseProject,
    required this.onOpenSettings,
  });

  List<PlatformMenuItem> _buildMenus() {
    return [
      PlatformMenu(
        label: 'Isochron Studio',
        menus: [
          const PlatformProvidedMenuItem(
            type: PlatformProvidedMenuItemType.about,
          ),
          if (manager.project != null)
            PlatformMenuItem(
              label: 'Settings...',
              shortcut: const SingleActivator(
                LogicalKeyboardKey.comma,
                meta: true,
              ),
              onSelected: onOpenSettings,
            ),
          const PlatformProvidedMenuItem(
            type: PlatformProvidedMenuItemType.quit,
          ),
        ],
      ),
      PlatformMenu(
        label: 'File',
        menus: [
          PlatformMenuItemGroup(
            members: [
              PlatformMenuItem(
                label: 'New Project...',
                shortcut: const SingleActivator(
                  LogicalKeyboardKey.keyN,
                  meta: true,
                ),
                onSelected: onCreateNewProject,
              ),
              PlatformMenuItem(
                label: 'Open Project...',
                shortcut: const SingleActivator(
                  LogicalKeyboardKey.keyO,
                  meta: true,
                ),
                onSelected: onOpenProject,
              ),
            ],
          ),
          if (manager.project != null)
            PlatformMenuItemGroup(
              members: [
                PlatformMenuItem(
                  label: 'Import Collections from Project...',
                  shortcut: const SingleActivator(
                    LogicalKeyboardKey.keyI,
                    meta: true,
                    shift: true,
                  ),
                  onSelected: onImportCollections,
                ),
                PlatformMenuItem(
                  label: 'Save',
                  shortcut: const SingleActivator(
                    LogicalKeyboardKey.keyS,
                    meta: true,
                  ),
                  onSelected:
                      (manager.selectedNode?.type == NodeType.track &&
                          !manager.hasUnsavedChanges)
                      ? null
                      : manager.saveProject,
                ),
              ],
            ),
          if (manager.project != null)
            PlatformMenuItemGroup(
              members: [
                PlatformMenuItem(
                  label: 'Close Project',
                  shortcut: const SingleActivator(
                    LogicalKeyboardKey.keyW,
                    meta: true,
                  ),
                  onSelected: onCloseProject,
                ),
              ],
            ),
        ],
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return PlatformMenuBar(menus: _buildMenus(), child: child);
  }
}
