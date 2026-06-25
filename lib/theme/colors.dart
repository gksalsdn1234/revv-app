import 'package:flutter/material.dart';

class AppColors {
  // ── REVV Lean MVP v5 design tokens ──────────────────────────────────────
  static const bg             = Color(0xFF100E0C);
  static const surfaceDim     = Color(0xFF100E0C);
  static const surfaceLowest  = Color(0xFF0B0908);
  static const panel          = Color(0xFF14110E);
  static const panel2         = Color(0xFF1A1714);
  static const surface        = Color(0xFF221E1B);
  static const surfaceHigh    = Color(0xFF2C2723);
  static const surfaceBright  = Color(0xFF332F2B);

  // Accent — REVV Red
  static const red            = Color(0xFFE2231A);
  static const redGlow        = Color(0x66E2231A);
  static const redDim         = Color(0x33E2231A);

  // Secondary palette
  static const orange         = Color(0xFFFFB020);
  static const cyan           = Color(0xFF00E5FF);
  static const white          = Colors.white;
  static const gray           = Color(0x40FFFFFF);

  // Semantic
  static const outline        = Color(0xFF7A6E66);
  static const outlineVariant = Color(0xFF3D3530);
  static const success        = Color(0xFF1FA85F);
  static const warning        = Color(0xFFFFB020);
  static const danger         = Color(0xFFE2231A);

  // Component tokens
  static const primaryContainer = Color(0xFFE2231A);
  static const onPrimary        = Color(0xFFF1ECE1);

  // Text hierarchy — warm cream tones
  static const textPrimary   = Color(0xFFF1ECE1);
  static const textSecondary = Color(0xFFB8A898);
  static const textHint      = Color(0xFF7A6E66);

  // Divider
  static const divider = Color(0xFF3D3530);

  // ── Background gradient ──────────────────────────────────────────────────
  static LinearGradient cockpitBackgroundGradient({
    AlignmentGeometry begin = Alignment.topLeft,
  }) {
    return LinearGradient(
      begin: begin,
      end: Alignment.bottomRight,
      colors: const [Color(0xFF0B0908), Color(0xFF100E0C), Color(0xFF161210)],
      stops: [0.0, 0.58, 1.0],
    );
  }

  // ── G-force colour ramp: green → amber → red ────────────────────────────
  static Color gForceColor(double mag) {
    final t = (mag / 1.2).clamp(0.0, 1.0);
    if (t < 0.42) {
      return Color.lerp(
        const Color(0xFF1FA85F),
        const Color(0xFFFFB020),
        t / 0.42,
      )!;
    }
    return Color.lerp(
      const Color(0xFFFFB020),
      const Color(0xFFE2231A),
      ((t - 0.42) / 0.58).clamp(0.0, 1.0),
    )!;
  }
}
