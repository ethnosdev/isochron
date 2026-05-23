import 'package:flutter/cupertino.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:isochron_flutter/ui/theme/app_theme.dart';

class WelcomeView extends StatelessWidget {
  final VoidCallback onCreateNewProject;
  final VoidCallback onOpenProject;

  const WelcomeView({
    super.key,
    required this.onCreateNewProject,
    required this.onOpenProject,
  });

  @override
  Widget build(BuildContext context) {
    return MacosWindow(
      key: const ValueKey('welcome_window'),
      child: MacosScaffold(
        children: [
          ContentArea(
            builder: (context, scrollController) => Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  MacosIcon(
                    CupertinoIcons.waveform_path_ecg,
                    size: 80,
                    color: AppTheme.accent(context),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    "Isochron Studio",
                    style: MacosTheme.of(context).typography.largeTitle
                        .copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 48),
                  PushButton(
                    controlSize: ControlSize.large,
                    onPressed: onCreateNewProject,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 24.0),
                      child: Text("Create New Project"),
                    ),
                  ),
                  const SizedBox(height: 16),
                  PushButton(
                    controlSize: ControlSize.large,
                    secondary: true,
                    onPressed: onOpenProject,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 24.0),
                      child: Text("Open Existing Project"),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
