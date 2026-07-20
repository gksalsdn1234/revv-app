import 'package:flutter/material.dart';

import '../core/app_language.dart';
import '../models/revv_route.dart';
import '../theme/colors.dart';
import '../theme/text_styles.dart';
import '../ui/app_copy.dart';

class RouteNewBadge extends StatelessWidget {
  final RevvRoute route;
  final AppLanguage language;
  final DateTime? now;

  const RouteNewBadge({
    super.key,
    required this.route,
    required this.language,
    this.now,
  });

  @override
  Widget build(BuildContext context) {
    if (!route.isNewlyGeneratedAt(now ?? DateTime.now())) {
      return const SizedBox.shrink();
    }

    return Semantics(
      key: const ValueKey('route-new-badge'),
      container: true,
      label: AppCopy.newRouteSemantics(language),
      child: ExcludeSemantics(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.cyan.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.cyan.withValues(alpha: 0.62)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            child: Text(
              AppCopy.newRouteLabel(language),
              maxLines: 1,
              style: AppText.technicalLabel(
                size: 9,
                weight: FontWeight.w800,
                color: AppColors.cyan,
                letterSpacing: 0.4,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
