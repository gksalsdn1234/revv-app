import 'package:flutter/material.dart';

import '../models/revv_route.dart';
import '../theme/colors.dart';
import '../theme/text_styles.dart';
import '../ui/copilot_briefing.dart';
import '../ui/route_quality_profile.dart';

Future<bool?> showCopilotStartSheet(
  BuildContext context, {
  required RevvRoute route,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (_) => _CopilotStartSheet(route: route),
  );
}

class _CopilotStartSheet extends StatelessWidget {
  final RevvRoute route;

  const _CopilotStartSheet({required this.route});

  @override
  Widget build(BuildContext context) {
    final profile = RouteQualityProfile.fromRoute(route);
    final briefing = CopilotRouteBriefing.fromRoute(
      route,
      profile: profile,
      startDistanceKm: route.distanceFromUser,
    );
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xF20F1214),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: AppColors.outlineVariant.withValues(alpha: 0.34),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.38),
                blurRadius: 32,
                offset: const Offset(0, 18),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '코파일럿 시작 판단',
                style: AppText.technicalLabel(
                  size: 10,
                  color: AppColors.primaryContainer,
                  letterSpacing: 1.8,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                route.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppText.body(
                  size: 23,
                  height: 1.05,
                  weight: FontWeight.w900,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              _AdviceLine(icon: Icons.flag_rounded, text: briefing.startAdvice),
              const SizedBox(height: 8),
              _AdviceLine(
                icon: Icons.psychology_rounded,
                text: briefing.primaryAdvice,
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: briefing.decisionChips
                    .map((chip) => _Chip(label: chip))
                    .toList(),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, false),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textSecondary,
                        side: BorderSide(
                          color: AppColors.outlineVariant.withValues(
                            alpha: 0.42,
                          ),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 15),
                      ),
                      child: Text(
                        '취소',
                        style: AppText.body(size: 14, weight: FontWeight.w900),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primaryContainer,
                        foregroundColor: AppColors.onPrimary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 15),
                      ),
                      child: Text(
                        briefing.nextActionLabel,
                        textAlign: TextAlign.center,
                        style: AppText.body(
                          size: 14,
                          weight: FontWeight.w900,
                          color: AppColors.onPrimary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdviceLine extends StatelessWidget {
  final IconData icon;
  final String text;

  const _AdviceLine({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: AppColors.primaryContainer, size: 18),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            text,
            style: AppText.body(
              size: 13,
              height: 1.35,
              weight: FontWeight.w800,
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;

  const _Chip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: AppText.body(
          size: 11,
          weight: FontWeight.w900,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}
