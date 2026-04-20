import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../models/chain_candidate.dart';
import '../theme/colors.dart';
import '../services/route_service.dart';
import '../services/location_service.dart';
import '../screens/route_preview_screen.dart';
import '../widgets/mini_elev_chart.dart';

// ── 탭 스케일 피드백 ─────────────────────────────────────────────────
class _TapScale extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  const _TapScale({required this.child, this.onTap});

  @override
  State<_TapScale> createState() => _TapScaleState();
}

class _TapScaleState extends State<_TapScale> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.93 : 1.0,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

// ── 난이도 색상 헬퍼 (외부 공개) ─────────────────────────────────
Color routeDiffColor(int level) {
  switch (level) {
    case 4:
      return const Color(0xFFEF4444);
    case 3:
      return const Color(0xFFF97316);
    case 2:
      return const Color(0xFFF59E0B);
    case 1:
      return const Color(0xFF22C55E);
    default:
      return const Color(0xFF6B7280);
  }
}

// ══════════════════════════════════════════════════════════════════
// 1. RoutesBottomSheet — 얇은 컨트롤 바 (루트수 + 정렬 + 반경)
// ══════════════════════════════════════════════════════════════════

class RoutesBottomSheet extends StatefulWidget {
  const RoutesBottomSheet({super.key});

  @override
  State<RoutesBottomSheet> createState() => _RoutesBottomSheetState();
}

class _RoutesBottomSheetState extends State<RoutesBottomSheet> {
  int _sortMode = 0; // 0=점수순, 1=거리순

  @override
  Widget build(BuildContext context) {
    return Consumer<RouteService>(
      builder: (context, svc, _) {
        return Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              // 루트 수 or 탐색 중
              if (svc.isLoading)
                Row(
                  children: [
                    SizedBox(
                      width: 10,
                      height: 10,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: AppColors.red,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '탐색 중',
                      style: GoogleFonts.rajdhani(
                        fontSize: 11,
                        color: AppColors.gray,
                      ),
                    ),
                  ],
                )
              else
                RichText(
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: '${svc.routes.length}',
                        style: GoogleFonts.orbitron(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.red,
                        ),
                      ),
                      TextSpan(
                        text: '  ROUTES',
                        style: GoogleFonts.rajdhani(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textSecondary,
                          letterSpacing: 3,
                        ),
                      ),
                    ],
                  ),
                ),
              const Spacer(),
              // 정렬 토글
              _TapScale(
                onTap: () => setState(() => _sortMode = _sortMode == 0 ? 1 : 0),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        child: Icon(
                          _sortMode == 0 ? Icons.star : Icons.near_me,
                          key: ValueKey(_sortMode),
                          size: 10,
                          color: AppColors.red,
                        ),
                      ),
                      const SizedBox(width: 4),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        child: Text(
                          _sortMode == 0 ? '점수순' : '거리순',
                          key: ValueKey(_sortMode),
                          style: GoogleFonts.rajdhani(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textSecondary,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // 반경 선택
              _RadiusSelector(
                current: svc.searchRadiusKm,
                onSelect: (km) {
                  final loc = context.read<LocationService>();
                  svc.changeRadius(km, loc.lat, loc.lng);
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── 반경 선택 ──────────────────────────────────────────────────────
class _RadiusSelector extends StatelessWidget {
  final int current;
  final void Function(int km) onSelect;
  const _RadiusSelector({required this.current, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [30, 50, 100].map((km) {
        final active = current == km;
        return _TapScale(
          onTap: () => onSelect(km),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            margin: const EdgeInsets.only(left: 4),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: BoxDecoration(
              color: active ? AppColors.red : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: active
                    ? AppColors.red
                    : AppColors.gray.withValues(alpha: 0.4),
              ),
            ),
            child: Text(
              '${km}k',
              style: GoogleFonts.rajdhani(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: active ? Colors.white : AppColors.gray,
                letterSpacing: 0.5,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// 2. RouteInfoOverlay — 지도 위 루트 정보 오버레이 카드
//    (routes_screen.dart에서 사용 — Calimoto/Rever 스타일)
// ══════════════════════════════════════════════════════════════════

class RouteInfoOverlay extends StatelessWidget {
  const RouteInfoOverlay({super.key});

  Color _diffColor(int level) {
    switch (level) {
      case 4:
        return const Color(0xFFEF4444);
      case 3:
        return const Color(0xFFF97316);
      case 2:
        return const Color(0xFFF59E0B);
      case 1:
        return const Color(0xFF22C55E);
      default:
        return const Color(0xFF6B7280);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<RouteService>(
      builder: (ctx, svc, _) {
        final route = svc.selectedRoute;
        if (route == null) return const SizedBox.shrink();

        final diffColor = _diffColor(route.difficultyLevel);
        final hasChain = svc.connectingRoutes.isNotEmpty;
        final composite = svc.selectedCompositeRoute;
        final previewComposite = svc.previewCompositeRoute;
        final activeComposite = previewComposite ?? composite;
        final totalChainKm =
            activeComposite?.totalDistanceKm ?? route.distanceKm;

        return Container(
          margin: const EdgeInsets.fromLTRB(10, 0, 10, 6),
          decoration: BoxDecoration(
            color: const Color(0xFF141416),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: diffColor.withValues(alpha: 0.45),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.7),
                blurRadius: 28,
                offset: const Offset(0, 8),
              ),
              BoxShadow(
                color: diffColor.withValues(alpha: 0.1),
                blurRadius: 24,
                spreadRadius: 2,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 상단 난이도 컬러 스트립
                Container(height: 3, color: diffColor),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 11, 10, 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // ── 루트 정보 ──
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: diffColor.withValues(alpha: 0.18),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    route.difficultyLabel,
                                    style: GoogleFonts.rajdhani(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w800,
                                      color: diffColor,
                                      letterSpacing: 1,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    route.name,
                                    style: GoogleFonts.orbitron(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 7),
                            Row(
                              children: [
                                _OvStatChip(
                                  icon: Icons.straighten,
                                  value: route.distanceDisplay,
                                ),
                                const SizedBox(width: 12),
                                _OvStatChip(
                                  icon: Icons.schedule,
                                  value: route.durationDisplay,
                                ),
                                if (route.windingDensityPct > 0) ...[
                                  const SizedBox(width: 12),
                                  _OvStatChip(
                                    icon: Icons.turn_right,
                                    value:
                                        '${route.windingDensityPct.toStringAsFixed(0)}%',
                                    color: diffColor,
                                  ),
                                ],
                              ],
                            ),
                            if (route.primaryReason?.isNotEmpty == true) ...[
                              const SizedBox(height: 8),
                              Text(
                                route.primaryReason!,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.rajdhani(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white70,
                                ),
                              ),
                            ],
                            if (route.cautionNote?.isNotEmpty == true) ...[
                              const SizedBox(height: 4),
                              Text(
                                route.cautionNote!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.rajdhani(
                                  fontSize: 12,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      // ── 버튼 ──
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // PREVIEW 버튼
                          _TapScale(
                            onTap: () => Navigator.push(
                              ctx,
                              MaterialPageRoute(
                                builder: (_) => RoutePreviewScreen(
                                  route: activeComposite == null ? route : null,
                                  compositeRoute: activeComposite,
                                ),
                              ),
                            ),
                            child: Container(
                              width: 76,
                              height: 28,
                              decoration: BoxDecoration(
                                color: AppColors.surface,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: AppColors.red.withValues(alpha: 0.5),
                                ),
                              ),
                              child: Center(
                                child: Text(
                                  'PREVIEW',
                                  style: GoogleFonts.orbitron(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                    letterSpacing: 1,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 5),
                          // GO 버튼
                          _TapScale(
                            onTap: () {
                              svc.requestSprint(
                                route: composite?.toRouteProjection(),
                              );
                              Navigator.of(ctx).pop();
                            },
                            child: Container(
                              width: 76,
                              height: 44,
                              decoration: BoxDecoration(
                                color: AppColors.red,
                                borderRadius: BorderRadius.circular(10),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.red.withValues(
                                      alpha: 0.55,
                                    ),
                                    blurRadius: 16,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Center(
                                child: Text(
                                  'GO',
                                  style: GoogleFonts.orbitron(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.white,
                                    letterSpacing: 3,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          // APPLY 버튼
                          if (hasChain) ...[
                            const SizedBox(height: 5),
                            _TapScale(
                              onTap: composite != null
                                  ? svc.clearCompositeRoute
                                  : null,
                              child: Container(
                                width: 76,
                                height: 28,
                                decoration: BoxDecoration(
                                  color: AppColors.surface,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: AppColors.red.withValues(alpha: 0.5),
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      composite != null
                                          ? Icons.layers_clear
                                          : Icons.link,
                                      size: 9,
                                      color: AppColors.red,
                                    ),
                                    const SizedBox(width: 3),
                                    Text(
                                      composite != null ? 'CLEAR' : 'CHAIN',
                                      style: GoogleFonts.rajdhani(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(width: 6),
                      // 액션 버튼 열 (배제 + 닫기)
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // 닫기
                          _TapScale(
                            onTap: () => svc.deselectRoute(),
                            child: Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.06),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.close,
                                size: 14,
                                color: Colors.white54,
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          // 배제 버튼
                          _TapScale(
                            onTap: () {
                              final route = svc.selectedRoute;
                              if (route != null) svc.excludeRoute(route);
                            },
                            child: Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: AppColors.red.withValues(alpha: 0.12),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: AppColors.red.withValues(alpha: 0.4),
                                ),
                              ),
                              child: const Icon(
                                Icons.block,
                                size: 13,
                                color: AppColors.red,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // ── 미니 고도 프로파일 ──────────────────────────
                Divider(height: 1, color: Colors.white.withValues(alpha: 0.06)),
                MiniElevSection(route: route, lineColor: diffColor),
                if (hasChain) ...[
                  Divider(
                    height: 1,
                    color: Colors.white.withValues(alpha: 0.06),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              '이어질 구간',
                              style: GoogleFonts.rajdhani(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                                letterSpacing: 1.5,
                              ),
                            ),
                            const Spacer(),
                            if (activeComposite != null)
                              Text(
                                '${totalChainKm.toStringAsFixed(1)} km',
                                style: GoogleFonts.orbitron(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.red,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        ...svc.connectingRoutes.map(
                          (candidate) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _ChainCandidateTile(candidate: candidate),
                          ),
                        ),
                        if (svc.connectingRoutes.isEmpty)
                          Text(
                            '이어서 달릴 만한 좋은 구간이 없습니다.',
                            style: GoogleFonts.rajdhani(
                              fontSize: 13,
                              color: AppColors.textSecondary,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ChainCandidateTile extends StatelessWidget {
  final ChainCandidate candidate;
  const _ChainCandidateTile({required this.candidate});

  @override
  Widget build(BuildContext context) {
    final svc = context.read<RouteService>();
    final isPreviewed =
        svc.previewCompositeCandidate?.route.id == candidate.route.id;
    final isCommitted =
        svc.selectedCompositeRoute?.chainedSegments.any(
          (segment) => segment.id == candidate.route.id,
        ) ??
        false;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isCommitted
              ? AppColors.red.withValues(alpha: 0.6)
              : Colors.white12,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  candidate.route.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.orbitron(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'gap ${candidate.gapKm.toStringAsFixed(1)}km · heading ${candidate.headingDelta.toStringAsFixed(0)}° · flow ${candidate.mergedFlowScore.toStringAsFixed(2)}',
                  style: GoogleFonts.rajdhani(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _TapScale(
            onTap: () => svc.previewChainCandidate(candidate),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: isPreviewed
                    ? AppColors.red.withValues(alpha: 0.18)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.red.withValues(alpha: 0.5)),
              ),
              child: Text(
                'PREVIEW',
                style: GoogleFonts.rajdhani(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          _TapScale(
            onTap: () => svc.commitCompositeRoute(candidate),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.red,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                isCommitted ? 'APPLIED' : 'APPLY',
                style: GoogleFonts.rajdhani(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OvStatChip extends StatelessWidget {
  final IconData icon;
  final String value;
  final Color? color;
  const _OvStatChip({required this.icon, required this.value, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.textSecondary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 10, color: c),
        const SizedBox(width: 3),
        Text(
          value,
          style: GoogleFonts.rajdhani(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: c,
          ),
        ),
      ],
    );
  }
}
