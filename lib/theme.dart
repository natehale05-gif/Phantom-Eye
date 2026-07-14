import 'dart:ui';
import 'package:flutter/cupertino.dart';

/// Apple-inspired visual language: deep space background, translucent
/// "frosted glass" surfaces, hairline strokes, and a single system-blue accent.
class PhantomColors {
  static const background = Color(0xFF05070C);
  static const accent = Color(0xFF0A84FF);

  static const text = Color(0xF2FFFFFF);
  static const textDim = Color(0x94FFFFFF);
  static const textFaint = Color(0x61FFFFFF);

  static const glass = Color(0x8C16181E);
  static const glassStroke = Color(0x24FFFFFF);
  static const danger = Color(0xFFFF6B6B);
  static const online = Color(0xFF32D74B);
}

class PhantomText {
  static const _family = '.SF Pro Text';

  static const largeTitle = TextStyle(
    fontFamily: _family,
    fontSize: 32,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.4,
    color: PhantomColors.text,
  );
  static const title = TextStyle(
    fontFamily: _family,
    fontSize: 17,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.2,
    color: PhantomColors.text,
  );
  static const body = TextStyle(
    fontFamily: _family,
    fontSize: 15,
    color: PhantomColors.text,
  );
  static const dim = TextStyle(
    fontFamily: _family,
    fontSize: 13.5,
    color: PhantomColors.textDim,
  );
  static const overline = TextStyle(
    fontFamily: _family,
    fontSize: 12,
    fontWeight: FontWeight.w600,
    letterSpacing: 1.4,
    color: PhantomColors.textFaint,
  );
}

/// A reusable frosted-glass surface.
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.radius = 20,
    this.padding,
    this.blur = 28,
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry? padding;
  final double blur;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: PhantomColors.glass,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: PhantomColors.glassStroke, width: 1),
            boxShadow: const [
              BoxShadow(
                color: Color(0x73000000),
                blurRadius: 40,
                offset: Offset(0, 12),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}
