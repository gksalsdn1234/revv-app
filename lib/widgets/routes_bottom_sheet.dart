import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../theme/colors.dart';
import '../models/revv_route.dart';
import '../services/route_service.dart';
import '../services/location_service.dart';

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
                          strokeWidth: 1.5, color: AppColors.red),
                    ),
                    const SizedBox(width: 8),
                    Text('탐색 중',
                        style: GoogleFonts.rajdhani(
                            fontSize: 11, color: AppColors.gray)),
                  ],
                )
              else
                RichText(
                  text: TextSpan(children: [
                    TextSpan(
                      text: '${svc.routes.length}',
                      style: GoogleFonts.orbitron(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.red),
                    ),
                    TextSpan(
                      text: '  ROUTES',
                      style: GoogleFonts.rajdhani(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textSecondary,
                          letterSpacing: 3),
                    ),
                  ]),
                ),
              const Spacer(),
              // 정렬 토글
              GestureDetector(
                onTap: () =>
                    setState(() => _sortMode = _sortMode == 0 ? 1 : 0),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                          _sortMode == 0 ? Icons.star : Icons.near_me,
                          size: 10,
                          color: AppColors.red),
                      const SizedBox(width: 4),
                      Text(
                        _sortMode == 0 ? '점수순' : '거리순',
                        style: GoogleFonts.rajdhani(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textSecondary,
                            letterSpacing: 1),
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
        return GestureDetector(
          onTap: () => onSelect(km),
          child: Container(
            margin: const EdgeInsets.only(left: 4),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: BoxDecoration(
              color: active ? AppColors.red : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: active ? AppColors.red : AppColors.gray.withOpacity(0.4),
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
      case 4: return const Color(0xFFEF4444);
      case 3: return const Color(0xFFF97316);
      case 2: return const Color(0xFFF59E0B);
      case 1: return const Color(0xFF22C55E);
      default: return const Color(0xFF6B7280);
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
        final totalChainKm = route.distanceKm +
            svc.connectingRoutes.fold<double>(0, (s, r) => s + r.distanceKm);

        return Container(
          margin: const EdgeInsets.fromLTRB(10, 0, 10, 6),
          decoration: BoxDecoration(
            color: const Color(0xFF141416),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: diffColor.withValues(alpha: 0.45), width: 1.5),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.7),
                  blurRadius: 28,
                  offset: const Offset(0, 8)),
              BoxShadow(
                  color: diffColor.withValues(alpha: 0.1),
                  blurRadius: 24,
                  spreadRadius: 2),
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
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: diffColor.withValues(alpha: 0.18),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    route.difficultyLabel,
                                    style: GoogleFonts.rajdhani(
                                      fontSize: 9, fontWeight: FontWeight.w800,
                                      color: diffColor, letterSpacing: 1,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    route.name,
                                    style: GoogleFonts.orbitron(
                                      fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white,
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
                                _OvStatChip(icon: Icons.straighten, value: route.distanceDisplay),
                                const SizedBox(width: 12),
                                _OvStatChip(icon: Icons.schedule, value: route.durationDisplay),
                                if (route.windingDensityPct > 0) ...[
                                  const SizedBox(width: 12),
                                  _OvStatChip(
                                    icon: Icons.turn_right,
                                    value: '${route.windingDensityPct.toStringAsFixed(0)}%',
                                    color: diffColor,
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      // ── 버튼 ──
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // GO 버튼
                          GestureDetector(
                            onTap: () {
                              svc.requestSprint();
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
                                    color: AppColors.red.withValues(alpha: 0.55),
                                    blurRadius: 16,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Center(
                                child: Text(
                                  'GO',
                                  style: GoogleFonts.orbitron(
                                    fontSize: 16, fontWeight: FontWeight.w900,
                                    color: Colors.white, letterSpacing: 3,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          // CHAIN 버튼
                          if (hasChain) ...[
                            const SizedBox(height: 5),
                            GestureDetector(
                              onTap: () {
                                final allNodes = [
                                  ...route.nodes,
                                  ...svc.connectingRoutes.expand((r) => r.nodes),
                                ];
                                svc.requestSprint(
                                  route: route.copyWith(
                                    id: '${route.id}_chain',
                                    name: '${route.name} +${svc.connectingRoutes.length}',
                                    nodes: allNodes,
                                    distanceKm: totalChainKm,
                                  ),
                                );
                                Navigator.of(ctx).pop();
                              },
                              child: Container(
                                width: 76,
                                height: 28,
                                decoration: BoxDecoration(
                                  color: AppColors.surface,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: AppColors.red.withValues(alpha: 0.5)),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.link, size: 9, color: AppColors.red),
                                    const SizedBox(width: 3),
                                    Text(
                                      '${totalChainKm.toStringAsFixed(0)}km',
                                      style: GoogleFonts.rajdhani(
                                        fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white,
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
                      // 닫기
                      GestureDetector(
                        onTap: () => svc.deselectRoute(),
                        child: Container(
                          width: 28, height: 28,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.06),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.close, size: 14, color: Colors.white54),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
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
          style: GoogleFonts.rajdhani(fontSize: 12, fontWeight: FontWeight.w600, color: c),
        ),
      ],
    );
  }
}
