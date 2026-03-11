import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'colors.dart';

class AppText {
  static TextStyle orbitron({
    double size = 14,
    FontWeight weight = FontWeight.w700,
    Color color = AppColors.white,
    double letterSpacing = 0,
  }) =>
      GoogleFonts.orbitron(
        fontSize: size,
        fontWeight: weight,
        color: color,
        letterSpacing: letterSpacing,
      );

  static TextStyle rajdhani({
    double size = 14,
    FontWeight weight = FontWeight.w500,
    Color color = AppColors.white,
    double letterSpacing = 0,
    FontStyle style = FontStyle.normal,
  }) =>
      GoogleFonts.rajdhani(
        fontSize: size,
        fontWeight: weight,
        color: color,
        letterSpacing: letterSpacing,
        fontStyle: style,
      );
}
