import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/chain_candidate.dart';
import '../models/composite_route.dart';
import '../models/revv_route.dart';
import '../services/location_service.dart';
import '../services/route_service.dart';
import '../services/saved_route_service.dart';
import '../theme/colors.dart';
import '../ui/ux_contracts.dart';
import '../widgets/mini_elev_chart.dart';
import 'route_preview_screen.dart';

class RouteDetailScreen extends StatelessWidget {
  final String routeId;
  final String? brief;
  final bool briefLoading;

  const RouteDetailScreen({
    super.key,
    required this.routeId,
    this.brief,
    this.briefLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<RouteService>(
      builder: (context, svc, _) {
        final route = svc.routes.cast<RevvRoute?>().firstWhere(
          (candidate) => candidate?.id == routeId,
          orElse: () =>
              svc.selectedRoute?.id == routeId ? svc.selectedRoute : null,
        );
        if (route == null) {
          return Scaffold(
            backgroundColor: AppColors.bg,
            appBar: AppBar(backgroundColor: AppColors.panel),
            body: Center(
              child: Text(
                '루트 정보를 찾을 수 없어요.',
                style: GoogleFonts.rajdhani(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          );
        }

        final activeComposite =
            svc.previewCompositeRoute ?? svc.selectedCompositeRoute;
        final saveTarget = activeComposite?.toRouteProjection() ?? route;
        final location = context.watch<LocationService>();
        final isSaved = context.watch<SavedRouteService>().isSaved(
          saveTarget.id,
        );
        final diffColor = _difficultyColor(route);
        final qualityLabel = describeRouteQuality(
          route.qualityLabel.isNotEmpty ? route.qualityLabel : 'keep',
        );
        final characterLabel = describeRouteCharacter(
          route.routeCharacter.isNotEmpty
              ? route.routeCharacter
              : 'mixed_touring',
        );

        return Scaffold(
          backgroundColor: AppColors.bg,
          appBar: AppBar(
            backgroundColor: AppColors.panel,
            title: Text(
              'ROUTE DETAIL',
              style: GoogleFonts.orbitron(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                letterSpacing: 1.5,
              ),
            ),
            actions: [
              IconButton(
                onPressed: () =>
                    context.read<SavedRouteService>().toggle(saveTarget),
                icon: Icon(
                  isSaved
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  color: isSaved ? AppColors.red : Colors.white54,
                ),
              ),
              IconButton(
                onPressed: () => _shareRoute(saveTarget),
                icon: const Icon(
                  Icons.ios_share_rounded,
                  color: Colors.white70,
                ),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
            children: [
              _HeroCard(
                route: route,
                diffColor: diffColor,
                qualityLabel: qualityLabel,
                characterLabel: characterLabel,
              ),
              const SizedBox(height: 12),
              _StartPlanCard(
                route: route,
                activeComposite: activeComposite,
                location: location,
              ),
              const SizedBox(height: 12),
              _DecisionSummaryCard(
                route: route,
                activeComposite: activeComposite,
                location: location,
              ),
              const SizedBox(height: 12),
              _SectionCard(
                title: '왜 이 루트인가',
                child: Text(
                  route.primaryReason ?? '지금 달리기 좋은 루트예요.',
                  style: GoogleFonts.rajdhani(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                    color: Colors.white,
                  ),
                ),
              ),
              if (route.cautionNote?.isNotEmpty == true) ...[
                const SizedBox(height: 12),
                _SectionCard(
                  title: '주의할 점',
                  child: Text(
                    route.cautionNote!,
                    style: GoogleFonts.rajdhani(
                      fontSize: 15,
                      height: 1.35,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
              if (briefLoading || brief != null) ...[
                const SizedBox(height: 12),
                _SectionCard(
                  title: 'AI 요약',
                  child: briefLoading
                      ? Row(
                          children: [
                            const SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                                color: AppColors.red,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              '추천 이유를 정리하고 있어요...',
                              style: GoogleFonts.rajdhani(
                                fontSize: 14,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        )
                      : Text(
                          brief!,
                          style: GoogleFonts.rajdhani(
                            fontSize: 14,
                            height: 1.35,
                            color: Colors.white70,
                          ),
                        ),
                ),
              ],
              const SizedBox(height: 12),
              _SectionCard(
                title: '루트 감각',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _MetricChip(
                          icon: Icons.straighten,
                          label: route.distanceDisplay,
                        ),
                        _MetricChip(
                          icon: Icons.timer_outlined,
                          label: route.durationDisplay,
                        ),
                        _MetricChip(
                          icon: Icons.route_rounded,
                          label: route.difficultyLabel,
                        ),
                        if (route.stopSignCount > 0 ||
                            route.trafficSignalCount > 0)
                          _MetricChip(
                            icon: Icons.traffic_rounded,
                            label:
                                'STOP ${route.stopSignCount} · SIGNAL ${route.trafficSignalCount}',
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    MiniElevSection(route: route, lineColor: diffColor),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _SectionCard(
                title: '체인 추천',
                child: svc.isLoadingConnecting
                    ? const SizedBox(
                        height: 36,
                        child: Center(
                          child: CircularProgressIndicator(
                            strokeWidth: 1.6,
                            color: AppColors.red,
                          ),
                        ),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (svc.connectingRoutes.isEmpty)
                            Text(
                              '이 루트 뒤에 자연스럽게 이어질 후보가 아직 없어요.',
                              style: GoogleFonts.rajdhani(
                                fontSize: 14,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ...svc.connectingRoutes.map(
                            (candidate) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _ChainTile(
                                candidate: candidate,
                                onPreview: () =>
                                    svc.previewChainCandidate(candidate),
                                onApply: () =>
                                    svc.commitCompositeRoute(candidate),
                              ),
                            ),
                          ),
                          if (activeComposite != null)
                            _CompositeSummary(composite: activeComposite),
                        ],
                      ),
              ),
            ],
          ),
          bottomNavigationBar: SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              decoration: BoxDecoration(
                color: AppColors.panel,
                border: Border(
                  top: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                          color: Colors.white.withValues(alpha: 0.2),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => RoutePreviewScreen(
                              route: activeComposite == null ? route : null,
                              compositeRoute: activeComposite,
                            ),
                          ),
                        );
                      },
                      child: Text(
                        '출발 방식 보기',
                        style: GoogleFonts.rajdhani(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Colors.white70,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.red,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: () {
                        context.read<RouteService>().requestSprint(
                          route: activeComposite?.toRouteProjection(),
                        );
                        Navigator.pop(context);
                      },
                      child: Text(
                        '이 루트로 달리기',
                        style: GoogleFonts.rajdhani(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Color _difficultyColor(RevvRoute route) {
    switch (route.difficultyLevel) {
      case 4:
        return const Color(0xFFEF4444);
      case 3:
        return const Color(0xFFF97316);
      case 2:
        return const Color(0xFFF59E0B);
      case 1:
        return const Color(0xFF22C55E);
      default:
        return AppColors.cyan;
    }
  }

  Future<void> _shareRoute(RevvRoute route) {
    final text = StringBuffer()
      ..writeln('REVV 추천 루트')
      ..writeln(route.name)
      ..writeln('${route.distanceDisplay} · ${route.durationDisplay}')
      ..writeln(describeRouteCharacter(route.routeCharacter))
      ..writeln(route.primaryReason ?? '지금 달리기 좋은 루트예요.');
    return Share.share(text.toString().trim());
  }
}

class _StartPlanCard extends StatelessWidget {
  final RevvRoute route;
  final CompositeRoute? activeComposite;
  final LocationService location;

  const _StartPlanCard({
    required this.route,
    required this.activeComposite,
    required this.location,
  });

  @override
  Widget build(BuildContext context) {
    final startNode = route.nodes.isNotEmpty
        ? route.nodes.first
        : route.centerPoint;
    final user = LatLng(location.lat, location.lng);
    final startDistanceKm = RevvRoute.haversineKm(user, startNode);

    final plan = _resolveStartPlan(startDistanceKm);
    final chainHint = activeComposite == null
        ? '단일 루트로 시작합니다.'
        : '체인 적용 상태라 첫 구간 뒤에 자동으로 다음 구간 흐름을 이어보게 됩니다.';

    return _SectionCard(
      title: '출발 플랜',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _Badge(label: plan.label, color: plan.color),
              const SizedBox(width: 8),
              Text(
                '시작점까지 ${_distanceLabel(startDistanceKm)}',
                style: GoogleFonts.rajdhani(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            plan.summary,
            style: GoogleFonts.rajdhani(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              height: 1.35,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            chainHint,
            style: GoogleFonts.rajdhani(
              fontSize: 13,
              height: 1.35,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  _StartPlan _resolveStartPlan(double startDistanceKm) {
    if (startDistanceKm < 0.3) {
      return const _StartPlan(
        label: '바로 시작 가능',
        summary: '지금 위치가 시작점에 가까워 바로 주행을 시작해도 자연스러워요.',
        color: Color(0xFF22C55E),
      );
    }
    if (startDistanceKm < 5.0) {
      return const _StartPlan(
        label: '시작점까지 안내 권장',
        summary: '먼저 시작점까지 짧게 이동한 뒤 루트 본편에 들어가는 편이 가장 매끄러워요.',
        color: Color(0xFFF59E0B),
      );
    }
    return const _StartPlan(
      label: '중간 합류 준비',
      summary: '현재 위치가 시작점에서 꽤 떨어져 있어 preview에서 합류 흐름을 먼저 확인하는 게 좋아요.',
      color: AppColors.cyan,
    );
  }

  String _distanceLabel(double distanceKm) {
    if (distanceKm < 1) return '${(distanceKm * 1000).round()}m';
    return '${distanceKm.toStringAsFixed(1)}km';
  }
}

class _DecisionSummaryCard extends StatelessWidget {
  final RevvRoute route;
  final CompositeRoute? activeComposite;
  final LocationService location;

  const _DecisionSummaryCard({
    required this.route,
    required this.activeComposite,
    required this.location,
  });

  @override
  Widget build(BuildContext context) {
    final startNode = route.nodes.isNotEmpty
        ? route.nodes.first
        : route.centerPoint;
    final startDistanceKm = RevvRoute.haversineKm(
      LatLng(location.lat, location.lng),
      startNode,
    );
    final bullets = <String>[
      route.primaryReason ?? '지금 달리기 좋은 루트예요.',
      buildSprintStartSummary(
        startDistanceKm,
        _recommendedMode(startDistanceKm),
      ),
      if (route.cautionNote?.isNotEmpty == true) route.cautionNote!,
      if (activeComposite != null) '체인이 적용돼 첫 구간 뒤에 다음 흐름까지 이어서 볼 수 있어요.',
    ];

    return _SectionCard(
      title: '지금 선택 포인트',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: bullets.take(3).map((line) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  margin: const EdgeInsets.only(top: 6),
                  decoration: const BoxDecoration(
                    color: AppColors.red,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    line,
                    style: GoogleFonts.rajdhani(
                      fontSize: 14,
                      height: 1.35,
                      color: Colors.white70,
                    ),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  SprintStartMode _recommendedMode(double startDistanceKm) {
    if (startDistanceKm < 0.3) return SprintStartMode.auto;
    if (startDistanceKm < 5.0) return SprintStartMode.guideToStart;
    return SprintStartMode.joinFromCurrent;
  }
}

class _StartPlan {
  final String label;
  final String summary;
  final Color color;

  const _StartPlan({
    required this.label,
    required this.summary,
    required this.color,
  });
}

class _HeroCard extends StatelessWidget {
  final RevvRoute route;
  final Color diffColor;
  final String qualityLabel;
  final String characterLabel;

  const _HeroCard({
    required this.route,
    required this.diffColor,
    required this.qualityLabel,
    required this.characterLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: diffColor.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _Badge(
                label: qualityLabel,
                color: _qualityColor(route.qualityLabel),
              ),
              _Badge(label: characterLabel, color: diffColor, outlined: true),
              if (route.isLoop)
                const _Badge(
                  label: '루프 코스',
                  color: AppColors.cyan,
                  outlined: true,
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            route.name,
            style: GoogleFonts.rajdhani(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${route.distanceDisplay} · ${route.durationDisplay} · ${route.distanceFromUserDisplay}',
            style: GoogleFonts.rajdhani(fontSize: 15, color: Colors.white70),
          ),
        ],
      ),
    );
  }

  Color _qualityColor(String qualityLabel) {
    switch (qualityLabel) {
      case 'maybe':
        return const Color(0xFFF59E0B);
      case 'reject':
        return const Color(0xFFEF4444);
      default:
        return const Color(0xFF22C55E);
    }
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _SectionCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: GoogleFonts.orbitron(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  final bool outlined;

  const _Badge({
    required this.label,
    required this.color,
    this.outlined = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: outlined
            ? color.withValues(alpha: 0.10)
            : color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: outlined
              ? color.withValues(alpha: 0.45)
              : color.withValues(alpha: 0.65),
        ),
      ),
      child: Text(
        label,
        style: GoogleFonts.rajdhani(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MetricChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: AppColors.textHint),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.rajdhani(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _ChainTile extends StatelessWidget {
  final ChainCandidate candidate;
  final VoidCallback onPreview;
  final VoidCallback onApply;

  const _ChainTile({
    required this.candidate,
    required this.onPreview,
    required this.onApply,
  });

  @override
  Widget build(BuildContext context) {
    final note = _chainNote(candidate);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            candidate.route.name,
            style: GoogleFonts.rajdhani(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'gap ${candidate.gapKm.toStringAsFixed(1)}km · flow ${candidate.mergedFlowScore.toStringAsFixed(2)} · rank ${candidate.mergedRankScore.toStringAsFixed(1)}',
            style: GoogleFonts.rajdhani(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            note,
            style: GoogleFonts.rajdhani(
              fontSize: 13,
              height: 1.3,
              color: Colors.white70,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onPreview,
                  child: Text(
                    '체인 미리 보기',
                    style: GoogleFonts.rajdhani(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.white70,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.red,
                  ),
                  onPressed: onApply,
                  child: Text(
                    '체인 적용',
                    style: GoogleFonts.rajdhani(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _chainNote(ChainCandidate candidate) {
    if (candidate.gapKm <= 1.0 && candidate.mergedFlowScore >= 0.75) {
      return '구간 사이 간격이 짧고 흐름 손실이 적어 자연스럽게 이어붙이기 좋은 후보예요.';
    }
    if (candidate.gapKm <= 2.5) {
      return '연결 거리는 조금 있지만, 전체 거리를 늘리고 싶을 때 검토할 만한 후보예요.';
    }
    return '연결 거리가 긴 편이라 preview에서 실제 합류 느낌을 먼저 확인하는 편이 좋아요.';
  }
}

class _CompositeSummary extends StatelessWidget {
  final CompositeRoute composite;

  const _CompositeSummary({required this.composite});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.red.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '현재 체인 구성',
            style: GoogleFonts.rajdhani(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${composite.totalDistanceKm.toStringAsFixed(1)} km · 재미 ${composite.funScore.toStringAsFixed(1)} · 흐름 ${composite.flowScore.toStringAsFixed(2)}',
            style: GoogleFonts.rajdhani(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            composite.connectorLegs.isEmpty
                ? '별도 연결 구간 없이 이어집니다.'
                : '연결 구간 ${composite.connectorLegs.first.distanceKm.toStringAsFixed(1)}km가 포함돼 있어 preview에서 흐름을 꼭 확인하세요.',
            style: GoogleFonts.rajdhani(
              fontSize: 13,
              height: 1.3,
              color: Colors.white70,
            ),
          ),
        ],
      ),
    );
  }
}
