import 'package:flutter/cupertino.dart';
import 'package:isochron_cli/isochron_cli.dart';
import 'package:isochron_flutter/services/user_settings_service.dart';
import 'package:isochron_flutter/ui/settings/model_panel.dart';
import 'package:isochron_flutter/ui/theme/app_theme.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:path/path.dart' as p;

class WelcomeView extends StatefulWidget {
  final VoidCallback onCreateNewProject;
  final VoidCallback onOpenProject;
  final ValueChanged<String> onOpenRecentProject;

  const WelcomeView({
    super.key,
    required this.onCreateNewProject,
    required this.onOpenProject,
    required this.onOpenRecentProject,
  });

  @override
  State<WelcomeView> createState() => _WelcomeViewState();
}

class _WelcomeViewState extends State<WelcomeView> {
  ModelStatus _modelStatus = ModelStatus.notDownloaded;

  @override
  void initState() {
    super.initState();
    _checkModelStatus();
  }

  Future<void> _checkModelStatus() async {
    try {
      final status = await ModelManager().checkStatus(ModelVariant.int8);
      if (mounted) {
        setState(() => _modelStatus = status);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final theme = MacosTheme.of(context);
    final recentProjects = UserSettingsService().recentProjectPaths;
    final isModelReady = _modelStatus == ModelStatus.ready;

    return MacosWindow(
      key: const ValueKey('welcome_window'),
      child: MacosScaffold(
        children: [
          ContentArea(
            builder: (context, scrollController) => Center(
              child: Container(
                constraints: const BoxConstraints(
                  maxWidth: 760,
                  maxHeight: 460,
                ),
                decoration: BoxDecoration(
                  color: theme.canvasColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: theme.dividerColor,
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: CupertinoColors.black.withValues(alpha: 0.12),
                      blurRadius: 24,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Left Column (280px)
                    Container(
                      width: 280,
                      padding: const EdgeInsets.all(24.0),
                      decoration: BoxDecoration(
                        border: Border(
                          right: BorderSide(color: theme.dividerColor),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          MacosIcon(
                            CupertinoIcons.waveform_path_ecg,
                            size: 56,
                            color: AppTheme.accent(context),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            "Isochron Studio",
                            style: theme.typography.largeTitle.copyWith(
                              fontWeight: FontWeight.bold,
                              fontSize: 22,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            "Multilingual Forced Alignment",
                            style: theme.typography.subheadline.copyWith(
                              color: AppTheme.grey(context),
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 28),
                          SizedBox(
                            width: double.infinity,
                            child: PushButton(
                              controlSize: ControlSize.large,
                              onPressed: widget.onCreateNewProject,
                              child: const Text("Create New Project..."),
                            ),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: PushButton(
                              controlSize: ControlSize.large,
                              secondary: true,
                              onPressed: widget.onOpenProject,
                              child: const Text("Open Project..."),
                            ),
                          ),
                          const Spacer(),

                          // Acoustic Model Status Card
                          GestureDetector(
                            onTap: () {
                              ModelPanel.show(
                                context,
                                onModelReady: () {
                                  _checkModelStatus();
                                },
                              );
                            },
                            behavior: HitTestBehavior.opaque,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.selectionBg(context)
                                    .withValues(alpha: 0.25),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: theme.dividerColor.withValues(
                                    alpha: 0.5,
                                  ),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: isModelReady
                                          ? AppTheme.success(context)
                                          : AppTheme.warning(context),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      isModelReady
                                          ? "MMS Acoustic Model: Ready"
                                          : "MMS Model Required — Setup...",
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w500,
                                        color: theme.typography.body.color,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Icon(
                                    CupertinoIcons.chevron_right,
                                    size: 11,
                                    color: AppTheme.grey(context),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Right Column (Expanded, Recent Projects)
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 20,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Recent Projects",
                              style: theme.typography.headline.copyWith(
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Expanded(
                              child: recentProjects.isEmpty
                                  ? Center(
                                      child: Text(
                                        "No recent projects.",
                                        style: TextStyle(
                                          color: AppTheme.grey(context),
                                          fontSize: 13,
                                        ),
                                      ),
                                    )
                                  : ListView.separated(
                                      itemCount: recentProjects.length,
                                      separatorBuilder: (context, index) => Container(
                                        height: 1,
                                        color: theme.dividerColor.withValues(
                                          alpha: 0.5,
                                        ),
                                      ),
                                      itemBuilder: (context, index) {
                                        final path = recentProjects[index];
                                        final projectName = p.basename(
                                          p.dirname(path),
                                        );
                                        final directory = p.dirname(path);

                                        return _RecentProjectRow(
                                          name: projectName.isNotEmpty
                                              ? projectName
                                              : p.basename(path),
                                          directory: directory,
                                          onTap: () =>
                                              widget.onOpenRecentProject(path),
                                        );
                                      },
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentProjectRow extends StatefulWidget {
  final String name;
  final String directory;
  final VoidCallback onTap;

  const _RecentProjectRow({
    required this.name,
    required this.directory,
    required this.onTap,
  });

  @override
  State<_RecentProjectRow> createState() => _RecentProjectRowState();
}

class _RecentProjectRowState extends State<_RecentProjectRow> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = MacosTheme.of(context);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: _isHovered
                ? AppTheme.selectionBg(context).withValues(alpha: 0.3)
                : CupertinoColors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              Icon(
                CupertinoIcons.folder,
                size: 16,
                color: AppTheme.accent(context),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.directory,
                      style: TextStyle(
                        fontSize: 11,
                        color: AppTheme.grey(context),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                CupertinoIcons.chevron_right,
                size: 12,
                color: _isHovered
                    ? theme.typography.body.color
                    : CupertinoColors.transparent,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
