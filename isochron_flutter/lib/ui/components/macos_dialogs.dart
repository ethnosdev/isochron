import 'package:flutter/material.dart';
import 'package:macos_ui/macos_ui.dart';

/// Displays a [MacosSheet] or modal sheet above the current application
/// with standard macOS dialog transitions (smooth ease-out fade and subtle scale,
/// with no bouncing physics).
Future<T?> showAppSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = false,
  Color? barrierColor,
  String? barrierLabel,
  bool useRootNavigator = true,
  RouteSettings? routeSettings,
}) {
  final resolvedBarrierColor = barrierColor ??
      (MacosTheme.of(context).brightness == Brightness.dark
          ? const Color(0x80000000)
          : const Color(0x55000000));

  return Navigator.of(context, rootNavigator: useRootNavigator).push<T>(
    _NormalDialogRoute<T>(
      settings: routeSettings,
      pageBuilder: (context, animation, secondaryAnimation) {
        return builder(context);
      },
      barrierDismissible: barrierDismissible,
      barrierColor: resolvedBarrierColor,
      barrierLabel: barrierLabel ??
          (barrierDismissible ? 'Dismiss' : null),
    ),
  );
}

/// Displays a [MacosAlertDialog] above the current contents of the app
/// with standard macOS dialog transitions (smooth ease-out fade and subtle scale,
/// with no bouncing physics).
Future<T?> showAppAlertDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = false,
  Color? barrierColor,
  String? barrierLabel,
  bool useRootNavigator = true,
  RouteSettings? routeSettings,
}) {
  final resolvedBarrierColor = barrierColor ??
      (MacosTheme.of(context).brightness == Brightness.dark
          ? const Color(0x80000000)
          : const Color(0x55000000));

  return Navigator.of(context, rootNavigator: useRootNavigator).push<T>(
    _NormalDialogRoute<T>(
      settings: routeSettings,
      pageBuilder: (context, animation, secondaryAnimation) {
        return builder(context);
      },
      barrierDismissible: barrierDismissible,
      barrierColor: resolvedBarrierColor,
      barrierLabel: barrierLabel ??
          (barrierDismissible ? 'Dismiss' : null),
    ),
  );
}

class _NormalDialogRoute<T> extends PopupRoute<T> {
  _NormalDialogRoute({
    required RoutePageBuilder pageBuilder,
    bool barrierDismissible = false,
    Color? barrierColor = const Color(0x80000000),
    String? barrierLabel,
    super.settings,
  })  : _pageBuilder = pageBuilder,
        _barrierDismissible = barrierDismissible,
        _barrierLabel = barrierLabel,
        _barrierColor = barrierColor;

  final RoutePageBuilder _pageBuilder;

  @override
  bool get barrierDismissible => _barrierDismissible;
  final bool _barrierDismissible;

  @override
  String? get barrierLabel => _barrierLabel;
  final String? _barrierLabel;

  @override
  Color? get barrierColor => _barrierColor;
  final Color? _barrierColor;

  @override
  Curve get barrierCurve => Curves.linear;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 180);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 120);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return Semantics(
      scopesRoute: true,
      explicitChildNodes: true,
      child: _pageBuilder(context, animation, secondaryAnimation),
    );
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curvedAnimation = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    return FadeTransition(
      opacity: curvedAnimation,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.96, end: 1.0).animate(curvedAnimation),
        child: child,
      ),
    );
  }
}
