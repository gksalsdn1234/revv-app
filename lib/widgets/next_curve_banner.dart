import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/app_language.dart';
import '../theme/colors.dart';
import '../theme/text_styles.dart';
import '../ui/app_copy.dart';
import '../ui/route_drive_cue.dart';
import 'drive_hud_glass.dart';

class NextCurveBanner extends StatelessWidget {
  final DriveCurveCue? cue;
  final DriveRhythmBrief? rhythmBrief;
  final DriveRouteStatus status;
  final String? eventMessage;
  final AppLanguage language;

  const NextCurveBanner({
    super.key,
    required this.cue,
    required this.rhythmBrief,
    required this.status,
    required this.eventMessage,
    required this.language,
  });

  @override
  Widget build(BuildContext context) {
    final data = cue;
    final rhythm = rhythmBrief;
    final severity = math.max(data?.severity ?? 0, rhythm?.severity ?? 0);
    final severityColor = driveSeverityColor(severity);
    final fallback = _fallbackCue(status, language);
    final headline = data?.headline ?? fallback.label;
    final rhythmLine = data?.rhythmLine ?? rhythm?.advice ?? fallback.detail;
    final metaLabels = <String>[
      if (data?.phaseLabel?.isNotEmpty == true) data!.phaseLabel!,
      if (data?.etaText?.isNotEmpty == true) data!.etaText!,
      if (data?.cornerTypeLabel?.isNotEmpty == true) data!.cornerTypeLabel!,
    ];
    final sequenceLine = data?.sequenceLine;

    return DriveHudGlass(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (eventMessage != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: severityColor.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: severityColor.withValues(alpha: 0.28),
                ),
              ),
              child: Text(
                eventMessage!,
                style: AppText.technicalLabel(size: 10, color: severityColor),
              ),
            ),
            const SizedBox(height: 8),
          ],
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: severityColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: severityColor.withValues(alpha: 0.35),
                  ),
                ),
                child: Icon(
                  data?.icon ?? fallback.icon,
                  color: severityColor,
                  size: 24,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      headline,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.body(
                        size: 24,
                        height: 1.02,
                        weight: FontWeight.w900,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      rhythmLine,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.body(
                        size: 13,
                        weight: FontWeight.w900,
                        color: severityColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (metaLabels.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: metaLabels
                  .map(
                    (label) => _CueMetaPill(label: label, color: severityColor),
                  )
                  .toList(growable: false),
            ),
          ],
          if (sequenceLine != null && sequenceLine != rhythmLine) ...[
            const SizedBox(height: 8),
            Text(
              sequenceLine,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.technicalLabel(
                size: 10,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CueMetaPill extends StatelessWidget {
  final String label;
  final Color color;

  const _CueMetaPill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppText.technicalLabel(size: 9, color: color),
      ),
    );
  }
}

class _FallbackCue {
  final String label;
  final String detail;
  final IconData icon;

  const _FallbackCue({
    required this.label,
    required this.detail,
    required this.icon,
  });
}

_FallbackCue _fallbackCue(DriveRouteStatus status, AppLanguage language) {
  switch (status) {
    case DriveRouteStatus.approachingStart:
      return _FallbackCue(
        label: AppCopy.t(
          language,
          ko: '시작점 이동',
          en: 'To start',
          fr: 'Vers départ',
        ),
        detail: AppCopy.t(
          language,
          ko: '루트 진입 대기',
          en: 'Waiting to enter',
          fr: 'Attente entrée',
        ),
        icon: Icons.flag_rounded,
      );
    case DriveRouteStatus.offRoute:
      return _FallbackCue(
        label: AppCopy.t(
          language,
          ko: '루트 이탈',
          en: 'Off route',
          fr: 'Hors route',
        ),
        detail: AppCopy.t(
          language,
          ko: '라인 복귀',
          en: 'Rejoin line',
          fr: 'Rejoindre ligne',
        ),
        icon: Icons.near_me_disabled_rounded,
      );
    case DriveRouteStatus.completed:
      return _FallbackCue(
        label: AppCopy.t(
          language,
          ko: '루트 완료',
          en: 'Route complete',
          fr: 'Route terminée',
        ),
        detail: AppCopy.t(
          language,
          ko: '주행 종료 가능',
          en: 'Ready to finish',
          fr: 'Fin possible',
        ),
        icon: Icons.done_rounded,
      );
    case DriveRouteStatus.onRoute:
      return _FallbackCue(
        label: AppCopy.t(
          language,
          ko: '흐름 구간',
          en: 'Flow section',
          fr: 'Section fluide',
        ),
        detail: AppCopy.t(
          language,
          ko: '1.0km 흐름 구간',
          en: '1.0km flow section',
          fr: '1,0km fluide',
        ),
        icon: Icons.timeline_rounded,
      );
  }
}
