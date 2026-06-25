import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/revv_route.dart';
import '../core/app_language.dart';
import '../services/settings_service.dart';
import '../theme/colors.dart';
import '../theme/text_styles.dart';
import '../ui/app_copy.dart';
import '../ui/copilot_briefing.dart';
import '../ui/route_detail_copy.dart';
import '../ui/route_drive_cue.dart';
import '../ui/route_quality_profile.dart';
import '../widgets/copilot_start_sheet.dart';
import 'lean_drive_screen.dart';

class LeanRouteDetailScreen extends StatelessWidget {
  final RevvRoute route;

  const LeanRouteDetailScreen({super.key, required this.route});

  Future<void> _startDrive(BuildContext context) async {
    final startChoice = await showCopilotStartSheet(context, route: route);
    if (!context.mounted || startChoice == null) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => LeanDriveScreen(
          route: route,
          simulated: startChoice == CopilotStartChoice.simulate,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final language = context.watch<SettingsService>().appLanguage;
    final copy = RouteDetailCopy.fromRoute(
      route,
      startDistanceKm: route.distanceFromUser,
      language: language,
    );
    final profile = RouteQualityProfile.fromRoute(route, language: language);
    final briefing = CopilotRouteBriefing.fromRoute(
      route,
      profile: profile,
      startDistanceKm: route.distanceFromUser,
      language: language,
    );
    final turnPlan = buildTurnByTurnPlan(route.nodes, language: language);
    final bestFor = _bestFor(route, language);
    final cautionBody = _cautionBody(copy, profile);

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            IconButton(
                              onPressed: () => Navigator.pop(context),
                              icon: const Icon(Icons.arrow_back_rounded),
                              color: AppColors.textPrimary,
                              style: IconButton.styleFrom(
                                backgroundColor: AppColors.surface.withValues(
                                  alpha: 0.72,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              AppCopy.t(
                                language,
                                ko: '루트 상세',
                                en: 'ROUTE DETAIL',
                                fr: 'DÉTAIL ROUTE',
                              ),
                              style: AppText.technicalLabel(
                                size: 11,
                                color: AppColors.primaryContainer,
                                letterSpacing: 2.0,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        _RouteShapeHero(route: route),
                        const SizedBox(height: 18),
                        Text(
                          profile.typeLabel,
                          style: AppText.technicalLabel(
                            size: 10,
                            color: AppColors.primaryContainer,
                            letterSpacing: 1.8,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          route.name,
                          style: AppText.display(
                            size: 34,
                            height: 0.98,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 14),
                        _QuickStatRow(route: route, language: language),
                        const SizedBox(height: 14),
                        _RouteConfidenceSection(profile: profile),
                        const SizedBox(height: 12),
                        _CopilotJudgementCard(
                          briefing: briefing,
                          language: language,
                        ),
                        const SizedBox(height: 12),
                        _MetricsGrid(route: route),
                        const SizedBox(height: 18),
                        _TurnPlanPreview(plan: turnPlan, language: language),
                        const SizedBox(height: 12),
                        _DetailSection(
                          title: AppCopy.t(
                            language,
                            ko: '왜 이 루트인가',
                            en: 'Why this route',
                            fr: 'Pourquoi cette route',
                          ),
                          icon: Icons.psychology_rounded,
                          body: copy.heroReason,
                        ),
                        const SizedBox(height: 12),
                        _DecisionBulletsSection(lines: copy.decisionBullets),
                        const SizedBox(height: 12),
                        _DetailSection(
                          title: AppCopy.t(
                            language,
                            ko: '주의할 점',
                            en: 'Watch-outs',
                            fr: 'À surveiller',
                          ),
                          icon: Icons.warning_amber_rounded,
                          body: cautionBody,
                          accent: AppColors.warning,
                        ),
                        const SizedBox(height: 12),
                        _DetailSection(
                          title: AppCopy.t(
                            language,
                            ko: '맞는 운전자',
                            en: 'Best for',
                            fr: 'Idéal pour',
                          ),
                          icon: Icons.auto_awesome_rounded,
                          body: bestFor,
                        ),
                        const SizedBox(height: 118),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          Positioned(
            left: 18,
            right: 18,
            bottom: MediaQuery.paddingOf(context).bottom + 14,
            child: _StickyStartBar(
              onStart: () => _startDrive(context),
              onBack: () => Navigator.pop(context),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickStatRow extends StatelessWidget {
  final RevvRoute route;
  final AppLanguage language;

  const _QuickStatRow({required this.route, required this.language});

  @override
  Widget build(BuildContext context) {
    final stopCount = route.stopSignCount + route.trafficSignalCount;
    final isFar = route.distanceFromUser >= 1.0;
    return Row(
      children: [
        _QuickStatPill(
          icon: Icons.flag_rounded,
          label: route.distanceFromUserDisplay,
          accent: isFar ? AppColors.warning : AppColors.primaryContainer,
        ),
        const SizedBox(width: 8),
        _QuickStatPill(
          icon: Icons.straighten_rounded,
          label: route.distanceDisplay,
        ),
        const SizedBox(width: 8),
        _QuickStatPill(
          icon: Icons.timer_outlined,
          label: route.durationDisplay,
        ),
        if (stopCount > 0) ...[
          const SizedBox(width: 8),
          _QuickStatPill(
            icon: Icons.stop_circle_outlined,
            label: AppCopy.t(
              language,
              ko: '정지 $stopCount개',
              en: '$stopCount stops',
              fr: '$stopCount arrêts',
            ),
            accent: AppColors.warning,
          ),
        ],
      ],
    );
  }
}

class _QuickStatPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color accent;

  const _QuickStatPill({
    required this.icon,
    required this.label,
    this.accent = AppColors.textSecondary,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: accent),
          const SizedBox(width: 5),
          Text(
            label,
            style: AppText.body(
              size: 12,
              weight: FontWeight.w900,
              color: accent,
            ),
          ),
        ],
      ),
    );
  }
}

class _CopilotJudgementCard extends StatelessWidget {
  final CopilotRouteBriefing briefing;
  final AppLanguage language;

  const _CopilotJudgementCard({required this.briefing, required this.language});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xE80F1214),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: AppColors.primaryContainer.withValues(alpha: 0.26),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppCopy.t(
              language,
              ko: '코파일럿 판단',
              en: 'COPILOT READ',
              fr: 'LECTURE COPILOTE',
            ),
            style: AppText.technicalLabel(
              size: 10,
              color: AppColors.primaryContainer,
              letterSpacing: 1.6,
            ),
          ),
          const SizedBox(height: 10),
          _CopilotJudgementRow(
            label: AppCopy.t(language, ko: '판단', en: 'Read', fr: 'Lecture'),
            text: briefing.primaryAdvice,
          ),
          _CopilotJudgementRow(
            label: AppCopy.t(language, ko: '시작', en: 'Start', fr: 'Départ'),
            text: briefing.startAdvice,
          ),
          _CopilotJudgementRow(
            label: AppCopy.t(language, ko: '주의', en: 'Risk', fr: 'Risque'),
            text: briefing.riskAdvice,
          ),
          _CopilotJudgementRow(
            label: AppCopy.t(language, ko: '성향', en: 'Fit', fr: 'Profil'),
            text: briefing.fitLabel,
            last: true,
          ),
        ],
      ),
    );
  }
}

class _CopilotJudgementRow extends StatelessWidget {
  final String label;
  final String text;
  final bool last;

  const _CopilotJudgementRow({
    required this.label,
    required this.text,
    this.last = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 76,
            child: Text(
              label,
              style: AppText.technicalLabel(
                size: 9,
                color: AppColors.textHint,
                letterSpacing: 1.1,
              ),
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: AppText.body(
                size: 13,
                height: 1.36,
                weight: FontWeight.w800,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RouteShapeHero extends StatelessWidget {
  final RevvRoute route;

  const _RouteShapeHero({required this.route});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 250,
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF101417), Color(0xFF182027), Color(0xFF0E0E0F)],
        ),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(
          color: AppColors.outlineVariant.withValues(alpha: 0.34),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.36),
            blurRadius: 34,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(painter: _RouteShapePainter(route)),
          ),
          Positioned(
            left: 4,
            bottom: 4,
            child: _HeroBadge(
              label: AppCopy.t(
                context.watch<SettingsService>().appLanguage,
                ko: '시작점',
                en: 'START',
                fr: 'DÉPART',
              ),
              value: route.distanceFromUserDisplay,
            ),
          ),
          Positioned(
            right: 4,
            top: 4,
            child: _HeroBadge(
              label: AppCopy.t(
                context.watch<SettingsService>().appLanguage,
                ko: '루트',
                en: 'ROUTE',
                fr: 'ROUTE',
              ),
              value: route.distanceDisplay,
              alignRight: true,
            ),
          ),
        ],
      ),
    );
  }
}

class _RouteConfidenceSection extends StatelessWidget {
  final RouteQualityProfile profile;

  const _RouteConfidenceSection({required this.profile});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xE80F1214),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: AppColors.primaryContainer.withValues(alpha: 0.24),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 56,
                height: 56,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.primaryContainer.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: AppColors.primaryContainer.withValues(alpha: 0.42),
                  ),
                ),
                child: Text(
                  '${profile.qualityScore}',
                  style: AppText.body(
                    size: 22,
                    weight: FontWeight.w900,
                    color: AppColors.primaryContainer,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppCopy.t(
                        context.watch<SettingsService>().appLanguage,
                        ko: '루트 신뢰도',
                        en: 'Route Confidence',
                        fr: 'Confiance route',
                      ),
                      style: AppText.technicalLabel(
                        size: 10,
                        color: AppColors.primaryContainer,
                        letterSpacing: 1.6,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${profile.typeLabel} · ${profile.curveDensityLabel}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.body(
                        size: 16,
                        weight: FontWeight.w900,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      profile.reasonLabel,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.body(
                        size: 12,
                        height: 1.3,
                        weight: FontWeight.w700,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final metric in profile.quickMetrics)
                _ConfidenceChip(label: metric.label, value: metric.value),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            profile.riskLabel,
            style: AppText.body(
              size: 12,
              height: 1.3,
              weight: FontWeight.w800,
              color: AppColors.warning,
            ),
          ),
        ],
      ),
    );
  }
}

class _ConfidenceChip extends StatelessWidget {
  final String label;
  final String value;

  const _ConfidenceChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.68),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: AppColors.outlineVariant.withValues(alpha: 0.20),
        ),
      ),
      child: Text(
        '$label $value',
        style: AppText.body(
          size: 11,
          weight: FontWeight.w900,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}

class _HeroBadge extends StatelessWidget {
  final String label;
  final String value;
  final bool alignRight;

  const _HeroBadge({
    required this.label,
    required this.value,
    this.alignRight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: alignRight
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppText.technicalLabel(size: 9, color: AppColors.textHint),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: AppText.body(
            size: 14,
            weight: FontWeight.w900,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}

class _MetricsGrid extends StatelessWidget {
  final RevvRoute route;

  const _MetricsGrid({required this.route});

  @override
  Widget build(BuildContext context) {
    final language = context.watch<SettingsService>().appLanguage;
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      childAspectRatio: 1.9,
      children: [
        _MetricTile(
          label: AppCopy.t(language, ko: '거리', en: 'Distance', fr: 'Distance'),
          value: route.distanceDisplay,
        ),
        _MetricTile(
          label: AppCopy.t(language, ko: '예상 시간', en: 'ETA', fr: 'Temps'),
          value: route.durationDisplay,
        ),
        _MetricTile(
          label: AppCopy.t(
            language,
            ko: '커브 구간',
            en: 'Curve km',
            fr: 'Virages',
          ),
          value: '${_curveKm(route)}km',
        ),
        _MetricTile(
          label: AppCopy.t(language, ko: '연속 흐름', en: 'Flow', fr: 'Rythme'),
          value: '${route.maxContinuousKm.toStringAsFixed(1)}km',
        ),
        _MetricTile(
          label: AppCopy.t(language, ko: '시작점', en: 'Start', fr: 'Départ'),
          value: route.distanceFromUserDisplay,
        ),
        _MetricTile(
          label: AppCopy.t(language, ko: '정지 요소', en: 'Stops', fr: 'Arrêts'),
          value: AppCopy.t(
            language,
            ko: '${route.stopSignCount + route.trafficSignalCount}개',
            en: '${route.stopSignCount + route.trafficSignalCount}',
            fr: '${route.stopSignCount + route.trafficSignalCount}',
          ),
        ),
      ],
    );
  }
}

class _MetricTile extends StatelessWidget {
  final String label;
  final String value;

  const _MetricTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.panel2.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: AppColors.outlineVariant.withValues(alpha: 0.24),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: AppText.technicalLabel(size: 9, color: AppColors.textHint),
          ),
          const SizedBox(height: 7),
          Text(
            value,
            style: AppText.body(
              size: 18,
              weight: FontWeight.w900,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _TurnPlanPreview extends StatelessWidget {
  final List<TurnInstruction> plan;
  final AppLanguage language;

  const _TurnPlanPreview({required this.plan, required this.language});

  @override
  Widget build(BuildContext context) {
    final visible = plan.take(5).toList();
    final hiddenCount = plan.length - visible.length;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.panel2.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: AppColors.primaryContainer.withValues(alpha: 0.24),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.route_rounded,
                color: AppColors.primaryContainer,
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  AppCopy.t(
                    language,
                    ko: '턴북',
                    en: 'TURN BOOK',
                    fr: 'CARNET VIRAGES',
                  ),
                  style: AppText.technicalLabel(
                    size: 10,
                    color: AppColors.primaryContainer,
                    letterSpacing: 1.6,
                  ),
                ),
              ),
              Text(
                AppCopy.t(
                  language,
                  ko: '${plan.length}개 안내',
                  en: '${plan.length} cues',
                  fr: '${plan.length} repères',
                ),
                style: AppText.technicalLabel(
                  size: 9,
                  color: AppColors.textHint,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (visible.isEmpty)
            Text(
              AppCopy.t(
                language,
                ko: '루트 라인을 불러오면 턴 안내가 표시됩니다.',
                en: 'Turn guidance appears once the route line is loaded.',
                fr: 'Les repères apparaissent avec la ligne de route.',
              ),
              style: AppText.body(
                size: 13,
                height: 1.35,
                weight: FontWeight.w700,
                color: AppColors.textSecondary,
              ),
            )
          else
            ...visible.map((instruction) {
              return _TurnPlanRow(instruction: instruction);
            }),
          if (hiddenCount > 0) ...[
            const SizedBox(height: 8),
            Text(
              AppCopy.t(
                language,
                ko: '+$hiddenCount개 더',
                en: '+$hiddenCount more',
                fr: '+$hiddenCount autres',
              ),
              style: AppText.technicalLabel(size: 9, color: AppColors.textHint),
            ),
          ],
        ],
      ),
    );
  }
}

class _TurnPlanRow extends StatelessWidget {
  final TurnInstruction instruction;

  const _TurnPlanRow({required this.instruction});

  @override
  Widget build(BuildContext context) {
    final accent = instruction.finish
        ? AppColors.success
        : _turnSeverityColor(instruction.severity);
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: accent.withValues(alpha: 0.28)),
            ),
            child: Icon(instruction.icon, size: 17, color: accent),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              instruction.headline,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.body(
                size: 14,
                weight: FontWeight.w900,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '#${instruction.sequence}',
            style: AppText.technicalLabel(size: 9, color: AppColors.textHint),
          ),
        ],
      ),
    );
  }
}

Color _turnSeverityColor(int severity) {
  if (severity >= 3) return AppColors.primaryContainer;
  if (severity == 2) return AppColors.warning;
  return AppColors.gold;
}

class _DecisionBulletsSection extends StatelessWidget {
  final List<String> lines;

  const _DecisionBulletsSection({required this.lines});

  @override
  Widget build(BuildContext context) {
    if (lines.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xE80F1214),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: AppColors.outlineVariant.withValues(alpha: 0.30),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.fact_check_rounded,
                color: AppColors.primaryContainer,
                size: 22,
              ),
              const SizedBox(width: 10),
              Text(
                AppCopy.t(
                  context.watch<SettingsService>().appLanguage,
                  ko: '선택 포인트',
                  en: 'Decision points',
                  fr: 'Points de choix',
                ),
                style: AppText.technicalLabel(
                  size: 10,
                  color: AppColors.primaryContainer,
                  letterSpacing: 1.6,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...lines.map(
            (line) => Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    margin: const EdgeInsets.only(top: 7),
                    decoration: const BoxDecoration(
                      color: AppColors.primaryContainer,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      line,
                      style: AppText.body(
                        size: 14,
                        height: 1.35,
                        weight: FontWeight.w700,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final String body;
  final Color accent;

  const _DetailSection({
    required this.title,
    required this.icon,
    required this.body,
    this.accent = AppColors.primaryContainer,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xE80F1214),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: AppColors.outlineVariant.withValues(alpha: 0.30),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: accent, size: 24),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppText.technicalLabel(
                    size: 10,
                    color: accent,
                    letterSpacing: 1.6,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  body,
                  style: AppText.body(
                    size: 14,
                    height: 1.45,
                    weight: FontWeight.w700,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StickyStartBar extends StatelessWidget {
  final VoidCallback onStart;
  final VoidCallback onBack;

  const _StickyStartBar({required this.onStart, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xF20F1214),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(
          color: AppColors.outlineVariant.withValues(alpha: 0.34),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.42),
            blurRadius: 30,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: const Icon(Icons.close_rounded),
            color: AppColors.textPrimary,
            style: IconButton.styleFrom(
              backgroundColor: AppColors.surface.withValues(alpha: 0.74),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(17),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SizedBox(
              height: 52,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primaryContainer,
                  foregroundColor: AppColors.onPrimary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                onPressed: onStart,
                child: Text(
                  AppCopy.t(
                    context.watch<SettingsService>().appLanguage,
                    ko: '주행 시작',
                    en: 'Start drive',
                    fr: 'Démarrer',
                  ),
                  style: AppText.body(
                    size: 16,
                    weight: FontWeight.w900,
                    color: AppColors.onPrimary,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RouteShapePainter extends CustomPainter {
  final RevvRoute route;

  const _RouteShapePainter(this.route);

  @override
  void paint(Canvas canvas, Size size) {
    final nodes = route.nodes;
    if (nodes.length < 2) return;

    var minLat = nodes.first.lat;
    var maxLat = nodes.first.lat;
    var minLng = nodes.first.lng;
    var maxLng = nodes.first.lng;
    for (final node in nodes) {
      minLat = math.min(minLat, node.lat);
      maxLat = math.max(maxLat, node.lat);
      minLng = math.min(minLng, node.lng);
      maxLng = math.max(maxLng, node.lng);
    }

    final latSpan = math.max(0.000001, maxLat - minLat);
    final lngSpan = math.max(0.000001, maxLng - minLng);
    final inset = math.min(size.width, size.height) * 0.14;
    final path = Path();

    for (var i = 0; i < nodes.length; i++) {
      final node = nodes[i];
      final x =
          inset + ((node.lng - minLng) / lngSpan) * (size.width - inset * 2);
      final y =
          inset +
          (1 - (node.lat - minLat) / latSpan) * (size.height - inset * 2);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    final shadow = Paint()
      ..color = Colors.black.withValues(alpha: 0.72)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 14;
    final casing = Paint()
      ..color = const Color(0xFF071015)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 9;
    final core = Paint()
      ..color = AppColors.primaryContainer
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 5;
    final glow = Paint()
      ..color = AppColors.primaryContainer.withValues(alpha: 0.18)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 22
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);

    canvas.drawPath(path, glow);
    canvas.drawPath(path.shift(const Offset(0, 4)), shadow);
    canvas.drawPath(path, casing);
    canvas.drawPath(path, core);
  }

  @override
  bool shouldRepaint(covariant _RouteShapePainter oldDelegate) {
    return oldDelegate.route.id != route.id;
  }
}

String _bestFor(RevvRoute route, AppLanguage language) {
  if (route.isLoop) {
    return AppCopy.t(
      language,
      ko: '짧게 확인하고 시작점 근처로 돌아오기 좋은 루프입니다.',
      en: 'A short validation drive that brings you back near the start.',
      fr: 'Une courte boucle de validation qui revient près du départ.',
    );
  }
  if (route.curveStyle == 'SWITCHBACK') {
    return AppCopy.t(
      language,
      ko: '타이트한 코너와 차분한 진입 라인을 읽는 데 좋습니다.',
      en: 'Reading tight corners and calm entry lines.',
      fr: 'Lire des virages serrés et des lignes d’entrée calmes.',
    );
  }
  if (route.curveStyle == 'SWEEPER') {
    return AppCopy.t(
      language,
      ko: '완만한 스위퍼와 길게 이어지는 조향 흐름에 좋습니다.',
      en: 'Smooth sweepers and longer steering flow.',
      fr: 'Grandes courbes fluides et rythme au volant.',
    );
  }
  if (route.maxContinuousKm >= 2.5) {
    return AppCopy.t(
      language,
      ko: '중간 리듬이 끊기지 않는 루트를 찾는 데 좋습니다.',
      en: 'Finding a route where the middle rhythm stays connected.',
      fr: 'Trouver une route où le rythme reste connecté.',
    );
  }
  return AppCopy.t(
    language,
    ko: '부담 없이 근처 도로를 비교하고 하나를 고르기 좋습니다.',
    en: 'Comparing nearby roads and picking one with low commitment.',
    fr: 'Comparer des routes proches sans gros engagement.',
  );
}

String _curveKm(RevvRoute route) {
  return (route.tightCurveKm + route.mediumCurveKm).toStringAsFixed(1);
}

String _cautionBody(RouteDetailCopy copy, RouteQualityProfile profile) {
  final caution = copy.cautionLine?.trim();
  if (caution == null || caution.isEmpty) return profile.riskLabel;
  if (profile.riskLabel.startsWith('기본 주의')) return caution;
  return '${profile.riskLabel}\n$caution';
}
