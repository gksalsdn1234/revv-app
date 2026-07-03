import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'colors.dart';

class AppText {
  static bool forceSystemFonts = false;

  static TextStyle inter({
    double size = 14,
    FontWeight weight = FontWeight.w500,
    Color color = AppColors.textPrimary,
    double letterSpacing = 0,
    FontStyle style = FontStyle.normal,
    double? height,
  }) => forceSystemFonts
      ? TextStyle(
          fontSize: size,
          fontWeight: weight,
          color: color,
          letterSpacing: letterSpacing,
          fontStyle: style,
          height: height,
        )
      : GoogleFonts.inter(
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
  }) {
    final textStyle = TextStyle(
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
    );
    return forceSystemFonts
        ? textStyle
        : GoogleFonts.archivo(textStyle: textStyle);
  }

  static TextStyle display({
    double size = 56,
    FontWeight weight = FontWeight.w800,
    Color color = AppColors.textPrimary,
    double letterSpacing = -2,
    double? height,
  }) {
    final textStyle = TextStyle(
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
    );
    return forceSystemFonts
        ? textStyle
        : GoogleFonts.rajdhani(textStyle: textStyle);
  }

  static TextStyle orbitron({
    double size = 14,
    FontWeight weight = FontWeight.w700,
    Color color = AppColors.textPrimary,
    double letterSpacing = 0,
  }) => forceSystemFonts
      ? TextStyle(
          fontSize: size,
          fontWeight: weight,
          color: color,
          letterSpacing: letterSpacing,
        )
      : GoogleFonts.orbitron(
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
  }) => forceSystemFonts
      ? TextStyle(
          fontSize: size,
          fontWeight: weight,
          color: color,
          letterSpacing: letterSpacing,
          fontStyle: style,
          height: height,
        )
      : GoogleFonts.rajdhani(
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
  }) => forceSystemFonts
      ? TextStyle(
          fontSize: size,
          fontWeight: weight,
          color: color,
          letterSpacing: letterSpacing,
        )
      : GoogleFonts.rajdhani(
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
  }) => forceSystemFonts
      ? TextStyle(
          fontSize: size,
          fontWeight: weight,
          color: color,
          letterSpacing: letterSpacing,
        )
      : GoogleFonts.jetBrainsMono(
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
  }) => forceSystemFonts
      ? TextStyle(
          fontSize: size,
          fontWeight: weight,
          color: color,
          letterSpacing: letterSpacing,
        )
      : GoogleFonts.jetBrainsMono(
          fontSize: size,
          fontWeight: weight,
          color: color,
          letterSpacing: letterSpacing,
        );
}
