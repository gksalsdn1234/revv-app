import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../theme/colors.dart';
import '../models/revv_route.dart';
import '../services/route_service.dart';
import '../services/location_service.dart';
import '../services/route_brief_service.dart';
import '../services/weather_service.dart';
import '../services/saved_route_service.dart';
import '../widgets/sprint_toggle.dart';

// ── 난이도 색상 헬퍼 ──────────────────────────────────────────
Color _diffColor(int level) {
  switch (level) {
    case 4: return const Color(0xFFEF4444);
    case 3: return const Color(0xFFF97316);
    case 2: return const Color(0xFFF59E0B);
    case 1: return const Color(0xFF22C55E);
    default: return const Color(0xFF6B7280);
  }
}

class RoutesBottomSheet extends StatefulWidget {
  const RoutesBottomSheet({super.key});

  @override
  State<RoutesBottomSheet> createState() => _RoutesBottomSheetState();
}

class _RoutesBottomSheetState extends State<RoutesBottomSheet> {
  final _briefService = RouteBriefService();
  String _briefText = '';
  bool _briefLoading = false;
  String? _lastBriefRouteId;

  String _displayText = '';
  int _charIndex = 0;
  Timer? _typeTimer;

  // 정렬 모드: 0=점수순, 1=거리순
  int _sortMode = 0;

  // 패널 확장 상태 (false=컴팩트 카드뷰, true=상세 펼침)
  bool _expanded = false;

  @override
  void dispose() {
    _typeTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadBriefing(RevvRoute route) async {
    if (_lastBriefRouteId == route.id) return;
    _lastBriefRouteId = route.id;

    setState(() {
      _briefLoading = true;
      _displayText = '';
      _briefText = '';
    });

    final weather = context.read<WeatherService>();
    final text = await _briefService.getBriefing(route: route, weather: weather);

    if (!mounted) return;
    setState(() {
      _briefText = text;
      _briefLoading = false;
    });
    _startTyping(text);
  }

  void _startTyping(String text) {
    _typeTimer?.cancel();
    _charIndex = 0;
    _displayText = '';
    _typeTimer = Timer.periodic(const Duration(milliseconds: 28), (_) {
      if (_charIndex < text.length) {
        if (mounted) setState(() => _displayText += text[_charIndex++]);
      } else {
        _typeTimer?.cancel();
      }
    });
  }

  List<RevvRoute> _sorted(List<RevvRoute> routes) {
    final copy = [...routes];
    if (_sortMode == 1) {
      copy.sort((a, b) => a.distanceFromUser.compareTo(b.distanceFromUser));
    } else {
      copy.sort((a, b) => b.windingScore.compareTo(a.windingScore));
    }
    return copy;
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<RouteService>(
      builder: (context, svc, _) {
        // 루트 선택 시 자동 확장 + 브리핑 로드
        if (svc.selectedRoute != null) {
          if (svc.selectedRoute!.id != _lastBriefRouteId && !_briefLoading) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                _loadBriefing(svc.selectedRoute!);
                setState(() => _expanded = true);
              }
            });
          }
        }

        return Consumer<SavedRouteService>(
          builder: (context, savedSvc, _) {
            return _buildSheet(context, svc, savedSvc);
          },
        );
      },
    );
  }

  Widget _buildSheet(BuildContext context, RouteService svc, SavedRouteService savedSvc) {
    final sorted = _sorted(svc.routes);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── 드래그 핸들 + 헤더 ────────────────────────────────
        GestureDetector(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(
              children: [
                // 드래그 핸들 표시
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(right: 12),
                    decoration: BoxDecoration(
                      color: AppColors.gray.withOpacity(0.4),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                // 루트 수 + 상태
                RichText(
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: svc.isLoading ? '탐색 중' : '${svc.routes.length}',
                        style: GoogleFonts.orbitron(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.red),
                      ),
                      if (!svc.isLoading)
                        TextSpan(
                          text: '  ROUTES',
                          style: GoogleFonts.rajdhani(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textSecondary,
                              letterSpacing: 3),
                        ),
                    ],
                  ),
                ),
                const Spacer(),
                // 정렬 토글
                GestureDetector(
                  onTap: () => setState(() => _sortMode = _sortMode == 0 ? 1 : 0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                          color: AppColors.red,
                        ),
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
                _RadiusSelector(
                  current: svc.searchRadiusKm,
                  onSelect: (km) {
                    final loc = context.read<LocationService>();
                    svc.changeRadius(km, loc.lat, loc.lng);
                  },
                ),
                const SizedBox(width: 8),
                // 확장/축소 아이콘
                Icon(
                  _expanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up,
                  size: 18,
                  color: AppColors.gray,
                ),
              ],
            ),
          ),
        ),

        // ── 루트 카드 리스트 (항상 표시) ─────────────────────
        SizedBox(
          height: 170,
          child: svc.routes.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(svc.isLoading ? Icons.radar : Icons.route,
                          size: 26, color: AppColors.gray.withOpacity(0.4)),
                      const SizedBox(height: 8),
                      Text(
                        svc.isLoading ? '와인딩 루트 분석 중...' : '이 근처엔 루트가 없어요.',
                        style: GoogleFonts.rajdhani(fontSize: 13, color: AppColors.gray),
                      ),
                      if (svc.isLoading)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: SizedBox(
                            width: 100,
                            child: LinearProgressIndicator(
                              color: AppColors.red,
                              backgroundColor: AppColors.surface,
                              minHeight: 2,
                            ),
                          ),
                        ),
                    ],
                  ),
                )
              : ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  itemCount: sorted.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) => _RouteCard(
                    route: sorted[i],
                    isSelected: svc.selectedRoute?.id == sorted[i].id,
                    isSaved: savedSvc.isSaved(sorted[i].id),
                    onTap: () {
                      svc.selectRoute(sorted[i]);
                      setState(() => _expanded = true);
                    },
                    onSave: () => savedSvc.toggle(sorted[i]),
                  ),
                ),
        ),

        // ── 확장 영역 (선택 루트 상세 + CHAIN) ───────────────
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 220),
          firstCurve: Curves.easeOut,
          secondCurve: Curves.easeIn,
          crossFadeState:
              (_expanded && svc.selectedRoute != null)
                  ? CrossFadeState.showFirst
                  : CrossFadeState.showSecond,
          firstChild: svc.selectedRoute == null
              ? const SizedBox.shrink()
              : _SelectedPanel(
                  route: svc.selectedRoute!,
                  savedSvc: savedSvc,
                  briefLoading: _briefLoading,
                  displayText: _displayText,
                  svc: svc,
                ),
          secondChild: const SizedBox(height: 8),
        ),
      ],
    );
  }
}

// ── 선택 루트 상세 패널 (분리) ────────────────────────────────
class _SelectedPanel extends StatelessWidget {
  final RevvRoute route;
  final SavedRouteService savedSvc;
  final bool briefLoading;
  final String displayText;
  final RouteService svc;

  const _SelectedPanel({
    required this.route,
    required this.savedSvc,
    required this.briefLoading,
    required this.displayText,
    required this.svc,
  });

  @override
  Widget build(BuildContext context) {
    final totalChainKm = route.distanceKm +
        svc.connectingRoutes.fold<double>(0, (s, r) => s + r.distanceKm);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 구분선
        Divider(height: 1, color: AppColors.red.withOpacity(0.20), indent: 16, endIndent: 16),

        // ── 선택 루트 컴팩트 정보 바 ──────────────────────────
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          color: AppColors.panel,
          child: Row(
            children: [
              // 루트명
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      route.name,
                      style: GoogleFonts.orbitron(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Colors.white),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        // 거리
                        Icon(Icons.straighten, size: 10, color: AppColors.gray),
                        const SizedBox(width: 3),
                        Text(route.distanceDisplay,
                            style: GoogleFonts.rajdhani(
                                fontSize: 10, color: AppColors.gray)),
                        const SizedBox(width: 8),
                        // 소요시간
                        Icon(Icons.schedule, size: 10, color: AppColors.gray),
                        const SizedBox(width: 3),
                        Text(route.durationDisplay,
                            style: GoogleFonts.rajdhani(
                                fontSize: 10, color: AppColors.gray)),
                        const SizedBox(width: 8),
                        // 난이도 배지
                        Container(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: _diffColor(route.difficultyLevel)
                                .withOpacity(0.15),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                                color: _diffColor(route.difficultyLevel)
                                    .withOpacity(0.5)),
                          ),
                          child: Text(
                            route.difficultyLabel,
                            style: GoogleFonts.rajdhani(
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                color: _diffColor(route.difficultyLevel),
                                letterSpacing: 0.5),
                          ),
                        ),
                        if (route.isLoop) ...[
                          const SizedBox(width: 5),
                          Text('🔄', style: const TextStyle(fontSize: 10)),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              // 저장 버튼
              GestureDetector(
                onTap: () => savedSvc.toggle(route),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: savedSvc.isSaved(route.id)
                        ? AppColors.redDim
                        : AppColors.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: savedSvc.isSaved(route.id)
                          ? AppColors.red
                          : AppColors.divider,
                    ),
                  ),
                  child: Icon(
                    savedSvc.isSaved(route.id)
                        ? Icons.bookmark
                        : Icons.bookmark_border,
                    size: 14,
                    color: savedSvc.isSaved(route.id)
                        ? AppColors.red
                        : AppColors.gray,
                  ),
                ),
              ),
            ],
          ),
        ),

        // ── AI 브리핑 ──────────────────────────────────────────
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
          color: AppColors.bg,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
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
                child: briefLoading
                    ? Row(
                        children: [
                          SizedBox(
                            width: 10, height: 10,
                            child: CircularProgressIndicator(
                                strokeWidth: 1.5, color: AppColors.red),
                          ),
                          const SizedBox(width: 8),
                          Text('루트 분석 중...',
                              style: GoogleFonts.rajdhani(
                                  fontSize: 12, color: AppColors.gray)),
                        ],
                      )
                    : Text(
                        displayText,
                        style: GoogleFonts.rajdhani(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.white70,
                            height: 1.45),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
              ),
            ],
          ),
        ),

        // ── 버튼 영역 ─────────────────────────────────────────
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
          color: AppColors.bg,
          child: Row(
            children: [
              // 이 루트로 달리기
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
              // CHAIN 전체 코스 달리기 버튼 (체인 루트 있을 때)
              if (svc.connectingRoutes.isNotEmpty) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      // 선택 루트 + CHAIN 루트 노드 합산
                      final allNodes = [
                        ...route.nodes,
                        ...svc.connectingRoutes.expand((r) => r.nodes),
                      ];
                      final chainRoute = route.copyWith(
                        id: '${route.id}_chain',
                        name: '${route.name} +${svc.connectingRoutes.length}',
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
                                    fontSize: 9,
                                    color: AppColors.red),
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

        // ── CHAIN 섹션 ──────────────────────────────────────────
        _ChainSection(svc: svc),
      ],
    );
  }
}

// ── 루트 카드 (컴팩트 리디자인) ──────────────────────────────
class _RouteCard extends StatelessWidget {
  final RevvRoute route;
  final bool isSelected;
  final bool isSaved;
  final VoidCallback onTap;
  final VoidCallback onSave;

  const _RouteCard({
    required this.route,
    required this.isSelected,
    required this.isSaved,
    required this.onTap,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    final diffColor = _diffColor(route.difficultyLevel);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 165,
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF1A0A0A) : AppColors.panel,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? AppColors.red.withOpacity(0.8)
                : AppColors.divider,
            width: isSelected ? 1.5 : 1,
          ),
          boxShadow: isSelected
              ? [BoxShadow(color: AppColors.red.withOpacity(0.15), blurRadius: 10)]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── 상단 컬러 밴드 ──────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
              decoration: BoxDecoration(
                color: diffColor.withOpacity(0.12),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(11)),
                border: Border(
                    bottom: BorderSide(color: diffColor.withOpacity(0.25))),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: diffColor.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      route.difficultyLabel,
                      style: GoogleFonts.rajdhani(
                          fontSize: 7,
                          fontWeight: FontWeight.w800,
                          color: diffColor,
                          letterSpacing: 1),
                    ),
                  ),
                  const Spacer(),
                  if (route.isLoop)
                    const Text('🔄', style: TextStyle(fontSize: 9)),
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: onSave,
                    behavior: HitTestBehavior.opaque,
                    child: Icon(
                      isSaved ? Icons.bookmark : Icons.bookmark_border,
                      size: 13,
                      color: isSaved
                          ? AppColors.red
                          : AppColors.gray.withOpacity(0.5),
                    ),
                  ),
                ],
              ),
            ),

            // ── 카드 본문 ────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(9, 7, 9, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 거리 + 소요시간
                  Row(
                    children: [
                      Icon(Icons.straighten,
                          size: 8, color: AppColors.gray),
                      const SizedBox(width: 3),
                      Text(route.distanceDisplay,
                          style: GoogleFonts.rajdhani(
                              fontSize: 9, color: AppColors.gray)),
                      const Spacer(),
                      Icon(Icons.schedule,
                          size: 8, color: AppColors.gray),
                      const SizedBox(width: 3),
                      Text(route.durationDisplay,
                          style: GoogleFonts.rajdhani(
                              fontSize: 9, color: AppColors.gray)),
                    ],
                  ),
                  const SizedBox(height: 4),

                  // 루트명
                  Text(
                    route.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.orbitron(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: isSelected
                            ? Colors.white
                            : AppColors.textPrimary,
                        height: 1.3),
                  ),
                  const SizedBox(height: 6),

                  // 와인딩 밀도 바
                  Row(
                    children: [
                      Text('WINDING',
                          style: GoogleFonts.rajdhani(
                              fontSize: 7,
                              color: AppColors.gray,
                              letterSpacing: 1)),
                      const Spacer(),
                      Text(
                        '${(route.windingDensityPct * 100).round()}%',
                        style: GoogleFonts.rajdhani(
                            fontSize: 7,
                            fontWeight: FontWeight.w700,
                            color: diffColor),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: route.windingDensityPct,
                      minHeight: 3,
                      backgroundColor: AppColors.surface,
                      valueColor: AlwaysStoppedAnimation<Color>(
                          diffColor.withOpacity(0.8)),
                    ),
                  ),
                  const SizedBox(height: 5),

                  // 집에서 거리
                  Row(
                    children: [
                      Icon(Icons.near_me_outlined,
                          size: 8,
                          color: AppColors.gray.withOpacity(0.6)),
                      const SizedBox(width: 3),
                      Text(
                        route.distanceFromUserDisplay,
                        style: GoogleFonts.rajdhani(
                            fontSize: 8,
                            color: AppColors.gray.withOpacity(0.7)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 반경 선택 ─────────────────────────────────────────────────
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
                color:
                    active ? AppColors.red : AppColors.gray.withOpacity(0.4),
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

// ── CHAIN 섹션 ────────────────────────────────────────────────
class _ChainSection extends StatelessWidget {
  final RouteService svc;
  const _ChainSection({required this.svc});

  @override
  Widget build(BuildContext context) {
    if (svc.isLoadingConnecting) {
      return Container(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
        color: AppColors.bg,
        child: Row(
          children: [
            SizedBox(
              width: 10, height: 10,
              child: CircularProgressIndicator(
                  strokeWidth: 1.5, color: AppColors.red),
            ),
            const SizedBox(width: 8),
            Text('끝점 연결 루트 탐색 중...',
                style: GoogleFonts.rajdhani(
                    fontSize: 11, color: AppColors.gray)),
          ],
        ),
      );
    }
    if (svc.connectingRoutes.isEmpty) return const SizedBox(height: 4);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // CHAIN 헤더
        Container(
          color: AppColors.bg,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
          child: Row(
            children: [
              const Icon(Icons.link, color: AppColors.red, size: 12),
              const SizedBox(width: 5),
              Text('CHAIN',
                  style: GoogleFonts.rajdhani(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: AppColors.red,
                      letterSpacing: 3)),
              const SizedBox(width: 5),
              Text('이어지는 루트',
                  style: GoogleFonts.rajdhani(
                      fontSize: 10, color: AppColors.textSecondary)),
            ],
          ),
        ),
        // CHAIN 루트 카드 (가로 스크롤)
        Container(
          color: AppColors.bg,
          child: SizedBox(
            height: 96,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              itemCount: svc.connectingRoutes.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final r = svc.connectingRoutes[i];
                final dc = _diffColor(r.difficultyLevel);
                return GestureDetector(
                  onTap: () => svc.selectRoute(r),
                  child: Container(
                    width: 148,
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: AppColors.panel,
                      borderRadius: BorderRadius.circular(10),
                      border:
                          Border.all(color: AppColors.red.withOpacity(0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding:
                                  const EdgeInsets.symmetric(
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
                            Icon(Icons.turn_right,
                                size: 9, color: AppColors.red),
                            const SizedBox(width: 2),
                            Text(r.distanceDisplay,
                                style: GoogleFonts.rajdhani(
                                    fontSize: 8, color: AppColors.gray)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(r.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.orbitron(
                                fontSize: 8,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                                height: 1.3)),
                        const Spacer(),
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
        ),
      ],
    );
  }
}
