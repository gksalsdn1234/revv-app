import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'colors.dart';

class AppText {
  static bool forceSystemFonts = false;
  static const _cjkFallback = [
    'Pretendard',
    'Apple SD Gothic Neo',
    'Noto Sans KR',
  ];

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
      fontFamilyFallback: _cjkFallback,
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
      fontFamilyFallback: _cjkFallback,
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
  }) {
    final textStyle = TextStyle(
      fontSize: size,
      fontWeight: weight,
      color: color,
      letterSpacing: letterSpacing,
      fontFamilyFallback: _cjkFallback,
    );
    return forceSystemFonts
        ? textStyle
        : GoogleFonts.orbitron(textStyle: textStyle);
  }

  static TextStyle rajdhani({
    double size = 14,
    FontWeight weight = FontWeight.w500,
    Color color = AppColors.textPrimary,
    double letterSpacing = 0,
    FontStyle style = FontStyle.normal,
    double? height,
  }) {
    final textStyle = TextStyle(
      fontSize: size,
      fontWeight: weight,
      color: color,
      letterSpacing: letterSpacing,
      fontStyle: style,
      height: height,
      fontFamilyFallback: _cjkFallback,
    );
    return forceSystemFonts
        ? textStyle
        : GoogleFonts.rajdhani(textStyle: textStyle);
  }

  static TextStyle label({
    double size = 12,
    FontWeight weight = FontWeight.w700,
    Color color = AppColors.textHint,
    double letterSpacing = 2,
  }) {
    final textStyle = TextStyle(
      fontSize: size,
      fontWeight: weight,
      color: color,
      letterSpacing: letterSpacing,
      fontFamilyFallback: _cjkFallback,
    );
    return forceSystemFonts
        ? textStyle
        : GoogleFonts.rajdhani(textStyle: textStyle);
  }

  static TextStyle technicalLabel({
    double size = 10,
    FontWeight weight = FontWeight.w700,
    Color color = AppColors.textHint,
    double letterSpacing = 1.6,
  }) {
    final textStyle = TextStyle(
      fontSize: size,
      fontWeight: weight,
      color: color,
      letterSpacing: letterSpacing,
      fontFamilyFallback: _cjkFallback,
    );
    return forceSystemFonts
        ? textStyle
        : GoogleFonts.jetBrainsMono(textStyle: textStyle);
  }

  static TextStyle mono({
    double size = 12,
    FontWeight weight = FontWeight.w700,
    Color color = AppColors.textPrimary,
    double letterSpacing = 0,
  }) {
    final textStyle = TextStyle(
      fontSize: size,
      fontWeight: weight,
      color: color,
      letterSpacing: letterSpacing,
      fontFamilyFallback: _cjkFallback,
    );
    return forceSystemFonts
        ? textStyle
        : GoogleFonts.jetBrainsMono(textStyle: textStyle);
  }
}
