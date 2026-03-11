import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/colors.dart';

class RedGlowButton extends StatelessWidget {
  final String label;
  final bool filled;
  final VoidCallback? onTap;
  final double height;

  const RedGlowButton({
    super.key,
    required this.label,
    this.filled = true,
    this.onTap,
    this.height = 52,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: height,
      child: Material(
        color: filled ? AppColors.red : Colors.transparent,
        borderRadius: BorderRadius.circular(2),
        child: InkWell(
          onTap: onTap,
          splashColor: AppColors.red.withOpacity(0.3),
          borderRadius: BorderRadius.circular(2),
          child: Container(
            decoration: filled
                ? null
                : BoxDecoration(
                    borderRadius: BorderRadius.circular(2),
                    border: Border.all(color: AppColors.red),
                  ),
            alignment: Alignment.center,
            child: Text(
              label,
              style: GoogleFonts.rajdhani(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                letterSpacing: 4,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
