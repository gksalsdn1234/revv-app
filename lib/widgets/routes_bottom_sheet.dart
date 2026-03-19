import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../theme/colors.dart';
import '../models/revv_route.dart';
import '../services/route_service.dart';
import '../services/location_service.dart';
import '../services/saved_route_service.dart';
import '../services/route_brief_service.dart';
import '../services/weather_service.dart';
import '../widgets/sprint_toggle.dart';

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
// ══════════════════════════════════════════════════════════════════

class RouteInfoOverlay extends StatefulWidget {
  const RouteInfoOverlay({super.key});

  @override
  State<RouteInfoOverlay> createState() => _RouteInfoOverlayState();
}

class _RouteInfoOverlayState extends State<RouteInfoOverlay> {
  final _briefSvc = RouteBriefService();
  String _displayText = '';
  bool _briefLoading = false;
  String? _lastBriefId;
  int _charIndex = 0;
  Timer? _typeTimer;

  @override
  void dispose() {
    _typeTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadBriefing(RevvRoute route) async {
    if (_lastBriefId == route.id) return;
    _lastBriefId = route.id;
    setState(() {
      _briefLoading = true;
      _displayText = '';
    });
    final weather = context.read<WeatherService>();
    final text = await _briefSvc.getBriefing(route: route, weather: weather);
    if (!mounted) return;
    setState(() => _briefLoading = false);
    _startTyping(text);
  }

  void _startTyping(String text) {
    _typeTimer?.cancel();
    _charIndex = 0;
    _displayText = '';
    _typeTimer = Timer.periodic(const Duration(milliseconds: 25), (_) {
      if (_charIndex < text.length) {
        if (mounted) setState(() => _displayText += text[_charIndex++]);
      } else {
        _typeTimer?.cancel();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<RouteService, SavedRouteService>(
      builder: (ctx, svc, savedSvc, _) {
        final route = svc.selectedRoute;
        if (route == null) return const SizedBox.shrink();

        // 선택 루트 변경 시 브리핑 자동 로드
        if (route.id != _lastBriefId && !_briefLoading) {
          WidgetsBinding.instance.addPostFrameCallback(
              (_) { if (mounted) _loadBriefing(route); });
        }

        final diffColor = routeDiffColor(route.difficultyLevel);
        final totalChainKm = route.distanceKm +
            svc.connectingRoutes.fold<double>(0, (s, r) => s + r.distanceKm);

        return Container(
          margin: const EdgeInsets.fromLTRB(10, 0, 10, 8),
          decoration: BoxDecoration(
            color: AppColors.panel.withOpacity(0.97),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: diffColor.withOpacity(0.35)),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.45),
                  blurRadius: 24,
                  offset: const Offset(0, 6)),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── 헤더: 컬러 스트립 + 루트명 + 북마크 + 닫기 ───────
              ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(13)),
                child: Container(
                  decoration: BoxDecoration(
                    color: diffColor.withOpacity(0.1),
                    border: Border(
                        bottom: BorderSide(color: diffColor.withOpacity(0.2))),
                  ),
                  child: IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // 왼쪽 컬러 스트립
                        Container(width: 5, color: diffColor),
                        const SizedBox(width: 10),
                        // 난이도 배지
                        Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: diffColor.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(4),
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
                        ),
                        const SizedBox(width: 8),
                        // 루트명
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
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
                        ),
                        if (route.isLoop)
                          const Center(
                            child: Padding(
                              padding: EdgeInsets.only(right: 4),
                              child: Text('🔄',
                                  style: TextStyle(fontSize: 11)),
                            ),
                          ),
                        // 북마크
                        GestureDetector(
                          onTap: () => savedSvc.toggle(route),
                          child: Padding(
                            padding: const EdgeInsets.all(10),
                            child: Icon(
                              savedSvc.isSaved(route.id)
                                  ? Icons.bookmark
                                  : Icons.bookmark_border,
                              size: 16,
                              color: savedSvc.isSaved(route.id)
                                  ? AppColors.red
                                  : AppColors.gray,
                            ),
                          ),
                        ),
                        // 닫기
                        GestureDetector(
                          onTap: () => svc.deselectRoute(),
                          child: Padding(
                            padding: const EdgeInsets.all(10),
                            child: Icon(Icons.close,
                                size: 16, color: AppColors.gray),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // ── 스탯 바: 거리 · 시간 · 와인딩 ─────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 9, 14, 4),
                child: Row(
                  children: [
                    Icon(Icons.straighten, size: 10, color: AppColors.gray),
                    const SizedBox(width: 3),
                    Text(route.distanceDisplay,
                        style: GoogleFonts.rajdhani(
                            fontSize: 12, color: AppColors.gray)),
                    const SizedBox(width: 10),
                    Icon(Icons.schedule, size: 10, color: AppColors.gray),
                    const SizedBox(width: 3),
                    Text(route.durationDisplay,
                        style: GoogleFonts.rajdhani(
                            fontSize: 12, color: AppColors.gray)),
                    const Spacer(),
                    Text('WINDING',
                        style: GoogleFonts.rajdhani(
                            fontSize: 8,
                            color: AppColors.gray,
                            letterSpacing: 1)),
                    const SizedBox(width: 7),
                    SizedBox(
                      width: 56,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: route.windingDensityPct,
                          minHeight: 4,
                          backgroundColor: AppColors.surface,
                          valueColor: AlwaysStoppedAnimation<Color>(
                              diffColor.withOpacity(0.85)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${(route.windingDensityPct * 100).round()}%',
                      style: GoogleFonts.rajdhani(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: diffColor),
                    ),
                  ],
                ),
              ),

              // ── AI 브리핑 ──────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 2, 14, 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 2),
                      margin: const EdgeInsets.only(right: 7, top: 1),
                      decoration: BoxDecoration(
                        color: AppColors.red.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text('AI',
                          style: GoogleFonts.orbitron(
                              fontSize: 8,
                              fontWeight: FontWeight.w700,
                              color: AppColors.red,
                              letterSpacing: 1)),
                    ),
                    Expanded(
                      child: _briefLoading
                          ? Row(children: [
                              SizedBox(
                                width: 10,
                                height: 10,
                                child: CircularProgressIndicator(
                                    strokeWidth: 1.5, color: AppColors.red),
                              ),
                              const SizedBox(width: 8),
                              Text('분석 중...',
                                  style: GoogleFonts.rajdhani(
                                      fontSize: 11, color: AppColors.gray)),
                            ])
                          : Text(
                              _displayText,
                              style: GoogleFonts.rajdhani(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white70,
                                  height: 1.45),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                    ),
                  ],
                ),
              ),

              // ── 버튼 영역 ──────────────────────────────────────────
              Divider(
                  height: 1,
                  color: AppColors.divider,
                  indent: 14,
                  endIndent: 14),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: RedGlowButton(
                        label: '달리기',
                        filled: true,
                        height: 42,
                        onTap: () {
                          svc.requestSprint();
                          Navigator.of(context).pop();
                        },
                      ),
                    ),
                    if (svc.connectingRoutes.isNotEmpty) ...[
                      const SizedBox(width: 10),
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            final allNodes = [
                              ...route.nodes,
                              ...svc.connectingRoutes
                                  .expand((r) => r.nodes),
                            ];
                            final chainRoute = route.copyWith(
                              id: '${route.id}_chain',
                              name:
                                  '${route.name} +${svc.connectingRoutes.length}',
                              nodes: allNodes,
                              distanceKm: totalChainKm,
                            );
                            svc.requestSprint(route: chainRoute);
                            Navigator.of(context).pop();
                          },
                          child: Container(
                            height: 42,
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color: AppColors.red.withOpacity(0.5)),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.link,
                                    size: 13, color: AppColors.red),
                                const SizedBox(width: 5),
                                Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '전체 코스',
                                      style: GoogleFonts.rajdhani(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800,
                                          color: Colors.white,
                                          letterSpacing: 0.5),
                                    ),
                                    Text(
                                      '${totalChainKm.toStringAsFixed(0)}km',
                                      style: GoogleFonts.rajdhani(
                                          fontSize: 9, color: AppColors.red),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // ── CHAIN 로딩 ─────────────────────────────────────────
              if (svc.isLoadingConnecting)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                  child: Row(children: [
                    SizedBox(
                      width: 10,
                      height: 10,
                      child: CircularProgressIndicator(
                          strokeWidth: 1.5, color: AppColors.red),
                    ),
                    const SizedBox(width: 8),
                    Text('끝점 연결 탐색 중...',
                        style: GoogleFonts.rajdhani(
                            fontSize: 11, color: AppColors.gray)),
                  ]),
                ),

              // ── CHAIN 루트 카드 ─────────────────────────────────────
              if (!svc.isLoadingConnecting &&
                  svc.connectingRoutes.isNotEmpty) ...[
                Divider(
                    height: 1,
                    color: AppColors.divider,
                    indent: 14,
                    endIndent: 14),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 8, 0, 6),
                  child: Row(children: [
                    const Icon(Icons.link, color: AppColors.red, size: 11),
                    const SizedBox(width: 4),
                    Text('CHAIN',
                        style: GoogleFonts.rajdhani(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: AppColors.red,
                            letterSpacing: 3)),
                    const SizedBox(width: 6),
                    Text('이어지는 루트',
                        style: GoogleFonts.rajdhani(
                            fontSize: 10, color: AppColors.textSecondary)),
                  ]),
                ),
                SizedBox(
                  height: 82,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                    itemCount: svc.connectingRoutes.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (_, i) {
                      final r = svc.connectingRoutes[i];
                      final dc = routeDiffColor(r.difficultyLevel);
                      return GestureDetector(
                        onTap: () => svc.selectRoute(r),
                        child: Container(
                          width: 140,
                          padding: const EdgeInsets.all(9),
                          decoration: BoxDecoration(
                            color: AppColors.bg,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color: AppColors.red.withOpacity(0.3)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 4, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: dc.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                  child: Text(r.difficultyLabel,
                                      style: GoogleFonts.rajdhani(
                                          fontSize: 7,
                                          fontWeight: FontWeight.w800,
                                          color: dc,
                                          letterSpacing: 0.5)),
                                ),
                                const Spacer(),
                                Text(r.distanceDisplay,
                                    style: GoogleFonts.rajdhani(
                                        fontSize: 8, color: AppColors.gray)),
                              ]),
                              const SizedBox(height: 4),
                              Expanded(
                                child: Text(r.name,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.orbitron(
                                        fontSize: 8,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white,
                                        height: 1.3)),
                              ),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(2),
                                child: LinearProgressIndicator(
                                  value: r.windingDensityPct,
                                  minHeight: 2,
                                  backgroundColor: AppColors.surface,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                      dc.withOpacity(0.7)),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
