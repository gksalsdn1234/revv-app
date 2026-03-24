import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mbx;
import 'package:provider/provider.dart';
import '../theme/colors.dart';
import '../services/location_service.dart';
import '../services/route_service.dart';
import '../services/mapbox_service.dart';
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

  @override
  void initState() {
    super.initState();
    mbx.MapboxOptions.setAccessToken(MapboxService.accessToken);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final loc = context.read<LocationService>();
      _routeSvc = context.read<RouteService>();
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
            child: Consumer<RouteService>(
              builder: (_, svc, __) {
                final selected = svc.selectedRoute;
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
                            )
                          : const SizedBox.shrink(),
                    ),
                  ),
                );
              },
            ),
          ),

          // ── 하단 미니 칩 바 ──
          Positioned(
            key: const ValueKey('bottom-panel'),
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.panel,
                border: Border(
                    top: BorderSide(color: AppColors.divider, width: 1)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.4),
                    blurRadius: 20,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: const _RouteChipBar(),
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

  const _RouteTooltip({
    required this.route,
    required this.connectingCount,
    required this.totalChainKm,
    required this.onGo,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final diffColor = _routeDiffColor(route.difficultyLevel);
    final hasChain = connectingCount > 0;
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
                // 루트 이름 + 닫기
                Row(
                  children: [
                    Expanded(
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
// 미니 칩 바 — 루트 가로 스크롤 + 반경 버튼
// ══════════════════════════════════════════════════════════════════
class _RouteChipBar extends StatelessWidget {
  const _RouteChipBar();

  @override
  Widget build(BuildContext context) {
    return Consumer<RouteService>(
      builder: (_, svc, __) {
        if (svc.isLoading) {
          return SizedBox(
            height: 44,
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.red)),
                  const SizedBox(width: 8),
                  Text('탐색 중...',
                      style: GoogleFonts.rajdhani(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textHint)),
                ],
              ),
            ),
          );
        }
        final routes = svc.routes;
        if (routes.isEmpty) {
          return SizedBox(
            height: 44,
            child: Center(
              child: Text('주변 루트 없음',
                  style: GoogleFonts.rajdhani(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textHint)),
            ),
          );
        }
        final selectedId = svc.selectedRoute?.id;
        return SizedBox(
          height: 44,
          child: Row(
            children: [
              // 루트 수
              Padding(
                padding: const EdgeInsets.only(left: 12, right: 4),
                child: Text(
                  '${routes.length}',
                  style: GoogleFonts.orbitron(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: AppColors.red),
                ),
              ),
              // 가로 스크롤 칩
              Expanded(
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  itemCount: routes.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 6),
                  itemBuilder: (_, i) {
                    final route = routes[i];
                    final isSel = route.id == selectedId;
                    final diffColor =
                        _routeDiffColor(route.difficultyLevel);
                    return GestureDetector(
                      onTap: () => svc.selectRoute(route),
                      child: Center(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: isSel
                                ? diffColor.withValues(alpha: 0.2)
                                : Colors.white.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isSel
                                  ? diffColor.withValues(alpha: 0.7)
                                  : Colors.white12,
                              width: isSel ? 1.5 : 1.0,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: diffColor,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              ConstrainedBox(
                                constraints: const BoxConstraints(
                                    maxWidth: 100),
                                child: Text(
                                  route.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.rajdhani(
                                    fontSize: 11,
                                    fontWeight: isSel
                                        ? FontWeight.w800
                                        : FontWeight.w600,
                                    color: isSel
                                        ? Colors.white
                                        : AppColors.textSecondary,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                route.distanceDisplay,
                                style: GoogleFonts.rajdhani(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textHint,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              // 반경 버튼
              _RadiusBtn(km: 30, active: svc.searchRadiusKm == 30),
              _RadiusBtn(km: 50, active: svc.searchRadiusKm == 50),
              _RadiusBtn(km: 100, active: svc.searchRadiusKm == 100),
              const SizedBox(width: 8),
            ],
          ),
        );
      },
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
