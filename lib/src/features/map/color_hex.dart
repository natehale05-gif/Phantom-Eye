import 'package:flutter/material.dart';

/// MapLibre's annotation options take colors as `#rrggbb` hex strings, not
/// [Color] objects — this is the single conversion helper the map layer
/// uses everywhere it hands a color to the plugin.
extension ColorHex on Color {
  String toHex() {
    String twoDigits(int v) => v.toRadixString(16).padLeft(2, '0');
    return '#${twoDigits(r8)}${twoDigits(g8)}${twoDigits(b8)}';
  }

  int get r8 => (r * 255).round() & 0xff;
  int get g8 => (g * 255).round() & 0xff;
  int get b8 => (b * 255).round() & 0xff;
}
