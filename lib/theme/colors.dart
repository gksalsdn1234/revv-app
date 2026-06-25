import 'package:flutter/material.dart';

class AppColors {
  // REVV Lean MVP racing tokens.
  static const bg = Color(0xFF100E0C);
  static const surfaceDim = Color(0xFF14110E);
  static const surfaceLowest = Color(0xFF0C0D10);
  static const panel = Color(0xFF14110E);
  static const panel2 = Color(0xFF1C1206);
  static const surface = Color(0xFF2A211D);
  static const surfaceHigh = Color(0xFF352B25);
  static const surfaceBright = Color(0xFF463931);

  static const red = Color(0xFFE2231A);
  static const redGlow = Color(0x66E2231A);
  static const redDim = Color(0x33E2231A);
  static const orange = Color(0xFFFFB020);
  static const cyan = Color(0xFFE2231A);
  static const white = Colors.white;
  static const gray = Color(0x408A8278);

  static const outline = Color(0xFF8A8278);
  static const outlineVariant = Color(0xFFA9A39B);
  static const success = Color(0xFF1FA85F);
  static const warning = Color(0xFFFFB020);
  static const danger = Color(0xFFFF6457);
  static const primaryContainer = Color(0xFFE2231A);
  static const onPrimary = Color(0xFFFFF8F0);

  static const textPrimary = Color(0xFFF1ECE1);
  static const textSecondary = Color(0xFFDAD3C2);
  static const textHint = Color(0xFFA9A39B);
  static const ink = Color(0xFF14110E);
  static const cream = Color(0xFFF1ECE1);
  static const creamRaised = Color(0xFFF8F4EB);
  static const creamMuted = Color(0xFFE7E1D4);
  static const stone = Color(0xFF8A8278);
  static const stoneMuted = Color(0xFFA9A39B);
  static const gold = Color(0xFFC9A24B);
  static const redSoft = Color(0xFFFBEBEA);

  static const divider = Color(0xFFA9A39B);

  static LinearGradient cockpitBackgroundGradient({
    AlignmentGeometry begin = Alignment.topLeft,
  }) {
    return LinearGradient(
      begin: begin,
      end: Alignment.bottomRight,
      colors: const [Color(0xFF100E0C), Color(0xFF14110E), Color(0xFF1C1206)],
      stops: [0.0, 0.58, 1.0],
    );
  }

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
