import 'package:flutter/cupertino.dart';

/// Design tokens: color palette.
///
/// Phantom Eye ships two "moods":
///  * Everyday (Maps) — restrained iOS-system-blue accent, matches the
///    "feels like an Apple product" ask.
///  * Offroad (Backcountry/Hunt) — a warmer, higher-contrast palette (burnt
///    orange + olive) that reads better on topo/satellite imagery and in
///    direct sunlight, echoing onX/Gaia GPS conventions.
///
/// No design handoff existed for this project, so these tokens were
/// authored from scratch to read as a native, modern Apple-platform app on
/// both iOS and Android (Material widgets are deliberately avoided in favor
/// of Cupertino-flavored custom widgets almost everywhere).
abstract final class AppColors {
  // Brand / accent
  static const Color accentEveryday = Color(0xFF0A84FF); // iOS system blue
  static const Color accentOffroad = Color(0xFFFF7A1A); // burnt orange
  static const Color accentOffroadSecondary = Color(0xFF6B7A3A); // olive

  // Semantic
  static const Color success = Color(0xFF34C759);
  static const Color warning = Color(0xFFFF9F0A);
  static const Color danger = Color(0xFFFF453A);
  static const Color elevationGain = Color(0xFFFF7A1A);
  static const Color elevationLoss = Color(0xFF5AC8FA);

  // Neutrals — dark theme (primary theme; navigation apps live at night a lot)
  static const Color darkBg0 = Color(0xFF06070A); // deepest background
  static const Color darkBg1 = Color(0xFF0D0F14); // base background
  static const Color darkBg2 = Color(0xFF15181F); // raised surface
  static const Color darkBg3 = Color(0xFF1F232C); // higher raised surface
  static const Color darkHairline = Color(0x1FFFFFFF);
  static const Color darkTextPrimary = Color(0xFFF5F6F8);
  static const Color darkTextSecondary = Color(0xB3F5F6F8); // 70%
  static const Color darkTextTertiary = Color(0x66F5F6F8); // 40%

  // Neutrals — light theme
  static const Color lightBg0 = Color(0xFFF2F3F5);
  static const Color lightBg1 = Color(0xFFFFFFFF);
  static const Color lightBg2 = Color(0xFFF7F8FA);
  static const Color lightBg3 = Color(0xFFEDEFF2);
  static const Color lightHairline = Color(0x1F000000);
  static const Color lightTextPrimary = Color(0xFF14161A);
  static const Color lightTextSecondary = Color(0xB314161A);
  static const Color lightTextTertiary = Color(0x6614161A);

  // Glass / blur overlays (used with BackdropFilter)
  static const Color glassDarkFill = Color(0xB3101216); // ~70% opacity
  static const Color glassLightFill = Color(0xCCFFFFFF); // ~80% opacity
  static const Color glassDarkBorder = Color(0x24FFFFFF);
  static const Color glassLightBorder = Color(0x1A000000);

  // Mesh / friends
  static const List<Color> meshPalette = <Color>[
    Color(0xFF34C759), // green
    Color(0xFF0A84FF), // blue
    Color(0xFFFF9F0A), // amber
    Color(0xFFBF5AF2), // purple
    Color(0xFFFF453A), // red
    Color(0xFF64D2FF), // cyan
    Color(0xFFFFD60A), // yellow
  ];

  static Color meshColorForNodeNum(int nodeNum) =>
      meshPalette[nodeNum.abs() % meshPalette.length];
}
