import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'colors.dart';

class AppText {
  static TextStyle inter({
    double size = 14,
    FontWeight weight = FontWeight.w500,
    Color color = AppColors.textPrimary,
    double letterSpacing = 0,
    FontStyle style = FontStyle.normal,
    double? height,
  }) => GoogleFonts.inter(
    fontSize: size,
    fontWeight: weight,
    color: color,
    letterSpacing: letterSpacing,
    fontStyle: style,
    height: height,
  );

  static TextStyle body({
    double size = 14,
    FontWeight weight = FontWeight.w500,
    Color color = AppColors.textPrimary,
    double letterSpacing = 0,
    double? height,
  }) => GoogleFonts.archivo(
    textStyle: TextStyle(
      fontSize: size,
      fontWeight: weight,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
      fontFamilyFallback: const [
        'Pretendard',
        'Apple SD Gothic Neo',
        'Noto Sans KR',
      ],
    ),
  );

  static TextStyle display({
    double size = 56,
    FontWeight weight = FontWeight.w800,
    Color color = AppColors.textPrimary,
    double letterSpacing = -2,
    double? height,
  }) => GoogleFonts.rajdhani(
    textStyle: TextStyle(
      fontSize: size,
      fontWeight: weight,
      color: color,
      letterSpacing: letterSpacing < 0 ? 0 : letterSpacing,
      height: height,
      fontFamilyFallback: const [
        'Pretendard',
        'Apple SD Gothic Neo',
        'Noto Sans KR',
      ],
    ),
  );

  static TextStyle orbitron({
    double size = 14,
    FontWeight weight = FontWeight.w700,
    Color color = AppColors.textPrimary,
    double letterSpacing = 0,
  }) => GoogleFonts.orbitron(
    fontSize: size,
    fontWeight: weight,
    color: color,
    letterSpacing: letterSpacing,
  );

  static TextStyle rajdhani({
    double size = 14,
    FontWeight weight = FontWeight.w500,
    Color color = AppColors.textPrimary,
    double letterSpacing = 0,
    FontStyle style = FontStyle.normal,
    double? height,
  }) => GoogleFonts.rajdhani(
    fontSize: size,
    fontWeight: weight,
    color: color,
    letterSpacing: letterSpacing,
    fontStyle: style,
    height: height,
  );

  static TextStyle label({
    double size = 12,
    FontWeight weight = FontWeight.w700,
    Color color = AppColors.textHint,
    double letterSpacing = 2,
  }) => GoogleFonts.rajdhani(
    fontSize: size,
    fontWeight: weight,
    color: color,
    letterSpacing: letterSpacing,
  );

  static TextStyle technicalLabel({
    double size = 10,
    FontWeight weight = FontWeight.w700,
    Color color = AppColors.textHint,
    double letterSpacing = 1.6,
  }) => GoogleFonts.jetBrainsMono(
    fontSize: size,
    fontWeight: weight,
    color: color,
    letterSpacing: letterSpacing,
  );

  static TextStyle mono({
    double size = 12,
    FontWeight weight = FontWeight.w700,
    Color color = AppColors.textPrimary,
    double letterSpacing = 0,
  }) => GoogleFonts.jetBrainsMono(
    fontSize: size,
    fontWeight: weight,
    color: color,
    letterSpacing: letterSpacing,
  );
}
