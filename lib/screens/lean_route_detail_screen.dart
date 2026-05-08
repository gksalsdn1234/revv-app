import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/revv_route.dart';
import '../theme/colors.dart';
import '../theme/text_styles.dart';
import '../ui/copilot_briefing.dart';
import '../ui/route_detail_copy.dart';
import '../ui/route_quality_profile.dart';
import '../widgets/copilot_start_sheet.dart';
import 'lean_drive_screen.dart';

class LeanRouteDetailScreen extends StatelessWidget {
  final RevvRoute route;

  const LeanRouteDetailScreen({super.key, required this.route});

  Future<void> _startDrive(BuildContext context) async {
    final shouldStart = await showCopilotStartSheet(context, route: route);
    if (!context.mounted || shouldStart != true) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => LeanDriveScreen(route: route)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final copy = RouteDetailCopy.fromRoute(
      route,
      startDistanceKm: route.distanceFromUser,
    );
    final profile = RouteQualityProfile.fromRoute(route);
    final briefing = CopilotRouteBriefing.fromRoute(
      route,
      profile: profile,
      startDistanceKm: route.distanceFromUser,
    );
    final bestFor = _bestFor(route);
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
                              '루트 상세',
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
                        const SizedBox(height: 18),
                        _RouteConfidenceSection(profile: profile),
                        const SizedBox(height: 12),
                        _CopilotJudgementCard(briefing: briefing),
                        const SizedBox(height: 12),
                        _MetricsGrid(route: route),
                        const SizedBox(height: 18),
                        _DetailSection(
                          title: '왜 이 루트인가',
                          icon: Icons.psychology_rounded,
                          body: copy.heroReason,
                        ),
                        const SizedBox(height: 12),
                        _DecisionBulletsSection(lines: copy.decisionBullets),
                        const SizedBox(height: 12),
                        _DetailSection(
                          title: '주의할 점',
                          icon: Icons.warning_amber_rounded,
                          body: cautionBody,
                          accent: AppColors.warning,
                        ),
                        const SizedBox(height: 12),
                        _DetailSection(
                          title: 'Best for',
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

class _CopilotJudgementCard extends StatelessWidget {
  final CopilotRouteBriefing briefing;

  const _CopilotJudgementCard({required this.briefing});

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
            '코파일럿 판단',
            style: AppText.technicalLabel(
              size: 10,
              color: AppColors.primaryContainer,
              letterSpacing: 1.6,
            ),
          ),
          const SizedBox(height: 10),
          _CopilotJudgementRow(label: '추천 판단', text: briefing.primaryAdvice),
          _CopilotJudgementRow(label: '시작 방식', text: briefing.startAdvice),
          _CopilotJudgementRow(label: '주의 포인트', text: briefing.riskAdvice),
          _CopilotJudgementRow(
            label: '맞는 운전자',
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
              label: 'START',
              value: route.distanceFromUserDisplay,
            ),
          ),
          Positioned(
            right: 4,
            top: 4,
            child: _HeroBadge(
              label: 'ROUTE',
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
                      'Route Confidence',
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
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      childAspectRatio: 1.9,
      children: [
        _MetricTile(label: '거리', value: route.distanceDisplay),
        _MetricTile(label: '예상 시간', value: route.durationDisplay),
        _MetricTile(label: '커브 구간', value: '${_curveKm(route)}km'),
        _MetricTile(
          label: '연속 흐름',
          value: '${route.maxContinuousKm.toStringAsFixed(1)}km',
        ),
        _MetricTile(label: '시작점', value: route.distanceFromUserDisplay),
        _MetricTile(
          label: '정지 요소',
          value: '${route.stopSignCount + route.trafficSignalCount}개',
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
                '선택 포인트',
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
                  '주행 시작',
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

String _bestFor(RevvRoute route) {
  if (route.isLoop) return '출발지 근처로 돌아오는 짧은 확인 주행에 잘 맞아요.';
  if (route.curveStyle == 'SWITCHBACK') {
    return '타이트한 코너와 진입 라인을 차분히 확인하고 싶을 때 좋아요.';
  }
  if (route.curveStyle == 'SWEEPER') return '부드러운 스위퍼와 긴 조향 흐름을 느끼고 싶을 때 어울려요.';
  if (route.maxContinuousKm >= 2.5) return '중간에 흐름이 끊기지 않는 루트를 찾을 때 좋아요.';
  return '가볍게 근교 루트를 비교하고 하나를 고를 때 좋은 후보예요.';
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
