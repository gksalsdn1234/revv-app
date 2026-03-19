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
// 2. RouteInfoOverlay — 지도 위 루트 정보 오버레이 카드 (미니멀)
// ══════════════════════════════════════════════════════════════════

class RouteInfoOverlay extends StatelessWidget {
  const RouteInfoOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<RouteService>(
      builder: (ctx, svc, _) {
        final route = svc.selectedRoute;
        if (route == null) return const SizedBox.shrink();

        final diffColor = routeDiffColor(route.difficultyLevel);
        final hasChain = svc.connectingRoutes.isNotEmpty;
        final totalChainKm = route.distanceKm +
            svc.connectingRoutes.fold<double>(0, (s, r) => s + r.distanceKm);

        return Container(
          margin: const EdgeInsets.fromLTRB(10, 0, 10, 8),
          decoration: BoxDecoration(
            color: AppColors.panel.withOpacity(0.97),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: diffColor.withOpacity(0.4)),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.5),
                  blurRadius: 20,
                  offset: const Offset(0, 4)),
            ],
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 왼쪽 컬러 스트립
                Container(
                  width: 4,
                  decoration: BoxDecoration(
                    color: diffColor,
                    borderRadius: const BorderRadius.horizontal(
                        left: Radius.circular(12)),
                  ),
                ),
                // 본문
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 난이도 배지 + 루트명 한 줄
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 5, vertical: 2),
                              decoration: BoxDecoration(
                                color: diffColor.withOpacity(0.18),
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: Text(
                                route.difficultyLabel,
                                style: GoogleFonts.rajdhani(
                                    fontSize: 8,
                                    fontWeight: FontWeight.w800,
                                    color: diffColor,
                                    letterSpacing: 1),
                              ),
                            ),
                            const SizedBox(width: 7),
                            Expanded(
                              child: Text(
                                route.name,
                                style: GoogleFonts.orbitron(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 5),
                        // 거리 + 시간
                        Row(
                          children: [
                            Icon(Icons.straighten,
                                size: 10, color: AppColors.gray),
                            const SizedBox(width: 3),
                            Text(route.distanceDisplay,
                                style: GoogleFonts.rajdhani(
                                    fontSize: 12, color: AppColors.gray)),
                            const SizedBox(width: 12),
                            Icon(Icons.schedule,
                                size: 10, color: AppColors.gray),
                            const SizedBox(width: 3),
                            Text(route.durationDisplay,
                                style: GoogleFonts.rajdhani(
                                    fontSize: 12, color: AppColors.gray)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                // 버튼 영역
                Padding(
                  padding: const EdgeInsets.fromLTRB(0, 8, 10, 8),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // 달리기 버튼
                      GestureDetector(
                        onTap: () {
                          svc.requestSprint();
                          Navigator.of(context).pop();
                        },
                        child: Container(
                          width: 80,
                          height: 36,
                          decoration: BoxDecoration(
                            color: AppColors.red,
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: [
                              BoxShadow(
                                  color: AppColors.red.withOpacity(0.4),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2)),
                            ],
                          ),
                          child: Center(
                            child: Text(
                              'GO',
                              style: GoogleFonts.orbitron(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                  letterSpacing: 2),
                            ),
                          ),
                        ),
                      ),
                      // CHAIN 버튼 (있을 때만)
                      if (hasChain) ...[
                        const SizedBox(height: 5),
                        GestureDetector(
                          onTap: () {
                            final allNodes = [
                              ...route.nodes,
                              ...svc.connectingRoutes
                                  .expand((r) => r.nodes),
                            ];
                            svc.requestSprint(
                              route: route.copyWith(
                                id: '${route.id}_chain',
                                name:
                                    '${route.name} +${svc.connectingRoutes.length}',
                                nodes: allNodes,
                                distanceKm: totalChainKm,
                              ),
                            );
                            Navigator.of(context).pop();
                          },
                          child: Container(
                            width: 80,
                            height: 28,
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                  color: AppColors.red.withOpacity(0.4)),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.link,
                                    size: 10, color: AppColors.red),
                                const SizedBox(width: 3),
                                Text(
                                  '${totalChainKm.toStringAsFixed(0)}km',
                                  style: GoogleFonts.rajdhani(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                // 닫기 버튼
                GestureDetector(
                  onTap: () => svc.deselectRoute(),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(0, 8, 10, 8),
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: Icon(Icons.close,
                          size: 15, color: AppColors.gray.withOpacity(0.6)),
                    ),
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
