import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
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
  final int connectingCount;
  final double totalChainKm;
  final VoidCallback onGo;
  final VoidCallback onClose;
  final VoidCallback? onTrim;
  final VoidCallback? onReverse;
  final VoidCallback? onFindSimilar;
  final VoidCallback? onChain;
  final VoidCallback? onHeatmap;
  final VoidCallback? onEdit;
  final VoidCallback? onExclude;
  final VoidCallback? onPreview;
  final VoidCallback? onSaved;

  const RoutesSelectionPanel({
    super.key,
    required this.route,
    required this.diffColor,
    required this.connectingCount,
    required this.totalChainKm,
    required this.onGo,
    required this.onClose,
    this.onTrim,
    this.onReverse,
    this.onFindSimilar,
    this.onChain,
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

    return RevvGlassCard(
      key: ValueKey('route-${route.id}'),
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      color: AppColors.bg.withValues(alpha: 0.90),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
                      style: AppText.inter(size: 22, weight: FontWeight.w900),
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
                          size: 18,
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
                      padding: EdgeInsets.all(4),
                      child: Icon(Icons.close, size: 16, color: Colors.white54),
                    ),
                  ),
                ],
              ),
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
              const SizedBox(height: 10),
              Text(
                recommendation.reason,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.rajdhani(
                  fontSize: 15,
                  height: 1.3,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              _DecisionStrip(route: route, connectingCount: connectingCount),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
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
                  if (route.stopSignCount > 0 || route.trafficSignalCount > 0)
                    _MetricChip(
                      icon: Icons.traffic_rounded,
                      label:
                          'STOP ${route.stopSignCount} · SIGNAL ${route.trafficSignalCount}',
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  if (connectingCount > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Text(
                        '+$connectingCount  ${totalChainKm.toStringAsFixed(0)}km',
                        style: GoogleFonts.rajdhani(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  const Spacer(),
                  _Pressable(
                    onTap: onPreview,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceHigh.withValues(alpha: 0.48),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: AppColors.outlineVariant.withValues(
                            alpha: 0.45,
                          ),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.route_rounded,
                            size: 15,
                            color: Colors.white70,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '자세히 보기',
                            style: GoogleFonts.rajdhani(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _Pressable(
                    onTap: onGo,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primaryContainer,
                        borderRadius: BorderRadius.circular(999),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primaryContainer.withValues(
                              alpha: 0.25,
                            ),
                            blurRadius: 18,
                          ),
                        ],
                      ),
                      child: Text(
                        recommendation.primaryCta,
                        style: GoogleFonts.rajdhani(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: AppColors.onPrimary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (onReverse != null ||
                  onFindSimilar != null ||
                  onChain != null ||
                  onHeatmap != null ||
                  onEdit != null ||
                  onTrim != null ||
                  onExclude != null) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () {
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
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.textSecondary,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 4,
                      ),
                    ),
                    child: Text(
                      '고급 옵션',
                      style: GoogleFonts.rajdhani(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _DecisionStrip extends StatelessWidget {
  final RevvRoute route;
  final int connectingCount;

  const _DecisionStrip({required this.route, required this.connectingCount});

  @override
  Widget build(BuildContext context) {
    final decisions = <String>[
      route.primaryReason ?? '지금 달리기 좋은 루트예요.',
      if (route.cautionNote?.isNotEmpty == true) route.cautionNote!,
      if (connectingCount > 0) '뒤에 이어붙일 후보 $connectingCount개가 준비돼 있어요.',
    ];
    final summary = decisions.firstWhere(
      (line) => line.trim().isNotEmpty,
      orElse: () => '지금 고르기 쉬운 루트예요.',
    );
    return SizedBox(
      width: double.infinity,
      child: RevvGlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Text(
          summary,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.rajdhani(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            height: 1.3,
            color: Colors.white70,
          ),
        ),
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

  const _MetricChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: Colors.white54),
          const SizedBox(width: 5),
          Text(
            label,
            style: GoogleFonts.rajdhani(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Colors.white70,
            ),
          ),
        ],
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
                label: '미리 보기',
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
                icon: Icons.link_rounded,
                label: '체인 추천',
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
                icon: Icons.tune_rounded,
                label: '구간 다듬기',
                onTap: onTrim,
                destructive: false,
              ),
              (
                icon: Icons.edit_rounded,
                label: '직접 수정',
                onTap: onEdit,
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
              '고급 옵션',
              style: GoogleFonts.orbitron(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 12),
            ...items.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: InkWell(
                  onTap: () {
                    Navigator.pop(context);
                    item.onTap?.call();
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
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
                          color: item.destructive
                              ? AppColors.red
                              : Colors.white70,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          item.label,
                          style: GoogleFonts.rajdhani(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: item.destructive
                                ? AppColors.red
                                : Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
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
