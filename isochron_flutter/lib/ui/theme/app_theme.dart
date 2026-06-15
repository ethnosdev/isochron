import 'package:flutter/cupertino.dart';
import 'package:macos_ui/macos_ui.dart';

class AppTheme {
  AppTheme._();

  // --- ATELIER SONIC DESIGN SYSTEM PALETTE ---

  // Light Mode Colors (YAML Spec)
  static const Color lightBg = Color(0xFFF9F9FF);
  static const Color lightSurface = Color(0xFFF9F9FF);
  static const Color lightSurfaceDim = Color(0xFFCFDAF2);
  static const Color lightSurfaceContainerLow = Color(0xFFF0F3FF);
  static const Color lightSurfaceContainer = Color(0xFFE7EEFF);
  static const Color lightSurfaceContainerHigh = Color(0xFFDEE8FF);
  static const Color lightSurfaceContainerHighest = Color(0xFFD8E3FB);
  static const Color lightOnSurface = Color(0xFF111C2D);
  static const Color lightOnSurfaceVariant = Color(0xFF3D4947);
  static const Color lightOutline = Color(0xFF6D7A77);
  static const Color lightOutlineVariant = Color(0xFFBCC9C6);
  static const Color lightAccent = Color(0xFF00685F); // Forest Mint (primary)
  static const Color lightDestructive = Color(
    0xFFAC3400,
  ); // Terracotta (secondary)
  static const Color lightSuccess = Color(0xFF00685F); // Forest Mint
  static const Color lightWarning = Color(0xFF825100); // Amber Gold (tertiary)
  static const Color lightPlayhead = Color(0xFF825100); // Amber Gold
  static const Color lightGrey = Color(0xFF6D7A77); // outline

  // Dark Mode Colors (Inverted/Adapted YAML Spec for premium dark mode)
  static const Color darkBg = Color(
    0xFF111C2D,
  ); // on-surface becomes background
  static const Color darkSurface = Color(0xFF1E293B); // charcoal dark surface
  static const Color darkSurfaceDim = Color(0xFF0F172A);
  static const Color darkSurfaceContainerLow = Color(0xFF1E293B);
  static const Color darkSurfaceContainer = Color(0xFF334155);
  static const Color darkSurfaceContainerHigh = Color(0xFF475569);
  static const Color darkSurfaceContainerHighest = Color(0xFF64748B);
  static const Color darkOnSurface = Color(0xFFECF1FF); // inverse-on-surface
  static const Color darkOnSurfaceVariant = Color(
    0xFFBCC9C6,
  ); // outline-variant
  static const Color darkOutline = Color(0xFF6D7A77);
  static const Color darkOutlineVariant = Color(0xFF3D4947);
  static const Color darkAccent = Color(
    0xFF6BD8CB,
  ); // inverse-primary (Mint/Teal light)
  static const Color darkDestructive = Color(
    0xFFFD6B36,
  ); // secondary-container (Terracotta bright)
  static const Color darkSuccess = Color(0xFF6BD8CB);
  static const Color darkWarning = Color(0xFFE9C46A); // Gold
  static const Color darkPlayhead = Color(0xFFFFA300); // Amber Gold
  static const Color darkGrey = Color(0xFF6D7A77);

  // --- SEMANTIC RESOLVERS ---

  static Color accent(BuildContext context) {
    return MacosTheme.of(context).brightness == Brightness.dark
        ? darkAccent
        : lightAccent;
  }

  static Color destructive(BuildContext context) {
    return MacosTheme.of(context).brightness == Brightness.dark
        ? darkDestructive
        : lightDestructive;
  }

  static Color success(BuildContext context) {
    return MacosTheme.of(context).brightness == Brightness.dark
        ? darkSuccess
        : lightSuccess;
  }

  static Color warning(BuildContext context) {
    return MacosTheme.of(context).brightness == Brightness.dark
        ? darkWarning
        : lightWarning;
  }

  static Color playhead(BuildContext context) {
    return MacosTheme.of(context).brightness == Brightness.dark
        ? darkPlayhead
        : lightPlayhead;
  }

  static Color grey(BuildContext context) {
    return MacosTheme.of(context).brightness == Brightness.dark
        ? darkGrey
        : lightGrey;
  }

  static Color selectionBg(BuildContext context) {
    return MacosTheme.of(context).brightness == Brightness.dark
        ? darkSurfaceContainer
        : lightSurfaceContainerHighest;
  }

  static Color selectionText(BuildContext context) {
    return MacosTheme.of(context).brightness == Brightness.dark
        ? darkAccent
        : lightAccent;
  }
}
