import 'package:flutter/material.dart';

import '../theme/colors.dart';
import '../theme/text_styles.dart';

class RideContextCard extends StatelessWidget {
  final String label;
  final String detail;
  final Color color;
  final EdgeInsetsGeometry padding;
  final Color backgroundColor;
  final double borderOpacity;
  final double detailHeight;

  const RideContextCard({
    super.key,
    required this.label,
    required this.detail,
    required this.color,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    this.backgroundColor = AppColors.surface,
    this.borderOpacity = 0.35,
    this.detailHeight = 1.25,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: backgroundColor.withValues(alpha: 0.84),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: borderOpacity)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppText.label(size: 10, color: color, letterSpacing: 1.1),
          ),
          const SizedBox(height: 4),
          Text(
            detail,
            style: AppText.inter(
              size: 13,
              weight: FontWeight.w700,
              color: AppColors.textSecondary,
              height: detailHeight,
            ),
          ),
        ],
      ),
    );
  }
}
