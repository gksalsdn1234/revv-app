import 'package:flutter/material.dart';

class AppColors {
  static const bg      = Color(0xFF080102);
  static const panel   = Color(0xFF0D0407);
  static const panel2  = Color(0xFF150608);
  static const surface = Color(0xFF1A0A0C);
  static const red     = Color(0xFFE3000F);
  static const redGlow = Color(0x99E3000F);
  static const redDim  = Color(0x33E3000F);
  static const orange  = Color(0xFFFF5500);
  static const cyan    = Color(0xFF00C8D4);
  static const white   = Colors.white;
  static const gray    = Color(0x40FFFFFF);

  // Text hierarchy
  static const textPrimary   = Color(0xFFE2E8F0);
  static const textSecondary = Color(0xFF94A3B8);
  static const textHint      = Color(0xFF475569);

  // Divider
  static const divider = Color(0xFF1E293B);

  static Color gForceColor(double mag) {
    final t = (mag / 1.2).clamp(0.0, 1.0);
    if (t < 0.42) {
      return Color.lerp(const Color(0xFF1565C0), const Color(0xFFFDD835), t / 0.42)!;
    }
    return Color.lerp(
      const Color(0xFFFDD835),
      const Color(0xFFE53935),
      ((t - 0.42) / 0.58).clamp(0.0, 1.0),
    )!;
  }
}
