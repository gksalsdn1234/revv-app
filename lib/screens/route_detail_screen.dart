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
import '../theme/text_styles.dart';
import '../ui/revv_copy.dart';
import '../ui/route_detail_copy.dart';
import '../ui/ux_contracts.dart';
import '../widgets/mini_elev_chart.dart';
import '../widgets/revv_ui.dart';
import 'route_edit_screen.dart';
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
        final startNode = route.nodes.isNotEmpty
            ? route.nodes.first
            : route.centerPoint;
        final startDistanceKm = RevvRoute.haversineKm(
          LatLng(location.lat, location.lng),
          startNode,
        );
        final copy = RouteDetailCopy.fromRoute(
          route,
          startDistanceKm: startDistanceKm,
          hasComposite: activeComposite != null,
        );
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
          appBar: RevvTopBar(
            title: 'Route Detail',
            eyebrow: 'Decision Screen',
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
              IconButton(
                onPressed: () => _showRouteActions(context, route, svc),
                icon: const Icon(
                  Icons.more_horiz_rounded,
                  color: Colors.white70,
                ),
              ),
            ],
          ),
          body: RevvCockpitBackground(
            scanlines: true,
            child: ListView(
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
                _DecisionSummaryCard(copy: copy),
                const SizedBox(height: 12),
                _SectionCard(
                  title: '왜 이 루트인가',
                  child: Text(
                    copy.heroReason,
                    style: AppText.body(
                      size: 18,
                      weight: FontWeight.w700,
                      height: 1.35,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                if (copy.cautionLine?.isNotEmpty == true) ...[
                  const SizedBox(height: 12),
                  _SectionCard(
                    title: '주의할 점',
                    child: Text(
                      copy.cautionLine!,
                      style: AppText.body(
                        size: 15,
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
                                  color: AppColors.primaryContainer,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                '추천 이유를 정리하고 있어요...',
                                style: AppText.body(
                                  size: 14,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          )
                        : Text(
                            brief!,
                            style: AppText.body(
                              size: 14,
                              height: 1.35,
                              color: AppColors.textSecondary,
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
                              color: AppColors.primaryContainer,
                            ),
                          ),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (svc.connectingRoutes.isEmpty)
                              Text(
                                '이 루트 뒤에 자연스럽게 이어질 후보가 아직 없어요.',
                                style: AppText.body(
                                  size: 14,
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
          ),
          bottomNavigationBar: SafeArea(
            top: false,
            child: RevvGlassCard(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              radius: 28,
              color: AppColors.bg.withValues(alpha: 0.88),
              child: Row(
                children: [
                  Expanded(
                    child: RevvGhostButton(
                      label: RevvCopy.viewOnMap,
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
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: RevvPrimaryButton(
                      label: RevvCopy.startDrive,
                      icon: Icons.bolt_rounded,
                      onPressed: () {
                        context.read<RouteService>().requestSprint(
                          route: activeComposite?.toRouteProjection(),
                        );
                        Navigator.pop(context);
                      },
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
    return SharePlus.instance.share(
      ShareParams(text: RouteDetailCopy.fromRoute(route).shareText),
    );
  }

  void _showRouteActions(
    BuildContext context,
    RevvRoute route,
    RouteService svc,
  ) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _RouteActionsSheet(
        onEdit: () async {
          Navigator.pop(context);
          final result = await Navigator.push<RouteEditResult>(
            context,
            MaterialPageRoute(
              builder: (_) => RouteEditScreen(
                route: route,
                otherRoutes: svc.routes.where((r) => r.id != route.id).toList(),
              ),
            ),
          );
          if (result == null || !context.mounted) return;
          svc.selectRoute(result.route);
          if (result.branchRoute != null) {
            svc.addManualChain(result.branchRoute!);
          }
          if (context.mounted) Navigator.pop(context);
        },
        onSimilar: () {
          Navigator.pop(context);
          svc.fetchRoutes(route.centerPoint.lat, route.centerPoint.lng);
          Navigator.pop(context);
        },
        onReverse: () {
          Navigator.pop(context);
          svc.selectRoute(
            route.copyWith(
              id: '${route.id}_rev',
              nodes: route.nodes.reversed.toList(),
            ),
          );
          Navigator.pop(context);
        },
        onHeatmap: () {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('히트맵은 주행 전 지도 화면에 맞춰 준비 중이에요.'),
              backgroundColor: AppColors.panel2,
            ),
          );
        },
        onHide: () {
          Navigator.pop(context);
          svc.excludeRoute(route);
          Navigator.pop(context);
        },
      ),
    );
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
  final RouteDetailCopy copy;

  const _DecisionSummaryCard({required this.copy});

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: '지금 선택 포인트',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: copy.decisionBullets.map((line) {
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
}

class _RouteActionsSheet extends StatelessWidget {
  final VoidCallback onSimilar;
  final VoidCallback onReverse;
  final VoidCallback onHeatmap;
  final VoidCallback onHide;
  final VoidCallback onEdit;

  const _RouteActionsSheet({
    required this.onEdit,
    required this.onSimilar,
    required this.onReverse,
    required this.onHeatmap,
    required this.onHide,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        decoration: BoxDecoration(
          color: AppColors.panel2.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: AppColors.outlineVariant.withValues(alpha: 0.22),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.outline.withValues(alpha: 0.28),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              RevvCopy.more,
              style: AppText.body(
                size: 20,
                weight: FontWeight.w900,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            _RouteActionTile(
              icon: Icons.edit_rounded,
              label: RevvCopy.edit,
              body: '구간을 다듬거나 이어지는 분기를 조정해요.',
              onTap: onEdit,
            ),
            _RouteActionTile(
              icon: Icons.auto_awesome_rounded,
              label: '비슷한 루트 찾기',
              body: '이 루트 주변에서 비슷한 흐름의 후보를 다시 찾아요.',
              onTap: onSimilar,
            ),
            _RouteActionTile(
              icon: Icons.swap_horiz_rounded,
              label: '방향 반전',
              body: '같은 라인을 반대 방향 기준으로 다시 봐요.',
              onTap: onReverse,
            ),
            _RouteActionTile(
              icon: Icons.grid_view_rounded,
              label: '히트맵',
              body: '커브 밀도와 흐름 구간을 지도형으로 확인해요.',
              onTap: onHeatmap,
            ),
            const SizedBox(height: 6),
            Divider(color: AppColors.outlineVariant.withValues(alpha: 0.20)),
            const SizedBox(height: 6),
            _RouteActionTile(
              icon: Icons.block_rounded,
              label: '이 루트 숨기기',
              body: '추천 목록에서 이 루트를 제외해요.',
              destructive: true,
              onTap: onHide,
            ),
          ],
        ),
      ),
    );
  }
}

class _RouteActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String body;
  final bool destructive;
  final VoidCallback onTap;

  const _RouteActionTile({
    required this.icon,
    required this.label,
    required this.body,
    required this.onTap,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = destructive ? AppColors.red : AppColors.primaryContainer;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.panel.withValues(alpha: 0.62),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: destructive
                  ? AppColors.red.withValues(alpha: 0.30)
                  : AppColors.outlineVariant.withValues(alpha: 0.18),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 18, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: AppText.body(
                        size: 14,
                        weight: FontWeight.w900,
                        color: destructive
                            ? AppColors.red
                            : AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      body,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.body(
                        size: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: destructive ? AppColors.red : AppColors.textHint,
              ),
            ],
          ),
        ),
      ),
    );
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
    return RevvGlassCard(
      padding: EdgeInsets.zero,
      glow: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(height: 3, color: diffColor.withValues(alpha: 0.92)),
          Padding(
            padding: const EdgeInsets.all(16),
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
                    _Badge(
                      label: characterLabel,
                      color: diffColor,
                      outlined: true,
                    ),
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
                  style: AppText.body(
                    size: 26,
                    weight: FontWeight.w900,
                    letterSpacing: -0.8,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: RevvMetricTile(
                        label: 'distance',
                        value: route.distanceKm.toStringAsFixed(1),
                        unit: 'KM',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: RevvMetricTile(
                        label: 'difficulty',
                        value: route.difficultyLabel,
                        accent: diffColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  '${route.durationDisplay} · ${route.distanceFromUserDisplay}',
                  style: AppText.technicalLabel(
                    size: 11,
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
    return RevvGlassCard(
      padding: const EdgeInsets.all(16),
      color: AppColors.panel.withValues(alpha: 0.86),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: AppText.technicalLabel(
              size: 10,
              color: AppColors.primaryContainer,
              letterSpacing: 1.8,
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
    return RevvPill(
      label: label,
      color: color,
      backgroundColor: outlined ? color.withValues(alpha: 0.08) : null,
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.48),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: AppColors.outlineVariant.withValues(alpha: 0.26),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: AppColors.textHint),
          const SizedBox(width: 6),
          Text(
            label,
            style: AppText.body(
              size: 12,
              weight: FontWeight.w700,
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
    return RevvGlassCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            candidate.route.name,
            style: AppText.body(
              size: 16,
              weight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'gap ${candidate.gapKm.toStringAsFixed(1)}km · flow ${candidate.mergedFlowScore.toStringAsFixed(2)} · rank ${candidate.mergedRankScore.toStringAsFixed(1)}',
            style: AppText.technicalLabel(
              size: 11,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            note,
            style: AppText.body(
              size: 13,
              height: 1.3,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: RevvGhostButton(onPressed: onPreview, label: '체인 미리 보기'),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: RevvPrimaryButton(label: '체인 적용', onPressed: onApply),
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
      child: RevvGlassCard(
        padding: const EdgeInsets.all(12),
        color: AppColors.surface.withValues(alpha: 0.42),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '현재 체인 구성',
              style: AppText.body(
                size: 14,
                weight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${composite.totalDistanceKm.toStringAsFixed(1)} km · 재미 ${composite.funScore.toStringAsFixed(1)} · 흐름 ${composite.flowScore.toStringAsFixed(2)}',
              style: AppText.technicalLabel(
                size: 11,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              composite.connectorLegs.isEmpty
                  ? '별도 연결 구간 없이 이어집니다.'
                  : '연결 구간 ${composite.connectorLegs.first.distanceKm.toStringAsFixed(1)}km가 포함돼 있어 preview에서 흐름을 꼭 확인하세요.',
              style: AppText.body(
                size: 13,
                height: 1.3,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
