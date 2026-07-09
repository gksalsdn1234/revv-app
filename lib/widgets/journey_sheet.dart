import 'package:flutter/material.dart';

import '../core/app_language.dart';
import '../models/drive_plan.dart';
import '../models/revv_route.dart';
import '../services/drive_planner_service.dart';
import '../services/route_loading_policy.dart';
import '../theme/colors.dart';
import '../theme/text_styles.dart';
import '../ui/app_copy.dart';
import 'map_widget.dart';
import 'revv_ui.dart';

List<PlanMapMarker> buildJourneyPlanMapMarkers({
  required LatLng origin,
  required LatLng destination,
  required DrivePlan plan,
}) {
  return [
    PlanMapMarker(point: origin, kind: PlanMapMarkerKind.origin),
    PlanMapMarker(point: destination, kind: PlanMapMarkerKind.destination),
    for (final leg in plan.legs)
      if (leg.kind == DrivePlanLegKind.winding && leg.nodes.isNotEmpty) ...[
        PlanMapMarker(
          point: leg.nodes.first,
          kind: PlanMapMarkerKind.windingStart,
        ),
        PlanMapMarker(
          point: leg.nodes.last,
          kind: PlanMapMarkerKind.windingEnd,
        ),
      ],
  ];
}

class JourneySheet extends StatelessWidget {
  final DraggableScrollableController controller;
  final AppLanguage language;
  final String? destinationName;
  final List<DrivePlanOption>? options;
  final List<FreeRoamOption>? freeRoamOptions;
  final DrivePlan plan;
  final DrivePlanOption? recommended;
  final DateTime? arriveBy;
  final DrivePlanOptionKind selectedKind;
  final int selectedFreeRoamIndex;
  final int selectedOptionBudget;
  final bool canStart;
  final VoidCallback? onBack;
  final VoidCallback? onSearchDestination;
  final ValueChanged<DrivePlanOptionKind> onSelectedOption;
  final ValueChanged<int> onSelectedFreeRoam;
  final VoidCallback onStart;
  final VoidCallback onNavigate;

  const JourneySheet({
    super.key,
    required this.controller,
    required this.language,
    required this.destinationName,
    required this.options,
    required this.freeRoamOptions,
    required this.plan,
    required this.recommended,
    required this.arriveBy,
    required this.selectedKind,
    required this.selectedFreeRoamIndex,
    required this.selectedOptionBudget,
    required this.canStart,
    required this.onSelectedOption,
    required this.onSelectedFreeRoam,
    required this.onStart,
    required this.onNavigate,
    this.onBack,
    this.onSearchDestination,
  });

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      controller: controller,
      initialChildSize: 0.42,
      minChildSize: 0.18,
      maxChildSize: 0.85,
      snap: true,
      snapSizes: const [0.18, 0.42, 0.85],
      builder: (context, scrollController) {
        final bottomPadding = MediaQuery.paddingOf(context).bottom;
        return RevvGlassCard(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 0),
          padding: EdgeInsets.zero,
          radius: 18,
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                  children: [
                    const _SheetHandle(),
                    KeyedSubtree(
                      key: const Key('planner-results-sheet'),
                      child: _ResultSheetBody(
                        language: language,
                        destinationName: destinationName,
                        options: options,
                        freeRoamOptions: freeRoamOptions,
                        plan: plan,
                        recommended: recommended,
                        arriveBy: arriveBy,
                        selectedKind: selectedKind,
                        selectedFreeRoamIndex: selectedFreeRoamIndex,
                        selectedOptionBudget: selectedOptionBudget,
                        onBack: onBack,
                        onSearchDestination: onSearchDestination,
                        onSelectedOption: onSelectedOption,
                        onSelectedFreeRoam: onSelectedFreeRoam,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, bottomPadding + 12),
                child: Row(
                  children: [
                    Expanded(
                      child: RevvPrimaryButton(
                        label: _copy(
                          language,
                          ko: '드라이브 시작',
                          en: 'Start drive',
                          fr: 'Lancer',
                        ),
                        icon: Icons.play_arrow_rounded,
                        onPressed: canStart ? onStart : null,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Tooltip(
                      message: _copy(
                        language,
                        ko: '외부 내비',
                        en: 'Open nav',
                        fr: 'Navigation',
                      ),
                      child: OutlinedButton(
                        onPressed: onNavigate,
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(
                            color: AppColors.outline.withValues(alpha: 0.28),
                          ),
                          foregroundColor: AppColors.textPrimary,
                          minimumSize: const Size(52, 52),
                          shape: const CircleBorder(),
                          padding: EdgeInsets.zero,
                        ),
                        child: const Icon(Icons.navigation_rounded, size: 20),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class JourneyPlanningCard extends StatelessWidget {
  final AppLanguage language;
  final bool framed;

  const JourneyPlanningCard({
    super.key,
    required this.language,
    this.framed = true,
  });

  @override
  Widget build(BuildContext context) {
    final content = Row(
      children: [
        const SizedBox.square(
          dimension: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: 10),
        Text(
          _copy(language, ko: '계산 중', en: 'Planning', fr: 'Calcul'),
          style: AppText.body(weight: FontWeight.w900),
        ),
      ],
    );
    if (!framed) return content;
    return RevvGlassCard(child: content);
  }
}

class JourneyStateCard extends StatelessWidget {
  final String title;
  final String body;

  const JourneyStateCard({super.key, required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return RevvGlassCard(
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded, color: AppColors.warning),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppText.body(weight: FontWeight.w900)),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: AppText.body(size: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 36,
        height: 4,
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: AppColors.outlineVariant.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(999),
        ),
      ),
    );
  }
}

class _ResultSheetBody extends StatelessWidget {
  final AppLanguage language;
  final String? destinationName;
  final List<DrivePlanOption>? options;
  final List<FreeRoamOption>? freeRoamOptions;
  final DrivePlan plan;
  final DrivePlanOption? recommended;
  final DateTime? arriveBy;
  final DrivePlanOptionKind selectedKind;
  final int selectedFreeRoamIndex;
  final int selectedOptionBudget;
  final VoidCallback? onBack;
  final VoidCallback? onSearchDestination;
  final ValueChanged<DrivePlanOptionKind> onSelectedOption;
  final ValueChanged<int> onSelectedFreeRoam;

  const _ResultSheetBody({
    required this.language,
    required this.destinationName,
    required this.options,
    required this.freeRoamOptions,
    required this.plan,
    required this.recommended,
    required this.arriveBy,
    required this.selectedKind,
    required this.selectedFreeRoamIndex,
    required this.selectedOptionBudget,
    required this.onBack,
    required this.onSearchDestination,
    required this.onSelectedOption,
    required this.onSelectedFreeRoam,
  });

  @override
  Widget build(BuildContext context) {
    final destinationOptions = options ?? const <DrivePlanOption>[];
    final freeOptions = freeRoamOptions ?? const <FreeRoamOption>[];
    final isFreeRoam = freeOptions.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (onBack != null) ...[
          TextButton.icon(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_rounded, size: 18),
            label: Text(_copy(language, ko: '목록', en: 'List', fr: 'Liste')),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.textSecondary,
              visualDensity: VisualDensity.compact,
            ),
          ),
          const SizedBox(height: 4),
        ],
        Text(
          _planHeader(plan, language),
          style: AppText.body(size: 19, weight: FontWeight.w900, height: 1.1),
        ),
        if (plan.baselineDirectMinutes != null) ...[
          const SizedBox(height: 10),
          _PlanCompareLine(plan: plan, language: language),
        ],
        const SizedBox(height: 12),
        if (isFreeRoam)
          _FreeRoamOptionStrip(
            options: freeOptions,
            selectedIndex: selectedFreeRoamIndex,
            language: language,
            onSelected: onSelectedFreeRoam,
          )
        else
          _PlanOptionStrip(
            options: destinationOptions,
            selected: selectedKind,
            recommended: recommended?.kind,
            language: language,
            onSelected: onSelectedOption,
          ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Text(
                isFreeRoam
                    ? _loopBackLabel(language)
                    : destinationName ?? _mapPinLabel(language),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.body(size: 13, weight: FontWeight.w800),
              ),
            ),
            if (onSearchDestination != null)
              TextButton(
                onPressed: onSearchDestination,
                child: Text(
                  _copy(language, ko: '변경', en: 'Change', fr: 'Modifier'),
                ),
              ),
          ],
        ),
        Divider(
          height: 18,
          color: AppColors.outlineVariant.withValues(alpha: 0.18),
        ),
        if (!isFreeRoam && arriveBy != null && recommended == null)
          _ArrivalInfeasibleCard(
            options: destinationOptions,
            arriveBy: arriveBy!,
            language: language,
          ),
        _PlanResultCard(
          plan: plan,
          language: language,
          targetMinutes: selectedOptionBudget,
        ),
      ],
    );
  }
}

class _PlanCompareLine extends StatelessWidget {
  final DrivePlan plan;
  final AppLanguage language;

  const _PlanCompareLine({required this.plan, required this.language});

  @override
  Widget build(BuildContext context) {
    final baseline = plan.baselineDirectMinutes;
    if (baseline == null) return const SizedBox.shrink();
    final extraMinutes = plan.totalMinutes - baseline;
    final curves = plan.legs
        .where((leg) => leg.kind == DrivePlanLegKind.winding)
        .fold<int>(0, (sum, leg) => sum + (leg.route?.sharpCurveCount ?? 0));

    return Wrap(
      key: const Key('plan-compare-line'),
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _ComparePill(
          text: _planCompareCopy(
            language,
            baseline,
            plan.totalMinutes,
            extraMinutes,
          ),
        ),
        if (curves > 0) _ComparePill(text: _curveCountCopy(language, curves)),
      ],
    );
  }
}

class _ComparePill extends StatelessWidget {
  final String text;

  const _ComparePill({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.84),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: AppColors.outlineVariant.withValues(alpha: 0.22),
        ),
      ),
      child: Text(
        text,
        style: AppText.body(
          size: 12,
          weight: FontWeight.w900,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}

class _PlanResultCard extends StatelessWidget {
  final DrivePlan plan;
  final AppLanguage language;
  final int targetMinutes;

  const _PlanResultCard({
    required this.plan,
    required this.language,
    required this.targetMinutes,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (plan.usesApproximateTransit) ...[
          Text(
            _copy(
              language,
              ko: '대략 경로 · 실제 내비에서 도로 경로를 확인하세요',
              en: 'Approximate route · confirm roads in navigation',
              fr: 'Trajet approximatif · vérifiez dans la navigation',
            ),
            style: AppText.body(size: 12, color: AppColors.warning),
          ),
          const SizedBox(height: 12),
        ],
        ...plan.legs.map((leg) => _TimelineLeg(leg: leg, language: language)),
        const SizedBox(height: 10),
        _PlanHonestyLine(
          plan: plan,
          language: language,
          targetMinutes: targetMinutes,
        ),
      ],
    );
  }
}

class _TimelineLeg extends StatelessWidget {
  final DrivePlanLeg leg;
  final AppLanguage language;

  const _TimelineLeg({required this.leg, required this.language});

  @override
  Widget build(BuildContext context) {
    final title = switch (leg.kind) {
      DrivePlanLegKind.winding =>
        '${leg.route == null ? _copy(language, ko: '와인딩 루트', en: 'Winding route', fr: 'Route sinueuse') : routeDisplayName(leg.route!, language: language)} ${_minutes(language, leg.estimatedMinutes)}',
      DrivePlanLegKind.rest => _copy(
        language,
        ko: '휴식 ${leg.estimatedMinutes}분',
        en: 'Rest ${leg.estimatedMinutes} min',
        fr: 'Pause ${leg.estimatedMinutes} min',
      ),
      DrivePlanLegKind.transit => _copy(
        language,
        ko: '이동 ${leg.estimatedMinutes}분',
        en: 'Transit ${leg.estimatedMinutes} min',
        fr: 'Liaison ${leg.estimatedMinutes} min',
      ),
    };
    final icon = switch (leg.kind) {
      DrivePlanLegKind.winding => Icons.route_rounded,
      DrivePlanLegKind.rest => Icons.local_cafe_rounded,
      DrivePlanLegKind.transit => Icons.near_me_rounded,
    };
    final color = switch (leg.kind) {
      DrivePlanLegKind.winding => AppColors.primaryContainer,
      DrivePlanLegKind.rest => AppColors.warning,
      DrivePlanLegKind.transit => AppColors.cyan,
    };
    final dotColor = switch (leg.kind) {
      DrivePlanLegKind.winding => AppColors.red,
      DrivePlanLegKind.transit => const Color(0xFF6DA3FF),
      DrivePlanLegKind.rest => null,
    };
    final dotKey = switch (leg.kind) {
      DrivePlanLegKind.winding => const Key('timeline-dot-winding'),
      DrivePlanLegKind.transit => const Key('timeline-dot-transit'),
      DrivePlanLegKind.rest => null,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          if (dotColor != null) ...[
            Container(
              key: dotKey,
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: dotColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Icon(icon, size: 17, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: AppText.body(size: 13, weight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanOptionStrip extends StatelessWidget {
  final List<DrivePlanOption> options;
  final DrivePlanOptionKind selected;
  final DrivePlanOptionKind? recommended;
  final AppLanguage language;
  final ValueChanged<DrivePlanOptionKind> onSelected;

  const _PlanOptionStrip({
    required this.options,
    required this.selected,
    required this.recommended,
    required this.language,
    required this.onSelected,
  });

  String _optionLabel(DrivePlanOption option) {
    final name = switch (option.kind) {
      DrivePlanOptionKind.light => _copy(
        language,
        ko: '가볍게',
        en: 'Shorter',
        fr: 'Court',
      ),
      DrivePlanOptionKind.standard => _copy(
        language,
        ko: '기본',
        en: 'Standard',
        fr: 'Standard',
      ),
      DrivePlanOptionKind.extended => _copy(
        language,
        ko: '길게',
        en: 'Longer',
        fr: 'Long',
      ),
    };
    return '$name ${option.plan.totalMinutes}${_copy(language, ko: '분', en: 'm', fr: 'min')}';
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: [
          for (final option in options) ...[
            _optionChip(option),
            if (option != options.last) const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }

  Widget _optionChip(DrivePlanOption option) {
    final active = option.kind == selected;
    final isRecommended = option.kind == recommended;
    return ChoiceChip(
      avatar: isRecommended
          ? const Icon(
              Icons.check_circle_rounded,
              size: 16,
              color: AppColors.gold,
            )
          : null,
      label: Text(
        isRecommended
            ? '${_optionLabel(option)} · ${_copy(language, ko: '추천', en: 'Fits', fr: 'Adapté')}'
            : _optionLabel(option),
      ),
      selected: active,
      onSelected: (_) => onSelected(option.kind),
      selectedColor: AppColors.primaryContainer,
      backgroundColor: AppColors.panel2.withValues(alpha: 0.92),
      labelStyle: AppText.body(
        size: 12,
        weight: FontWeight.w800,
        color: active ? AppColors.onPrimary : AppColors.textPrimary,
      ),
    );
  }
}

class _FreeRoamOptionStrip extends StatelessWidget {
  final List<FreeRoamOption> options;
  final int selectedIndex;
  final AppLanguage language;
  final ValueChanged<int> onSelected;

  const _FreeRoamOptionStrip({
    required this.options,
    required this.selectedIndex,
    required this.language,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: [
          for (var index = 0; index < options.length; index++) ...[
            ChoiceChip(
              label: Text(options[index].headingLabel(language)),
              selected: index == selectedIndex,
              onSelected: (_) => onSelected(index),
              selectedColor: AppColors.primaryContainer,
              backgroundColor: AppColors.panel2.withValues(alpha: 0.92),
              labelStyle: AppText.body(
                size: 12,
                weight: FontWeight.w800,
                color: index == selectedIndex
                    ? AppColors.onPrimary
                    : AppColors.textPrimary,
              ),
            ),
            if (index != options.length - 1) const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class _ArrivalInfeasibleCard extends StatelessWidget {
  final List<DrivePlanOption> options;
  final DateTime arriveBy;
  final AppLanguage language;

  const _ArrivalInfeasibleCard({
    required this.options,
    required this.arriveBy,
    required this.language,
  });

  @override
  Widget build(BuildContext context) {
    final availableMinutes = arriveBy.difference(DateTime.now()).inMinutes;
    final lightest = options.reduce(
      (a, b) => a.plan.totalMinutes <= b.plan.totalMinutes ? a : b,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: JourneyStateCard(
        title: _copy(
          language,
          ko: '희망 시각까지 맞는 여정이 없어요',
          en: 'No plan fits the arrival time',
          fr: 'Aucun trajet ne convient à cette heure',
        ),
        body: _copy(
          language,
          ko: '남은 시간 $availableMinutes분, 가장 가벼운 여정도 ${lightest.plan.totalMinutes}분이 필요해요. 도착 시각을 늦추거나 목적지를 조정해 보세요.',
          en: '$availableMinutes min left, but the lightest plan needs ${lightest.plan.totalMinutes} min. Push the arrival time or adjust the destination.',
          fr: '$availableMinutes min restantes, mais le trajet le plus court demande ${lightest.plan.totalMinutes} min. Décalez l’arrivée ou ajustez la destination.',
        ),
      ),
    );
  }
}

class _PlanHonestyLine extends StatelessWidget {
  final DrivePlan plan;
  final AppLanguage language;
  final int targetMinutes;

  const _PlanHonestyLine({
    required this.plan,
    required this.language,
    required this.targetMinutes,
  });

  @override
  Widget build(BuildContext context) {
    final text = plan.windingMinutes == 0
        ? _copy(
            language,
            ko: '이 경로엔 아직 발견된 와인딩이 없어요. 직행 안내로 열 수 있어요.',
            en: 'No discovered winding roads on this route yet. Direct navigation is available.',
            fr: 'Aucune route sinueuse trouvée sur ce trajet. La navigation directe reste disponible.',
          )
        : plan.budgetShortfallMinutes > 0
        ? _copy(
            language,
            ko: '와인딩 ${plan.windingMinutes}/$targetMinutes분',
            en: 'Winding ${plan.windingMinutes}/$targetMinutes min',
            fr: 'Sinueux ${plan.windingMinutes}/$targetMinutes min',
          )
        : _copy(
            language,
            ko: '와인딩 ${plan.windingMinutes}/$targetMinutes분',
            en: 'Winding ${plan.windingMinutes}/$targetMinutes min',
            fr: 'Sinueux ${plan.windingMinutes}/$targetMinutes min',
          );
    return RevvPill(label: text, color: AppColors.warning);
  }
}

String _mapPinLabel(AppLanguage language) {
  return _copy(
    language,
    ko: '지도에서 선택한 지점',
    en: 'Picked on map',
    fr: 'Point sur la carte',
  );
}

String _loopBackLabel(AppLanguage language) {
  return _copy(
    language,
    ko: '출발지로 돌아오는 루프',
    en: 'Loop back to start',
    fr: 'Boucle retour',
  );
}

String _formatClock(DateTime time) {
  final hour = time.hour.toString().padLeft(2, '0');
  final minute = time.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

String _planHeader(DrivePlan plan, AppLanguage language) {
  final eta = DateTime.now().add(Duration(minutes: plan.totalMinutes));
  return _copy(
    language,
    ko: '도착 ~${_formatClock(eta)} · ${plan.totalMinutes}분 · 와인딩 ${plan.windingMinutes}분',
    en: 'Arrive ~${_formatClock(eta)} · ${plan.totalMinutes} min · Winding ${plan.windingMinutes} min',
    fr: 'Arrivée ~${_formatClock(eta)} · ${plan.totalMinutes} min · Sinueux ${plan.windingMinutes} min',
  );
}

String _planCompareCopy(
  AppLanguage language,
  int baselineMinutes,
  int revvMinutes,
  int extraMinutes,
) {
  final directLabel = _copy(language, ko: '기본', en: 'Direct', fr: 'Direct');
  final extra = extraMinutes > 0
      ? ' ${_copy(language, ko: '(+$extraMinutes분)', en: '(+$extraMinutes min)', fr: '(+$extraMinutes min)')}'
      : '';
  return '$directLabel ${_formatCompactDuration(baselineMinutes)} · REVV ${_formatCompactDuration(revvMinutes)}$extra';
}

String _curveCountCopy(AppLanguage language, int curves) {
  return _copy(
    language,
    ko: '커브 $curves개',
    en: '$curves curves',
    fr: '$curves virages',
  );
}

String _formatCompactDuration(int minutes) {
  final hours = minutes ~/ 60;
  final remainder = minutes % 60;
  if (hours == 0) return '${remainder}m';
  if (remainder == 0) return '${hours}h';
  return '${hours}h ${remainder.toString().padLeft(2, '0')}m';
}

String _minutes(AppLanguage language, int value) {
  return _copy(language, ko: '$value분', en: '$value min', fr: '$value min');
}

String journeyRetryCopy(AppLanguage language) {
  return _copy(
    language,
    ko: '출발지나 목적지를 조정한 뒤 다시 시도해 주세요.',
    en: 'Adjust the origin or destination and try again.',
    fr: 'Ajustez le départ ou la destination puis réessayez.',
  );
}

String _copy(
  AppLanguage language, {
  String? ko,
  required String en,
  required String fr,
}) {
  return AppCopy.t(language, ko: ko, en: en, fr: fr);
}
