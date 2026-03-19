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
import '../screens/sprint_screen.dart';

// ── 난이도 색상 헬퍼 ──────────────────────────────────────────
Color _diffColor(int level) {
  switch (level) {
    case 4: return const Color(0xFFEF4444); // EXTREME — 빨강
    case 3: return const Color(0xFFF97316); // HARD    — 주황
    case 2: return const Color(0xFFF59E0B); // MEDIUM  — 황색
    case 1: return const Color(0xFF22C55E); // EASY    — 초록
    default: return const Color(0xFF6B7280); // SCENIC  — 회색
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
        if (svc.selectedRoute != null &&
            svc.selectedRoute!.id != _lastBriefRouteId &&
            !_briefLoading) {
          WidgetsBinding.instance.addPostFrameCallback(
              (_) => _loadBriefing(svc.selectedRoute!));
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
        // ── 저장된 루트 섹션 ─────────────────────────────────────
        if (savedSvc.routes.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: Row(
              children: [
                const Icon(Icons.bookmark, color: AppColors.red, size: 13),
                const SizedBox(width: 6),
                Text('저장된 루트',
                    style: GoogleFonts.rajdhani(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary,
                        letterSpacing: 2)),
              ],
            ),
          ),
          SizedBox(
            height: 72,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: savedSvc.routes.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final r = savedSvc.routes[i];
                final isSel = svc.selectedRoute?.id == r.id;
                return GestureDetector(
                  onTap: () => svc.selectRoute(r),
                  child: Container(
                    width: 180,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: isSel ? AppColors.redDim : AppColors.surface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isSel ? AppColors.red : AppColors.divider,
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.bookmark, color: AppColors.red, size: 14),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(r.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.orbitron(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white)),
                              Text(
                                  '${r.distanceKm.toStringAsFixed(0)}km  ·  ${r.difficultyLabel}',
                                  style: GoogleFonts.rajdhani(
                                      fontSize: 10,
                                      color: _diffColor(r.difficultyLevel))),
                            ],
                          ),
                        ),
                        GestureDetector(
                          onTap: () => savedSvc.toggle(r),
                          child: const Icon(Icons.close, color: Colors.white24, size: 14),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          Divider(height: 1, color: AppColors.red.withOpacity(0.15), indent: 16, endIndent: 16),
        ],

        // ── 헤더: 루트 수 + 정렬 ────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              // 루트 수
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
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
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
                        size: 11,
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
        ),

        // ── 루트 카드 리스트 ──────────────────────────────────────
        SizedBox(
          height: 210,
          child: svc.routes.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(svc.isLoading ? Icons.radar : Icons.route,
                          size: 28, color: AppColors.gray.withOpacity(0.4)),
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
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: sorted.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (_, i) => _RouteCard(
                    route: sorted[i],
                    isSelected: svc.selectedRoute?.id == sorted[i].id,
                    isSaved: savedSvc.isSaved(sorted[i].id),
                    onTap: () => svc.selectRoute(sorted[i]),
                    onSave: () => savedSvc.toggle(sorted[i]),
                  ),
                ),
        ),

        // ── 선택 루트 상세 패널 ──────────────────────────────────
        if (svc.selectedRoute != null) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            decoration: BoxDecoration(
              color: AppColors.panel,
              border: Border(
                top: BorderSide(color: AppColors.red.withOpacity(0.25)),
                bottom: BorderSide(color: AppColors.divider),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 루트명 + 저장 버튼
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        svc.selectedRoute!.name,
                        style: GoogleFonts.orbitron(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Colors.white),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    GestureDetector(
                      onTap: () => savedSvc.toggle(svc.selectedRoute!),
                      child: Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: savedSvc.isSaved(svc.selectedRoute!.id)
                              ? AppColors.redDim
                              : AppColors.surface,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: savedSvc.isSaved(svc.selectedRoute!.id)
                                ? AppColors.red
                                : AppColors.divider,
                          ),
                        ),
                        child: Icon(
                          savedSvc.isSaved(svc.selectedRoute!.id)
                              ? Icons.bookmark
                              : Icons.bookmark_border,
                          size: 15,
                          color: savedSvc.isSaved(svc.selectedRoute!.id)
                              ? AppColors.red
                              : AppColors.gray,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // 스탯 4칸
                Row(
                  children: [
                    _StatPill(
                      icon: Icons.straighten,
                      label: svc.selectedRoute!.distanceDisplay,
                      color: AppColors.textSecondary,
                    ),
                    const SizedBox(width: 6),
                    _StatPill(
                      icon: Icons.schedule,
                      label: svc.selectedRoute!.durationDisplay,
                      color: AppColors.textSecondary,
                    ),
                    const SizedBox(width: 6),
                    _StatPill(
                      icon: Icons.near_me,
                      label: svc.selectedRoute!.distanceFromUserDisplay,
                      color: AppColors.textSecondary,
                    ),
                    const SizedBox(width: 6),
                    // 난이도 배지
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _diffColor(svc.selectedRoute!.difficultyLevel).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(
                          color: _diffColor(svc.selectedRoute!.difficultyLevel).withOpacity(0.6),
                          width: 1,
                        ),
                      ),
                      child: Text(
                        svc.selectedRoute!.difficultyLabel,
                        style: GoogleFonts.rajdhani(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: _diffColor(svc.selectedRoute!.difficultyLevel),
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                    if (svc.selectedRoute!.isLoop) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.teal.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(5),
                          border: Border.all(color: Colors.teal.withOpacity(0.5)),
                        ),
                        child: Text('🔄 LOOP',
                            style: GoogleFonts.rajdhani(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: Colors.teal)),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 12),

                // REVV AI 브리핑
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      margin: const EdgeInsets.only(right: 8, top: 2),
                      decoration: BoxDecoration(
                        color: AppColors.red.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(4),
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
                                        fontSize: 13, color: AppColors.gray)),
                              ],
                            )
                          : Text(_displayText,
                              style: GoogleFonts.rajdhani(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                  height: 1.5)),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                RedGlowButton(
                  label: '이 루트로 달리기',
                  filled: true,
                  height: 44,
                  onTap: () {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SprintScreen(selectedRoute: svc.selectedRoute),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),

          // ── CHAIN 섹션 ──────────────────────────────────────────
          _ChainSection(svc: svc),
        ],
        const SizedBox(height: 8),
      ],
    );
  }
}

// ── 스탯 필 ───────────────────────────────────────────────────
class _StatPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _StatPill({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 4),
          Text(label,
              style: GoogleFonts.rajdhani(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: color)),
        ],
      ),
    );
  }
}

// ── 루트 카드 (완전 리디자인) ─────────────────────────────────
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
        width: 190,
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
              ? [BoxShadow(color: AppColors.red.withOpacity(0.15), blurRadius: 12)]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── 상단 컬러 밴드 (난이도) ──────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: diffColor.withOpacity(0.12),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
                border: Border(bottom: BorderSide(color: diffColor.withOpacity(0.25))),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: diffColor.withOpacity(0.2),
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
                  const Spacer(),
                  if (route.isLoop)
                    Text('🔄',
                        style: const TextStyle(fontSize: 10)),
                  const SizedBox(width: 4),
                  // 저장 버튼
                  GestureDetector(
                    onTap: onSave,
                    behavior: HitTestBehavior.opaque,
                    child: Icon(
                      isSaved ? Icons.bookmark : Icons.bookmark_border,
                      size: 14,
                      color: isSaved ? AppColors.red : AppColors.gray.withOpacity(0.5),
                    ),
                  ),
                ],
              ),
            ),

            // ── 카드 본문 ─────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 9, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 거리 + 소요시간
                  Row(
                    children: [
                      Icon(Icons.straighten, size: 9, color: AppColors.gray),
                      const SizedBox(width: 3),
                      Text(route.distanceDisplay,
                          style: GoogleFonts.rajdhani(
                              fontSize: 10, color: AppColors.gray)),
                      const Spacer(),
                      Icon(Icons.schedule, size: 9, color: AppColors.gray),
                      const SizedBox(width: 3),
                      Text(route.durationDisplay,
                          style: GoogleFonts.rajdhani(
                              fontSize: 10, color: AppColors.gray)),
                    ],
                  ),
                  const SizedBox(height: 5),

                  // 루트명
                  Text(
                    route.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.orbitron(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: isSelected ? Colors.white : AppColors.textPrimary,
                        height: 1.3),
                  ),
                  const SizedBox(height: 7),

                  // 와인딩 밀도 스코어바
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text('WINDING',
                              style: GoogleFonts.rajdhani(
                                  fontSize: 8,
                                  color: AppColors.gray,
                                  letterSpacing: 1)),
                          const Spacer(),
                          Text(
                            '${(route.windingDensityPct * 100).round()}%',
                            style: GoogleFonts.rajdhani(
                                fontSize: 8,
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
                          minHeight: 4,
                          backgroundColor: AppColors.surface,
                          valueColor: AlwaysStoppedAnimation<Color>(
                              diffColor.withOpacity(0.8)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 7),

                  // TIGHT / MED + MAX 연속
                  Row(
                    children: [
                      _CurveChip(
                        label: 'TIGHT',
                        value: '${route.tightCurveKm.toStringAsFixed(1)}k',
                        color: AppColors.red,
                      ),
                      const SizedBox(width: 4),
                      _CurveChip(
                        label: 'MED',
                        value: '${route.mediumCurveKm.toStringAsFixed(1)}k',
                        color: Colors.orange,
                      ),
                      const Spacer(),
                      Row(
                        children: [
                          Icon(Icons.linear_scale, size: 9,
                              color: isSelected ? AppColors.red : AppColors.gray),
                          const SizedBox(width: 2),
                          Text(
                            '${route.maxContinuousKm.toStringAsFixed(1)}k',
                            style: GoogleFonts.rajdhani(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: isSelected ? AppColors.red : AppColors.gray),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),

                  // 집에서 거리
                  Row(
                    children: [
                      Icon(Icons.near_me_outlined, size: 9, color: AppColors.gray.withOpacity(0.6)),
                      const SizedBox(width: 3),
                      Text(
                        route.distanceFromUserDisplay,
                        style: GoogleFonts.rajdhani(
                            fontSize: 9, color: AppColors.gray.withOpacity(0.7)),
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
            margin: const EdgeInsets.only(left: 5),
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
            decoration: BoxDecoration(
              color: active ? AppColors.red : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: active ? AppColors.red : AppColors.gray.withOpacity(0.4),
              ),
            ),
            child: Text(
              '${km}km',
              style: GoogleFonts.rajdhani(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: active ? Colors.white : AppColors.gray,
                letterSpacing: 1,
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
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        color: AppColors.bg,
        child: Row(
          children: [
            SizedBox(
              width: 10, height: 10,
              child: CircularProgressIndicator(strokeWidth: 1.5, color: AppColors.red),
            ),
            const SizedBox(width: 8),
            Text('끝점 주변 연결 루트 탐색 중...',
                style: GoogleFonts.rajdhani(fontSize: 11, color: AppColors.gray)),
          ],
        ),
      );
    }
    if (svc.connectingRoutes.isEmpty) return const SizedBox.shrink();

    // 누적 거리 계산
    final totalChainKm = (svc.selectedRoute?.distanceKm ?? 0) +
        svc.connectingRoutes.fold<double>(0, (sum, r) => sum + r.distanceKm);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          color: AppColors.bg,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
          child: Row(
            children: [
              const Icon(Icons.link, color: AppColors.red, size: 12),
              const SizedBox(width: 6),
              Text('CHAIN',
                  style: GoogleFonts.rajdhani(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: AppColors.red,
                      letterSpacing: 3)),
              const SizedBox(width: 6),
              Text('끝점 연결 루트',
                  style: GoogleFonts.rajdhani(
                      fontSize: 10, color: AppColors.textSecondary)),
              const Spacer(),
              // 누적 거리
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: AppColors.red.withOpacity(0.3)),
                ),
                child: Text(
                  '총 ${totalChainKm.toStringAsFixed(0)}km',
                  style: GoogleFonts.rajdhani(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: AppColors.red),
                ),
              ),
            ],
          ),
        ),
        Container(
          color: AppColors.bg,
          child: SizedBox(
            height: 110,
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
                    width: 156,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.panel,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.red.withOpacity(0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
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
                            Icon(Icons.turn_right, size: 10, color: AppColors.red),
                            const SizedBox(width: 2),
                            Text(r.distanceDisplay,
                                style: GoogleFonts.rajdhani(
                                    fontSize: 9, color: AppColors.gray)),
                          ],
                        ),
                        const SizedBox(height: 5),
                        Text(r.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.orbitron(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                                height: 1.3)),
                        const Spacer(),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(
                            value: r.windingDensityPct,
                            minHeight: 3,
                            backgroundColor: AppColors.surface,
                            valueColor: AlwaysStoppedAnimation<Color>(dc.withOpacity(0.7)),
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

// ── 커브 칩 ──────────────────────────────────────────────────
class _CurveChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _CurveChip({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: color.withOpacity(0.35), width: 0.5),
      ),
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(
              text: '$label ',
              style: GoogleFonts.rajdhani(fontSize: 8, color: color, letterSpacing: 0.8),
            ),
            TextSpan(
              text: value,
              style: GoogleFonts.rajdhani(
                  fontSize: 9, fontWeight: FontWeight.w700, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}
