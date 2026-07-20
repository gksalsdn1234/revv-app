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

class NewRouteMapLegend extends StatelessWidget {
  final int count;
  final AppLanguage language;

  const NewRouteMapLegend({
    super.key,
    required this.count,
    required this.language,
  });

  String get _label => AppCopy.t(
    language,
    ko: '신규 $count개',
    en: '${AppCopy.newRouteLabel(language)} $count',
    fr: '${AppCopy.newRouteLabel(language)} $count',
  );

  String get _outlineLabel =>
      AppCopy.t(language, ko: '청록 테두리', en: 'Cyan outline', fr: 'Contour cyan');

  String get _semanticsLabel => AppCopy.t(
    language,
    ko: '신규 루트 $count개, 청록 테두리',
    en: '$count new routes, cyan outline',
    fr: '$count nouveaux itinéraires, contour cyan',
  );

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();

    return Semantics(
      key: const ValueKey('new-route-map-legend'),
      label: _semanticsLabel,
      child: ExcludeSemantics(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.surface.withValues(alpha: 0.88),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.cyan.withValues(alpha: 0.72)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 18,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: AppColors.cyan, width: 2),
                  ),
                ),
                const SizedBox(width: 7),
                Text(
                  _label,
                  style: AppText.technicalLabel(
                    size: 10,
                    weight: FontWeight.w800,
                    color: AppColors.cream,
                    letterSpacing: 0.35,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  _outlineLabel,
                  style: AppText.technicalLabel(
                    size: 9,
                    weight: FontWeight.w700,
                    color: AppColors.cyan,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
