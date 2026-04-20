import 'package:flutter/material.dart';

class AppColors {
  static const bg = Color(0xFF131314);
  static const panel = Color(0xFF1C1B1C);
  static const panel2 = Color(0xFF201F20);
  static const surface = Color(0xFF2A2A2B);
  static const red = Color(0xFF00E5FF);
  static const redGlow = Color(0x6600E5FF);
  static const redDim = Color(0x3300E5FF);
  static const orange = Color(0xFFFEB300);
  static const cyan = Color(0xFF00DAF3);
  static const white = Colors.white;
  static const gray = Color(0x40FFFFFF);

  static const surfaceLowest = Color(0xFF0E0E0F);
  static const surfaceHigh = Color(0xFF353436);
  static const surfaceBright = Color(0xFF3A393A);
  static const outline = Color(0xFF849396);
  static const outlineVariant = Color(0xFF3B494C);
  static const success = Color(0xFF59D98E);
  static const warning = Color(0xFFFEB300);
  static const danger = Color(0xFFFF6F61);
  static const primaryContainer = Color(0xFF00E5FF);
  static const onPrimary = Color(0xFF00363D);

  // Text hierarchy
  static const textPrimary = Color(0xFFE5E2E3);
  static const textSecondary = Color(0xFFBAC9CC);
  static const textHint = Color(0xFF849396);

  // Divider
  static const divider = Color(0xFF3B494C);

  static Color gForceColor(double mag) {
    final t = (mag / 1.2).clamp(0.0, 1.0);
    if (t < 0.42) {
      return Color.lerp(
        const Color(0xFF1565C0),
        const Color(0xFFFDD835),
        t / 0.42,
      )!;
    }
    return Color.lerp(
      const Color(0xFFFDD835),
      const Color(0xFFE53935),
      ((t - 0.42) / 0.58).clamp(0.0, 1.0),
    )!;
  }
}
