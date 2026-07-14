import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_typography.dart';

/// Which "persona" of the app is active. Everyday driving/walking navigation
/// vs. offroad/backcountry trail use. Swaps accent color + default map
/// style; every other token stays the same so switching feels seamless.
enum AppMode { everyday, offroad }

abstract final class AppTheme {
  static ThemeData dark(AppMode mode) => _build(Brightness.dark, mode);
  static ThemeData light(AppMode mode) => _build(Brightness.light, mode);

  static ThemeData _build(Brightness brightness, AppMode mode) {
    final isDark = brightness == Brightness.dark;
    final accent =
        mode == AppMode.offroad ? AppColors.accentOffroad : AppColors.accentEveryday;
    final bg0 = isDark ? AppColors.darkBg0 : AppColors.lightBg0;
    final bg1 = isDark ? AppColors.darkBg1 : AppColors.lightBg1;
    final textPrimary = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final textSecondary =
        isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: accent,
      onPrimary: Colors.white,
      secondary: AppColors.accentOffroadSecondary,
      onSecondary: Colors.white,
      error: AppColors.danger,
      onError: Colors.white,
      surface: bg1,
      onSurface: textPrimary,
      surfaceContainerHighest: isDark ? AppColors.darkBg3 : AppColors.lightBg3,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: bg0,
      fontFamily: AppTypography.fontFamily,
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      textTheme: TextTheme(
        displayLarge: AppTypography.largeTitle.copyWith(color: textPrimary),
        headlineLarge: AppTypography.title1.copyWith(color: textPrimary),
        headlineMedium: AppTypography.title2.copyWith(color: textPrimary),
        headlineSmall: AppTypography.title3.copyWith(color: textPrimary),
        titleMedium: AppTypography.headline.copyWith(color: textPrimary),
        bodyLarge: AppTypography.body.copyWith(color: textPrimary),
        bodyMedium: AppTypography.callout.copyWith(color: textSecondary),
        bodySmall: AppTypography.subhead.copyWith(color: textSecondary),
        labelLarge: AppTypography.footnote.copyWith(color: textSecondary),
        labelMedium: AppTypography.caption1.copyWith(color: textSecondary),
        labelSmall: AppTypography.caption2.copyWith(color: textSecondary),
      ),
      iconTheme: IconThemeData(color: textPrimary, size: 22),
      dividerColor: isDark ? AppColors.darkHairline : AppColors.lightHairline,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleTextStyle: AppTypography.headline.copyWith(color: textPrimary),
        iconTheme: IconThemeData(color: textPrimary),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: accent,
        thumbColor: Colors.white,
        overlayColor: accent.withValues(alpha: 0.15),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: const WidgetStatePropertyAll(Colors.white),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? accent
              : (isDark ? AppColors.darkBg3 : AppColors.lightBg3),
        ),
      ),
      extensions: [
        AppGlassTheme(
          fill: isDark ? AppColors.glassDarkFill : AppColors.glassLightFill,
          border: isDark ? AppColors.glassDarkBorder : AppColors.glassLightBorder,
          raised: isDark ? AppColors.darkBg2 : AppColors.lightBg2,
          raised2: isDark ? AppColors.darkBg3 : AppColors.lightBg3,
          hairline: isDark ? AppColors.darkHairline : AppColors.lightHairline,
          textTertiary: isDark ? AppColors.darkTextTertiary : AppColors.lightTextTertiary,
        ),
      ],
    );
  }
}

/// Theme extension carrying the "glass" (BackdropFilter) surface tokens that
/// [ThemeData] has no first-class slot for.
class AppGlassTheme extends ThemeExtension<AppGlassTheme> {
  const AppGlassTheme({
    required this.fill,
    required this.border,
    required this.raised,
    required this.raised2,
    required this.hairline,
    required this.textTertiary,
  });

  final Color fill;
  final Color border;
  final Color raised;
  final Color raised2;
  final Color hairline;
  final Color textTertiary;

  @override
  AppGlassTheme copyWith({
    Color? fill,
    Color? border,
    Color? raised,
    Color? raised2,
    Color? hairline,
    Color? textTertiary,
  }) {
    return AppGlassTheme(
      fill: fill ?? this.fill,
      border: border ?? this.border,
      raised: raised ?? this.raised,
      raised2: raised2 ?? this.raised2,
      hairline: hairline ?? this.hairline,
      textTertiary: textTertiary ?? this.textTertiary,
    );
  }

  @override
  AppGlassTheme lerp(ThemeExtension<AppGlassTheme>? other, double t) {
    if (other is! AppGlassTheme) return this;
    return AppGlassTheme(
      fill: Color.lerp(fill, other.fill, t)!,
      border: Color.lerp(border, other.border, t)!,
      raised: Color.lerp(raised, other.raised, t)!,
      raised2: Color.lerp(raised2, other.raised2, t)!,
      hairline: Color.lerp(hairline, other.hairline, t)!,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
    );
  }
}

extension AppGlassThemeGetter on BuildContext {
  AppGlassTheme get glass => Theme.of(this).extension<AppGlassTheme>()!;
}
