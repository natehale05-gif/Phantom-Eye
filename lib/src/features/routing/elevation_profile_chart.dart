import 'package:flutter/material.dart';

import '../../models/geo_point.dart';
import '../../models/unit_system.dart';
import '../../theme/app_colors.dart';

/// Lightweight custom-painted elevation profile — deliberately not backed
/// by a charting package: it's a single filled polyline against
/// distance/elevation, which a `CustomPainter` does in ~40 lines with zero
/// added dependency weight.
class ElevationProfileChart extends StatelessWidget {
  const ElevationProfileChart({super.key, required this.profile, required this.units, this.height = 90});

  final List<ElevationPoint> profile;
  final UnitSystem units;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (profile.length < 2) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text(
            'Elevation profile unavailable',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      );
    }
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _ElevationPainter(profile: profile, color: Theme.of(context).colorScheme.primary),
      ),
    );
  }
}

class _ElevationPainter extends CustomPainter {
  _ElevationPainter({required this.profile, required this.color});

  final List<ElevationPoint> profile;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final minEle = profile.map((p) => p.elevationMeters).reduce((a, b) => a < b ? a : b);
    final maxEle = profile.map((p) => p.elevationMeters).reduce((a, b) => a > b ? a : b);
    final range = (maxEle - minEle).abs() < 1 ? 1.0 : (maxEle - minEle);
    final maxDistance = profile.last.distanceFromStartMeters == 0
        ? 1.0
        : profile.last.distanceFromStartMeters;

    final path = Path();
    final fillPath = Path();
    for (var i = 0; i < profile.length; i++) {
      final x = (profile[i].distanceFromStartMeters / maxDistance) * size.width;
      final normalized = (profile[i].elevationMeters - minEle) / range;
      final y = size.height - (normalized * size.height * 0.85) - 4;
      if (i == 0) {
        path.moveTo(x, y);
        fillPath.moveTo(x, size.height);
        fillPath.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }
    fillPath.lineTo(size.width, size.height);
    fillPath.close();

    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.35), color.withValues(alpha: 0.02)],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round,
    );

    // Baseline hairline.
    canvas.drawLine(
      Offset(0, size.height - 0.5),
      Offset(size.width, size.height - 0.5),
      Paint()..color = AppColors.darkHairline,
    );
  }

  @override
  bool shouldRepaint(covariant _ElevationPainter oldDelegate) =>
      oldDelegate.profile != profile || oldDelegate.color != color;
}
