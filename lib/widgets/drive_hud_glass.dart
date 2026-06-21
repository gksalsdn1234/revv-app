import 'package:flutter/material.dart';

import '../theme/colors.dart';

class DriveHudGlass extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const DriveHudGlass({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(12),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: const Color(0xE60F1214),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppColors.outlineVariant.withValues(alpha: 0.34),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.24),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: child,
    );
  }
}

Color driveSeverityColor(int severity) {
  if (severity >= 3) return AppColors.danger;
  if (severity >= 2) return AppColors.warning;
  return AppColors.primaryContainer;
}
