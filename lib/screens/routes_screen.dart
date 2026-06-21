import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mbx;
import 'package:provider/provider.dart';
import '../theme/colors.dart';
import '../services/location_service.dart';
import '../services/route_service.dart';
import '../services/mapbox_service.dart';
import '../services/saved_route_service.dart';
import '../services/weather_service.dart';
import '../services/run_history_service.dart';
import '../models/revv_route.dart';
import 'route_wizard_screen.dart';

class RoutesScreen extends StatefulWidget {
  const RoutesScreen({super.key});

  @override
  State<RoutesScreen> createState() => _RoutesScreenState();
}

class _RoutesScreenState extends State<RoutesScreen> {
  // ── 지도 ──────────────────────────────────────────────────────
  mbx.MapboxMap? _mapController;
  mbx.PolylineAnnotationManager? _polyManager;
  final List<mbx.PolylineAnnotation> _polylines = [];
  final Map<String, RevvRoute> _annotationToRoute = {};
  bool _styleLoaded = false;
  bool _isDrawing = false;
  String? _lastFlownRouteId;
  RouteService? _routeSvc;

  // ── 정렬 ──────────────────────────────────────────────────────
  int _sortMode = 0; // 0=점수순, 1=거리순

  List<RevvRoute> _sorted(List<RevvRoute> routes) {
    if (_sortMode == 0) return routes; // RouteService가 이미 windingScore 내림차순
    final list = [...routes];
    list.sort((a, b) => a.distanceKm.compareTo(b.distanceKm));
    return list;
  }

  @override
  void initState() {
    super.initState();
    mbx.MapboxOptions.setAccessToken(MapboxService.accessToken);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final loc = context.read<LocationService>();
      _routeSvc = context.read<RouteService>();
      // 날씨 노면 상태 주입
      _routeSvc!.roadCondition = context.read<WeatherService>().roadCondition;
      // 주행 이력 부스트 주입
      final hist = context.read<RunHistoryService>().history;
      final visitMap = <String, int>{};
      for (final s in hist) {
        if (s.routeId != null) visitMap[s.routeId!] = (visitMap[s.routeId!] ?? 0) + 1;
      }
      _routeSvc!.updateVisitHistory(visitMap);
      _routeSvc!.fetchRoutes(loc.lat, loc.lng);
      _routeSvc!.addListener(_onRouteServiceChanged);
    });
  }

  @override
  void dispose() {
    _routeSvc?.removeListener(_onRouteServiceChanged);
    super.dispose();
  }

  // ── 루트 서비스 리스너 ──────────────────────────────────────────
  void _onRouteServiceChanged() {
    if (!mounted || _routeSvc == null) return;
    if (_styleLoaded && !_routeSvc!.isLoading) {
      final sel = _routeSvc!.selectedRoute;
      if (sel != null && sel.id != _lastFlownRouteId) {
        _lastFlownRouteId = sel.id;
        _mapController?.flyTo(
          mbx.CameraOptions(
            center: mbx.Point(
              coordinates: mbx.Position(sel.centerPoint.lng, sel.centerPoint.lat),
            ),
            zoom: 11.5,
            pitch: 0,
          ),
          mbx.MapAnimationOptions(duration: 700),
        );
      }
      _drawRoutes(_routeSvc!.routes, sel);
    }
  }

  // ── 지도 콜백 ──────────────────────────────────────────────────
  void _onMapCreated(mbx.MapboxMap controller) {
    _mapController = controller;
  }

  Future<void> _onStyleLoaded(mbx.StyleLoadedEventData _) async {
    _styleLoaded = true;
    _polyManager =
        await _mapController?.annotations.createPolylineAnnotationManager();
    _polyManager?.addOnPolylineAnnotationClickListener(
      _PolylineClickHandler(_annotationToRoute, (route) {
        context.read<RouteService>().selectRoute(route);
      }),
    );
    await _applyCustomStyle();
    final svc = context.read<RouteService>();
    if (svc.routes.isNotEmpty) {
      await _drawRoutes(svc.routes, svc.selectedRoute);
    }
  }

  Future<void> _applyCustomStyle() async {
    final map = _mapController;
    if (map == null) return;
    for (final entry in {
      'showPointOfInterestLabels': false,
      'showTransitLabels': false,
      'showRoadLabels': true,
      'showPlaceLabels': false,
      'lightPreset': 'night',
    }.entries) {
      try {
        await map.style
            .setStyleImportConfigProperty('basemap', entry.key, entry.value);
      } catch (_) {}
    }
  }

  Future<void> _drawRoutes(List<RevvRoute> routes, RevvRoute? selected) async {
    if (!_styleLoaded || _polyManager == null || _isDrawing) return;
    _isDrawing = true;
    try {
      await _polyManager!.deleteAll();
      _polylines.clear();
      _annotationToRoute.clear();
      final unselected = routes.where((r) => r.id != selected?.id).toList();
      final selectedList = routes.where((r) => r.id == selected?.id).toList();
      for (final route in [...unselected, ...selectedList]) {
        final isSel = route.id == selected?.id;
        final coords =
            route.nodes.map((n) => mbx.Position(n.lng, n.lat)).toList();
        final diffColor = _routeDiffColorInt(route.difficultyLevel);
        final poly = await _polyManager!.create(
          mbx.PolylineAnnotationOptions(
            geometry: mbx.LineString(coordinates: coords),
            lineColor: isSel ? 0xFFFFFFFF : diffColor,
            lineWidth: isSel ? 7.0 : 4.5,
            lineOpacity: isSel ? 1.0 : 0.75,
          ),
        );
        _polylines.add(poly);
        if (poly.id != null) {
          _annotationToRoute[poly.id!] = route;
        }
        if (isSel) {
          final overlay = await _polyManager!.create(
            mbx.PolylineAnnotationOptions(
              geometry: mbx.LineString(coordinates: coords),
              lineColor: diffColor,
              lineWidth: 4.5,
              lineOpacity: 1.0,
            ),
          );
          _polylines.add(overlay);
        }
      }
    } finally {
      _isDrawing = false;
    }
  }

  // ── 화살표 네비게이션 ────────────────────────────────────────────
  void _prevRoute(RouteService svc) {
    if (svc.routes.isEmpty) return;
    final sorted = _sorted(svc.routes);
    final idx = sorted.indexWhere((r) => r.id == svc.selectedRoute?.id);
    final newIdx = ((idx <= 0 ? sorted.length : idx) - 1);
    svc.selectRoute(sorted[newIdx]);
  }

  void _nextRoute(RouteService svc) {
    if (svc.routes.isEmpty) return;
    final sorted = _sorted(svc.routes);
    final idx = sorted.indexWhere((r) => r.id == svc.selectedRoute?.id);
    final newIdx = (idx + 1) % sorted.length;
    svc.selectRoute(sorted[newIdx]);
  }

  // ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final loc = context.read<LocationService>();

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          // 지도 — 전체 화면
          ClipRect(
            child: SizedBox.expand(
              child: RepaintBoundary(
                child: mbx.MapWidget(
                  styleUri: MapboxService.cruiseStyle,
                  cameraOptions: mbx.CameraOptions(
                    center: mbx.Point(
                        coordinates: mbx.Position(loc.lng, loc.lat)),
                    zoom: 10.0,
                    pitch: 0,
                  ),
                  androidHostingMode:
                      mbx.AndroidPlatformViewHostingMode.TLHC_VD,
                  textureView: true,
                  onMapCreated: _onMapCreated,
                  onStyleLoadedListener: _onStyleLoaded,
                ),
              ),
            ),
          ),

          // ── 상단 헤더 ──
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            left: 14,
            right: 14,
            child: Row(
              children: [
                // 뒤로가기
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.62),
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.1)),
                    ),
                    child: const Icon(Icons.arrow_back_ios_new_rounded,
                        size: 15, color: Colors.white),
                  ),
                ),
                const SizedBox(width: 10),
                // 타이틀
                Expanded(
                  child: Container(
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.08)),
                    ),
                    child: Center(
                      child: Text(
                        'ROUTES',
                        style: GoogleFonts.orbitron(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          letterSpacing: 3,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                // 루트 wizard
                GestureDetector(
                  onTap: () => RouteWizardSheet.show(context),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.62),
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: AppColors.red.withValues(alpha: 0.5)),
                    ),
                    child: const Icon(Icons.add_road_rounded,
                        size: 18, color: AppColors.red),
                  ),
                ),
              ],
            ),
          ),

          // 로딩 오버레이
          Consumer<RouteService>(
            builder: (context, svc, _) {
              if (!svc.isLoading) return const SizedBox.shrink();
              return Positioned.fill(
                child: Container(
                  color: Colors.black.withOpacity(0.5),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'REVV가 주변 루트를 분석하고 있어요',
                        style: GoogleFonts.rajdhani(
                            fontSize: 14, color: Colors.white),
                      ),
                      const SizedBox(height: 16),
                      const SizedBox(
                        width: 200,
                        child: LinearProgressIndicator(
                          color: AppColors.red,
                          backgroundColor: AppColors.panel,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),

          // 에러 메시지
          Consumer<RouteService>(
            builder: (context, svc, _) {
              if (svc.errorMessage == null) return const SizedBox.shrink();
              return Positioned(
                top: MediaQuery.of(context).padding.top + 62,
                left: 16,
                right: 16,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.panel,
                    border: Border.all(
                        color: AppColors.red.withOpacity(0.5)),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(svc.errorMessage!,
                      style: GoogleFonts.rajdhani(
                          fontSize: 13, color: Colors.white)),
                ),
              );
            },
          ),

          // ── 말풍선 툴팁 (루트 선택 시) ──
          Positioned(
            key: const ValueKey('route-tooltip'),
            top: MediaQuery.of(context).padding.top + 70,
            left: 20,
            right: 20,
            child: Consumer2<RouteService, RunHistoryService>(
              builder: (_, svc, histSvc, __) {
                final selected = svc.selectedRoute;
                final sorted = _sorted(svc.routes);
                final isTopPick = sorted.isNotEmpty && selected?.id == sorted.first.id;
                final isNew = selected != null &&
                    histSvc.history.every((s) => s.routeId != selected.id);
                return AnimatedSlide(
                  offset: selected != null
                      ? Offset.zero
                      : const Offset(0, -0.3),
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                  child: AnimatedOpacity(
                    opacity: selected != null ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 160),
                    child: IgnorePointer(
                      ignoring: selected == null,
                      child: selected != null
                          ? _RouteTooltip(
                              route: selected,
                              connectingCount:
                                  svc.connectingRoutes.length,
                              totalChainKm: selected.distanceKm +
                                  svc.connectingRoutes.fold<double>(
                                      0, (s, r) => s + r.distanceKm),
                              onGo: () => svc.requestSprint(),
                              onClose: () => svc.deselectRoute(),
                              isTopPick: isTopPick,
                              isNew: isNew,
                            )
                          : const SizedBox.shrink(),
                    ),
                  ),
                );
              },
            ),
          ),

          // ── 왼쪽 이전 화살표 ──
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: Consumer<RouteService>(
              builder: (_, svc, __) => _ArrowBtn(
                icon: Icons.chevron_left_rounded,
                onTap: svc.routes.isEmpty ? null : () => _prevRoute(svc),
              ),
            ),
          ),

          // ── 오른쪽 다음 화살표 ──
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            child: Consumer<RouteService>(
              builder: (_, svc, __) => _ArrowBtn(
                icon: Icons.chevron_right_rounded,
                onTap: svc.routes.isEmpty ? null : () => _nextRoute(svc),
              ),
            ),
          ),

          // ── 하단 인디케이터 (N/M + 반경) ──
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 16,
            left: 0,
            right: 0,
            child: Consumer<RouteService>(
              builder: (_, svc, __) {
                if (svc.isLoading) {
                  return Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppColors.red),
                        ),
                        const SizedBox(width: 8),
                        Text('탐색 중...',
                            style: GoogleFonts.rajdhani(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textHint)),
                      ],
                    ),
                  );
                }
                final sorted = _sorted(svc.routes);
                final total = sorted.length;
                final idx = total == 0
                    ? 0
                    : sorted.indexWhere((r) => r.id == svc.selectedRoute?.id) + 1;
                return Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.1)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // N / M 카운터
                        Text(
                          total == 0 ? '—' : '$idx / $total',
                          style: GoogleFonts.orbitron(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            letterSpacing: 1,
                          ),
                        ),
                        Container(
                          width: 1,
                          height: 14,
                          margin: const EdgeInsets.symmetric(horizontal: 10),
                          color: Colors.white24,
                        ),
                        // 정렬 토글
                        GestureDetector(
                          onTap: () => setState(() => _sortMode = _sortMode == 0 ? 1 : 0),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _sortMode == 0 ? Icons.star_rounded : Icons.near_me_rounded,
                                size: 11,
                                color: AppColors.red,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                _sortMode == 0 ? '점수순' : '거리순',
                                style: GoogleFonts.rajdhani(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white70,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          width: 1,
                          height: 14,
                          margin: const EdgeInsets.symmetric(horizontal: 10),
                          color: Colors.white24,
                        ),
                        // 반경 버튼
                        _RadiusBtn(km: 30, active: svc.searchRadiusKm == 30),
                        _RadiusBtn(km: 50, active: svc.searchRadiusKm == 50),
                        _RadiusBtn(km: 100, active: svc.searchRadiusKm == 100),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── 난이도 색상 (int ARGB) ─────────────────────────────────────────
int _routeDiffColorInt(int level) {
  switch (level) {
    case 4:
      return 0xFFEF4444; // red (EXTREME)
    case 3:
      return 0xFFF97316; // orange (HARD)
    case 2:
      return 0xFFF59E0B; // amber (MEDIUM)
    case 1:
      return 0xFF22C55E; // green (EASY)
    default:
      return 0xFF60A5FA; // blue (SCENIC)
  }
}

Color _routeDiffColor(int level) => Color(_routeDiffColorInt(level));

// ══════════════════════════════════════════════════════════════════
// 말풍선 툴팁 — 루트 선택 시 지도 위에 표시
// ══════════════════════════════════════════════════════════════════
class _RouteTooltip extends StatelessWidget {
  final RevvRoute route;
  final int connectingCount;
  final double totalChainKm;
  final VoidCallback onGo;
  final VoidCallback onClose;
  final bool isTopPick;
  final bool isNew;

  const _RouteTooltip({
    required this.route,
    required this.connectingCount,
    required this.totalChainKm,
    required this.onGo,
    required this.onClose,
    this.isTopPick = false,
    this.isNew = false,
  });

  @override
  Widget build(BuildContext context) {
    final diffColor = _routeDiffColor(route.difficultyLevel);
    final hasChain = connectingCount > 0;
    final savedSvc = context.watch<SavedRouteService>();
    final isSaved = savedSvc.isSaved(route.id);
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xF0141416),
        borderRadius: BorderRadius.circular(14),
        border:
            Border.all(color: diffColor.withValues(alpha: 0.5), width: 1.5),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.6),
              blurRadius: 20,
              offset: const Offset(0, 6)),
          BoxShadow(
              color: diffColor.withValues(alpha: 0.15),
              blurRadius: 16,
              spreadRadius: 1),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 난이도 컬러 밴드
          Container(
            height: 3,
            decoration: BoxDecoration(
              color: diffColor,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(13)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 10, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 루트 이름 + 배지 + 닫기
                Row(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              route.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.rajdhani(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          if (isTopPick) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.red.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: AppColors.red.withValues(alpha: 0.5)),
                              ),
                              child: Text(
                                'PICK',
                                style: GoogleFonts.orbitron(
                                  fontSize: 7,
                                  fontWeight: FontWeight.w900,
                                  color: AppColors.red,
                                  letterSpacing: 1,
                                ),
                              ),
                            ),
                          ] else if (isNew) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.greenAccent.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.4)),
                              ),
                              child: Text(
                                'NEW',
                                style: GoogleFonts.orbitron(
                                  fontSize: 7,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.greenAccent,
                                  letterSpacing: 1,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    // ♥ 북마크 버튼
                    GestureDetector(
                      onTap: () => context.read<SavedRouteService>().toggle(route),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          isSaved ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                          size: 18,
                          color: isSaved ? AppColors.red : Colors.white38,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: onClose,
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(Icons.close,
                            size: 16, color: Colors.white54),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                // 스탯 칩 + 난이도 배지
                Row(
                  children: [
                    _TooltipChip(
                        icon: Icons.straighten,
                        label: route.distanceDisplay),
                    const SizedBox(width: 6),
                    _TooltipChip(
                        icon: Icons.timer_outlined,
                        label: route.durationDisplay),
                    const SizedBox(width: 6),
                    if (route.isLoop) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.blueAccent.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text('LOOP',
                            style: GoogleFonts.orbitron(
                                fontSize: 8,
                                fontWeight: FontWeight.w700,
                                color: Colors.blueAccent)),
                      ),
                      const SizedBox(width: 6),
                    ],
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: diffColor.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                            color: diffColor.withValues(alpha: 0.4)),
                      ),
                      child: Text(
                        route.difficultyLabel,
                        style: GoogleFonts.orbitron(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: diffColor,
                            letterSpacing: 1),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // CHAIN + GO
                Row(
                  children: [
                    if (hasChain)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: Text(
                          '+$connectingCount  ${totalChainKm.toStringAsFixed(0)}km',
                          style: GoogleFonts.rajdhani(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textSecondary),
                        ),
                      ),
                    const Spacer(),
                    GestureDetector(
                      onTap: onGo,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 7),
                        decoration: BoxDecoration(
                          color: AppColors.red,
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [
                            BoxShadow(
                                color:
                                    AppColors.red.withValues(alpha: 0.35),
                                blurRadius: 10)
                          ],
                        ),
                        child: Text(
                          'GO',
                          style: GoogleFonts.orbitron(
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            letterSpacing: 3,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TooltipChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _TooltipChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: AppColors.textHint),
          const SizedBox(width: 3),
          Text(label,
              style: GoogleFonts.rajdhani(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// 사이드 화살표 버튼 — 게임 맵 선택 스타일
// ══════════════════════════════════════════════════════════════════
class _ArrowBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const _ArrowBtn({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.translucent,
      child: SizedBox(
        width: 52,
        height: double.infinity,
        child: Center(
          child: AnimatedOpacity(
            opacity: enabled ? 1.0 : 0.25,
            duration: const Duration(milliseconds: 200),
            child: Container(
              width: 40,
              height: 56,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(12),
                border:
                    Border.all(color: Colors.white.withValues(alpha: 0.15)),
              ),
              child: Icon(icon, size: 28, color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}

class _RadiusBtn extends StatelessWidget {
  final int km;
  final bool active;
  const _RadiusBtn({required this.km, required this.active});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        final loc = context.read<LocationService>();
        context.read<RouteService>().changeRadius(km, loc.lat, loc.lng);
      },
      child: Container(
        margin: const EdgeInsets.only(left: 3),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: active
              ? AppColors.red.withValues(alpha: 0.9)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
              color: active ? AppColors.red : Colors.white24, width: 1),
        ),
        child: Text(
          '${km}k',
          style: GoogleFonts.rajdhani(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: active ? Colors.white : AppColors.textHint,
          ),
        ),
      ),
    );
  }
}

// ── 폴리라인 탭 → 루트 선택 리스너 ────────────────────────────────
class _PolylineClickHandler
    extends mbx.OnPolylineAnnotationClickListener {
  final Map<String, RevvRoute> annotationToRoute;
  final void Function(RevvRoute) onSelect;

  _PolylineClickHandler(this.annotationToRoute, this.onSelect);

  @override
  bool onPolylineAnnotationClick(mbx.PolylineAnnotation annotation) {
    final route = annotationToRoute[annotation.id];
    if (route != null) {
      onSelect(route);
      return true;
    }
    return false;
  }
}
