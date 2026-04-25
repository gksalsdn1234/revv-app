import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/revv_route.dart';
import '../services/saved_route_service.dart';
import '../theme/colors.dart';
import '../theme/text_styles.dart';
import '../ui/ux_contracts.dart';
import 'revv_ui.dart';

class RoutesSelectionPanel extends StatelessWidget {
  final RevvRoute route;
  final Color diffColor;
  final bool expanded;
  final int connectingCount;
  final double totalChainKm;
  final bool isGeneratingExtension;
  final bool hasActiveExtension;
  final VoidCallback onGo;
  final VoidCallback onExpand;
  final VoidCallback onCollapse;
  final VoidCallback onClose;
  final VoidCallback? onTrim;
  final VoidCallback? onReverse;
  final VoidCallback? onFindSimilar;
  final VoidCallback? onChain;
  final VoidCallback? onGenerate;
  final VoidCallback? onHeatmap;
  final VoidCallback? onEdit;
  final VoidCallback? onExclude;
  final VoidCallback? onPreview;
  final VoidCallback? onSaved;

  const RoutesSelectionPanel({
    super.key,
    required this.route,
    required this.diffColor,
    required this.expanded,
    required this.connectingCount,
    required this.totalChainKm,
    required this.isGeneratingExtension,
    required this.hasActiveExtension,
    required this.onGo,
    required this.onExpand,
    required this.onCollapse,
    required this.onClose,
    this.onTrim,
    this.onReverse,
    this.onFindSimilar,
    this.onChain,
    this.onGenerate,
    this.onHeatmap,
    this.onEdit,
    this.onExclude,
    this.onPreview,
    this.onSaved,
  });

  @override
  Widget build(BuildContext context) {
    final savedSvc = context.watch<SavedRouteService>();
    final isSaved = savedSvc.isSaved(route.id);
    final recommendation = buildRouteRecommendation(route);
    final qualityLabel = describeRouteQuality(
      route.qualityLabel.isNotEmpty ? route.qualityLabel : 'keep',
    );
    final characterLabel = describeRouteCharacter(
      route.routeCharacter.isNotEmpty ? route.routeCharacter : 'mixed_touring',
    );

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: expanded ? MediaQuery.sizeOf(context).height * 0.45 : 166,
      ),
      child: RevvGlassCard(
        key: ValueKey('route-${route.id}'),
        margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        padding: const EdgeInsets.fromLTRB(14, 8, 12, 12),
        color: AppColors.panel.withValues(alpha: 0.94),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: GestureDetector(
                onTap: expanded ? onCollapse : onExpand,
                child: Container(
                  width: 44,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: AppColors.outline.withValues(alpha: 0.42),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        recommendation.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.body(
                          size: 20,
                          weight: FontWeight.w900,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ),
                    _Pressable(
                      onTap: () {
                        context.read<SavedRouteService>().toggle(route);
                        if (!isSaved) onSaved?.call();
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          transitionBuilder: (child, anim) =>
                              ScaleTransition(scale: anim, child: child),
                          child: Icon(
                            isSaved
                                ? Icons.favorite_rounded
                                : Icons.favorite_border_rounded,
                            key: ValueKey(isSaved),
                            size: 20,
                            color: isSaved
                                ? AppColors.primaryContainer
                                : Colors.white38,
                          ),
                        ),
                      ),
                    ),
                    _Pressable(
                      onTap: onClose,
                      child: const Padding(
                        padding: EdgeInsets.all(6),
                        child: Icon(
                          Icons.close,
                          size: 18,
                          color: Colors.white54,
                        ),
                      ),
                    ),
                  ],
                ),
                if (expanded) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _DiscoveryBadge(
                        label: qualityLabel,
                        color: route.qualityLabel == 'maybe'
                            ? const Color(0xFFF59E0B)
                            : route.qualityLabel == 'reject'
                            ? const Color(0xFFEF4444)
                            : const Color(0xFF22C55E),
                      ),
                      _DiscoveryBadge(
                        label: characterLabel,
                        color: diffColor,
                        outlined: true,
                      ),
                      if (route.isLoop)
                        const _DiscoveryBadge(
                          label: '루프 코스',
                          color: AppColors.cyan,
                          outlined: true,
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _RouteReviewCard(
                    reason: recommendation.reason,
                    characterLabel: characterLabel,
                    qualityLabel: qualityLabel,
                    signalCount:
                        route.stopSignCount + route.trafficSignalCount,
                  ),
                ],
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (hasActiveExtension)
                      _MetricChip(
                        icon: Icons.add_road_rounded,
                        label: '확장 적용 · ${totalChainKm.toStringAsFixed(0)}km',
                        color: AppColors.primaryContainer,
                      ),
                    if (isGeneratingExtension)
                      const _MetricChip(
                        icon: Icons.sync_rounded,
                        label: '확장 후보 찾는 중',
                        color: AppColors.primaryContainer,
                        busy: true,
                      ),
                    ...recommendation.primaryMetrics.map(
                      (metric) => _MetricChip(
                        icon: metric == route.distanceDisplay
                            ? Icons.straighten
                            : metric == route.durationDisplay
                            ? Icons.timer_outlined
                            : Icons.auto_awesome_rounded,
                        label: metric,
                      ),
                    ),
                    if (expanded &&
                        (route.stopSignCount > 0 ||
                            route.trafficSignalCount > 0))
                      _MetricChip(
                        icon: Icons.traffic_rounded,
                        label:
                            'STOP ${route.stopSignCount} · SIGNAL ${route.trafficSignalCount}',
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _MainActionButton(
                        label: '편집',
                        icon: Icons.tune_rounded,
                        onTap: onEdit ?? onTrim,
                        primary: false,
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (onGenerate != null) ...[
                      Expanded(
                        child: _MainActionButton(
                          label: isGeneratingExtension ? '찾는중' : '확장',
                          icon: Icons.auto_fix_high_rounded,
                          onTap: isGeneratingExtension ? null : onGenerate,
                          primary: false,
                          busy: isGeneratingExtension,
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: _MainActionButton(
                        label: '더보기',
                        icon: Icons.more_horiz_rounded,
                        onTap: () => _showAdvanced(context),
                        primary: false,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: _MainActionButton(
                        label: '달리기',
                        icon: Icons.navigation_rounded,
                        onTap: onGo,
                        primary: true,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showAdvanced(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _AdvancedRouteSheet(
        onPreview: onPreview,
        onReverse: onReverse,
        onFindSimilar: onFindSimilar,
        onChain: onChain,
        onHeatmap: onHeatmap,
        onEdit: onEdit,
        onTrim: onTrim,
        onExclude: onExclude,
      ),
    );
  }
}

class _RouteReviewCard extends StatelessWidget {
  final String reason;
  final String characterLabel;
  final String qualityLabel;
  final int signalCount;

  const _RouteReviewCard({
    required this.reason,
    required this.characterLabel,
    required this.qualityLabel,
    required this.signalCount,
  });

  String get _supportingLine {
    if (signalCount >= 8) {
      return '신호나 정지 구간이 조금 있어 흐름이 끊기지 않는지 먼저 보고 들어가는 편이 좋아요.';
    }
    if (characterLabel == '스위퍼 중심') {
      return '긴 호흡으로 이어지는 코너가 많아서 리듬감 있게 타기 좋은 타입이에요.';
    }
    if (characterLabel == '타이트 코너') {
      return '짧고 촘촘한 방향 전환이 많아 진입 템포를 천천히 맞추면 훨씬 재미있어요.';
    }
    if (qualityLabel == '추천') {
      return '지금 위치 기준으로 보면 REVV가 우선 추천할 만한 밸런스예요.';
    }
    return '지도에서 라인 흐름을 한 번 보고 들어가면 체감이 더 좋아질 거예요.';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh.withValues(alpha: 0.44),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.outlineVariant.withValues(alpha: 0.32),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.rate_review_rounded,
                size: 15,
                color: AppColors.primaryContainer,
              ),
              const SizedBox(width: 6),
              Text(
                'REVV 리뷰',
                style: AppText.technicalLabel(
                  size: 10,
                  color: AppColors.primaryContainer,
                  letterSpacing: 1.6,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            reason,
            style: AppText.body(
              size: 13,
              height: 1.35,
              weight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _supportingLine,
            style: AppText.body(
              size: 12,
              height: 1.35,
              weight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _DiscoveryBadge extends StatelessWidget {
  final String label;
  final Color color;
  final bool outlined;

  const _DiscoveryBadge({
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
  final Color? color;
  final bool busy;

  const _MetricChip({
    required this.icon,
    required this.label,
    this.color,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.46),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: AppColors.outlineVariant.withValues(alpha: 0.28),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (busy)
            SizedBox(
              width: 13,
              height: 13,
              child: CircularProgressIndicator(
                strokeWidth: 1.7,
                color: color ?? Colors.white54,
              ),
            )
          else
            Icon(icon, size: 13, color: color ?? Colors.white54),
          const SizedBox(width: 5),
          Text(
            label,
            style: AppText.body(
              size: 12,
              weight: FontWeight.w700,
              color: color ?? AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _MainActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final bool primary;
  final bool busy;

  const _MainActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
    required this.primary,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    final bg = primary
        ? AppColors.primaryContainer
        : AppColors.surfaceHigh.withValues(alpha: 0.52);
    final fg = primary ? AppColors.onPrimary : AppColors.textPrimary;
    return _Pressable(
      onTap: onTap,
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
          border: primary
              ? null
              : Border.all(
                  color: AppColors.outlineVariant.withValues(alpha: 0.35),
                ),
          boxShadow: primary
              ? [
                  BoxShadow(
                    color: AppColors.primaryContainer.withValues(alpha: 0.22),
                    blurRadius: 14,
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (busy)
              SizedBox(
                width: 15,
                height: 15,
                child: CircularProgressIndicator(strokeWidth: 1.8, color: fg),
              )
            else
              Icon(icon, size: 16, color: fg),
            const SizedBox(width: 6),
            Text(
              label,
              style: AppText.body(size: 13, weight: FontWeight.w900, color: fg),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdvancedRouteSheet extends StatelessWidget {
  final VoidCallback? onPreview;
  final VoidCallback? onReverse;
  final VoidCallback? onFindSimilar;
  final VoidCallback? onChain;
  final VoidCallback? onHeatmap;
  final VoidCallback? onEdit;
  final VoidCallback? onTrim;
  final VoidCallback? onExclude;

  const _AdvancedRouteSheet({
    this.onPreview,
    this.onReverse,
    this.onFindSimilar,
    this.onChain,
    this.onHeatmap,
    this.onEdit,
    this.onTrim,
    this.onExclude,
  });

  @override
  Widget build(BuildContext context) {
    final items =
        <
              ({
                IconData icon,
                String label,
                VoidCallback? onTap,
                bool destructive,
              })
            >[
              (
                icon: Icons.route_rounded,
                label: '자세히 보기',
                onTap: onPreview,
                destructive: false,
              ),
              (
                icon: Icons.swap_horiz_rounded,
                label: '방향 반전',
                onTap: onReverse,
                destructive: false,
              ),
              (
                icon: Icons.auto_awesome_rounded,
                label: '비슷한 루트',
                onTap: onFindSimilar,
                destructive: false,
              ),
              (
                icon: Icons.add_link_rounded,
                label: '체인 연결',
                onTap: onChain,
                destructive: false,
              ),
              (
                icon: Icons.local_fire_department_rounded,
                label: '커브 히트맵',
                onTap: onHeatmap,
                destructive: false,
              ),
              (
                icon: Icons.edit_rounded,
                label: '편집 스튜디오',
                onTap: onEdit ?? onTrim,
                destructive: false,
              ),
              (
                icon: Icons.block_rounded,
                label: '이 루트 숨기기',
                onTap: onExclude,
                destructive: true,
              ),
            ]
            .where((item) => item.onTap != null)
            .toList();

    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        decoration: BoxDecoration(
          color: const Color(0xF2141416),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '더보기',
              style: AppText.body(
                size: 18,
                weight: FontWeight.w900,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            ...items
                .where((item) => !item.destructive)
                .map((item) => _AdvancedRouteAction(item: item)),
            if (items.any((item) => item.destructive)) ...[
              const SizedBox(height: 6),
              Divider(color: AppColors.outlineVariant.withValues(alpha: 0.24)),
              const SizedBox(height: 6),
              ...items
                  .where((item) => item.destructive)
                  .map((item) => _AdvancedRouteAction(item: item)),
            ],
          ],
        ),
      ),
    );
  }
}

class _AdvancedRouteAction extends StatelessWidget {
  final ({IconData icon, String label, VoidCallback? onTap, bool destructive})
  item;

  const _AdvancedRouteAction({required this.item});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () {
          Navigator.pop(context);
          item.onTap?.call();
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: item.destructive
                  ? AppColors.red.withValues(alpha: 0.35)
                  : Colors.white10,
            ),
          ),
          child: Row(
            children: [
              Icon(
                item.icon,
                size: 16,
                color: item.destructive ? AppColors.red : Colors.white70,
              ),
              const SizedBox(width: 10),
              Text(
                item.label,
                style: AppText.body(
                  size: 15,
                  weight: FontWeight.w800,
                  color: item.destructive
                      ? AppColors.red
                      : AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;

  const _Pressable({required this.child, this.onTap});

  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.95 : 1.0,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}
