import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/theme.dart';

/// The frosted-glass "material" used for every floating control, chip, and
/// sheet in the app (search bar, weather chip, control stack, bottom
/// sheets...). Wraps [BackdropFilter] + a translucent fill + a 1px hairline
/// border, which is the closest Flutter-native equivalent to iOS's
/// `UIVisualEffectView` blur materials.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(AppRadius.lg)),
    this.blurSigma = 24,
    this.padding,
    this.color,
    this.borderColor,
    this.elevated = false,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final double blurSigma;
  final EdgeInsetsGeometry? padding;
  final Color? color;
  final Color? borderColor;

  /// Adds a soft drop shadow — use for controls that float directly over
  /// the map (as opposed to sheets docked to an edge).
  final bool elevated;

  @override
  Widget build(BuildContext context) {
    final glass = context.glass;
    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: color ?? glass.fill,
            borderRadius: borderRadius,
            border: Border.all(color: borderColor ?? glass.border, width: 1),
            boxShadow: elevated
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.28),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ]
                : null,
          ),
          child: child,
        ),
      ),
    );
  }
}

/// A circular glass icon button — used for the map control stack (locate
/// me, compass, layers, route-builder, mesh).
class GlassIconButton extends StatelessWidget {
  const GlassIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.size = 44,
    this.iconSize = 20,
    this.active = false,
    this.activeColor,
    this.tooltip,
    this.badge,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final double size;
  final double iconSize;
  final bool active;
  final Color? activeColor;
  final String? tooltip;
  final Widget? badge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = active ? (activeColor ?? theme.colorScheme.primary) : theme.iconTheme.color;
    final button = GlassSurface(
      elevated: true,
      borderRadius: BorderRadius.circular(size / 2),
      color: active
          ? (activeColor ?? theme.colorScheme.primary).withValues(alpha: 0.22)
          : null,
      child: SizedBox(
        width: size,
        height: size,
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Center(child: Icon(icon, size: iconSize, color: color)),
          ),
        ),
      ),
    );
    final content = tooltip != null ? Tooltip(message: tooltip!, child: button) : button;
    if (badge == null) return content;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        content,
        Positioned(right: -2, top: -2, child: badge!),
      ],
    );
  }
}

/// Small rounded pill, e.g. "24 min · 3.1 mi", profile switch segments,
/// category chips in search.
class GlassPill extends StatelessWidget {
  const GlassPill({
    super.key,
    required this.child,
    this.onTap,
    this.selected = false,
    this.selectedColor,
    this.padding = const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
  });

  final Widget child;
  final VoidCallback? onTap;
  final bool selected;
  final Color? selectedColor;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = selectedColor ?? theme.colorScheme.primary;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppDurations.fast,
        padding: padding,
        decoration: BoxDecoration(
          color: selected ? accent : context.glass.raised,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(
            color: selected ? accent : context.glass.hairline,
          ),
        ),
        child: DefaultTextStyle.merge(
          style: TextStyle(color: selected ? Colors.white : null),
          child: child,
        ),
      ),
    );
  }
}
