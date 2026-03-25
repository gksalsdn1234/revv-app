import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mbx;
import 'package:provider/provider.dart';
import '../theme/colors.dart';
import '../services/location_service.dart';
import '../services/route_service.dart';
import '../services/mapbox_service.dart';
import '../services/saved_route_service.dart';
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

  // ── A. 출발점 핀 모드 ─────────────────────────────────────────
  bool _pinStartMode = false;
  LatLng? _customStart;

  // ── D. 구간 트리밍 ────────────────────────────────────────────
  bool _trimMode = false;
  double _trimStart = 0.0;
  double _trimEnd = 1.0;
  RevvRoute? _trimBase;

  // ── I. 히트맵 오버레이 ────────────────────────────────────────
  bool _heatmapMode = false;

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

        // I. 히트맵 모드: 선택 루트는 세그먼트별 컬러로 그림
        if (isSel && _heatmapMode) {
          await _drawHeatmapSegments(route);
          continue;
        }

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

  // ── A. 출발점 핀 설정 ────────────────────────────────────────────
  Future<void> _onPinTap(TapUpDetails details) async {
    if (!_pinStartMode) return;
    final map = _mapController;
    if (map == null) return;
    final point = await map.coordinateForPixel(
      mbx.ScreenCoordinate(
        x: details.localPosition.dx,
        y: details.localPosition.dy,
      ),
    );
    if (!mounted) return;
    final lat = point.coordinates.lat.toDouble();
    final lng = point.coordinates.lng.toDouble();
    setState(() {
      _customStart = LatLng(lat, lng);
      _pinStartMode = false;
      _lastFlownRouteId = null;
    });
    _routeSvc?.fetchRoutes(lat, lng);
  }

  void _resetCustomStart() {
    final loc = context.read<LocationService>();
    setState(() {
      _customStart = null;
      _lastFlownRouteId = null;
    });
    _routeSvc?.fetchRoutes(loc.lat, loc.lng);
  }

  // ── D. 구간 트리밍 ────────────────────────────────────────────────
  void _startTrim(RevvRoute route) {
    setState(() {
      _trimMode = true;
      _trimBase = route;
      _trimStart = 0.0;
      _trimEnd = 1.0;
    });
  }

  void _cancelTrim() {
    setState(() {
      _trimMode = false;
      _trimBase = null;
    });
    // 원본 루트로 지도 복원
    final svc = _routeSvc;
    if (svc != null) _drawRoutes(svc.routes, svc.selectedRoute);
  }

  void _applyTrim() {
    final base = _trimBase;
    if (base == null) return;
    final nodes = base.nodes;
    final s = (_trimStart * nodes.length).round().clamp(0, nodes.length - 2);
    final e = (_trimEnd * nodes.length).round().clamp(s + 2, nodes.length);
    final trimmed = nodes.sublist(s, e);
    double dist = 0;
    for (int i = 0; i < trimmed.length - 1; i++) {
      dist += RevvRoute.haversineKm(trimmed[i], trimmed[i + 1]);
    }
    final newRoute = base.copyWith(
      id: '${base.id}_trim',
      nodes: trimmed,
      distanceKm: dist,
    );
    _routeSvc?.selectRoute(newRoute);
    setState(() {
      _trimMode = false;
      _trimBase = null;
    });
  }

  void _onTrimChanged(double start, double end) {
    setState(() {
      _trimStart = start;
      _trimEnd = end;
    });
    // 실시간 미리보기
    final base = _trimBase;
    if (base == null || _routeSvc == null) return;
    final nodes = base.nodes;
    final s = (start * nodes.length).round().clamp(0, nodes.length - 2);
    final e = (end * nodes.length).round().clamp(s + 2, nodes.length);
    _drawTrimPreview(base, s, e);
  }

  Future<void> _drawTrimPreview(RevvRoute base, int s, int e) async {
    if (!_styleLoaded || _polyManager == null || _isDrawing) return;
    _isDrawing = true;
    try {
      await _polyManager!.deleteAll();
      _polylines.clear();
      _annotationToRoute.clear();
      final svc = _routeSvc;
      if (svc == null) return;
      // 비선택 루트
      for (final route in svc.routes.where((r) => r.id != base.id)) {
        final coords = route.nodes.map((n) => mbx.Position(n.lng, n.lat)).toList();
        await _polyManager!.create(mbx.PolylineAnnotationOptions(
          geometry: mbx.LineString(coordinates: coords),
          lineColor: _routeDiffColorInt(route.difficultyLevel),
          lineWidth: 4.5, lineOpacity: 0.4,
        ));
      }
      final allCoords = base.nodes.map((n) => mbx.Position(n.lng, n.lat)).toList();
      // 잘려나갈 앞 부분 (회색)
      if (s > 1) {
        await _polyManager!.create(mbx.PolylineAnnotationOptions(
          geometry: mbx.LineString(coordinates: allCoords.sublist(0, s + 1)),
          lineColor: 0xFF444444, lineWidth: 4.0, lineOpacity: 0.5,
        ));
      }
      // 살아남는 구간 (흰색+컬러)
      final kept = allCoords.sublist(s, e);
      final diffColor = _routeDiffColorInt(base.difficultyLevel);
      await _polyManager!.create(mbx.PolylineAnnotationOptions(
        geometry: mbx.LineString(coordinates: kept),
        lineColor: 0xFFFFFFFF, lineWidth: 7.0, lineOpacity: 1.0,
      ));
      await _polyManager!.create(mbx.PolylineAnnotationOptions(
        geometry: mbx.LineString(coordinates: kept),
        lineColor: diffColor, lineWidth: 4.5, lineOpacity: 1.0,
      ));
      // 잘려나갈 뒷 부분 (회색)
      if (e < allCoords.length - 1) {
        await _polyManager!.create(mbx.PolylineAnnotationOptions(
          geometry: mbx.LineString(coordinates: allCoords.sublist(e)),
          lineColor: 0xFF444444, lineWidth: 4.0, lineOpacity: 0.5,
        ));
      }
    } finally {
      _isDrawing = false;
    }
  }

  // ── E. 루트 방향 반전 ────────────────────────────────────────────
  void _reverseRoute(RevvRoute route) {
    final reversed = route.copyWith(
      id: '${route.id}_rev',
      nodes: route.nodes.reversed.toList(),
    );
    _routeSvc?.selectRoute(reversed);
  }

  // ── F. 유사 루트 탐색 ────────────────────────────────────────────
  void _findSimilar(RevvRoute route) {
    setState(() {
      _customStart = route.centerPoint;
      _lastFlownRouteId = null;
    });
    _routeSvc?.fetchRoutes(route.centerPoint.lat, route.centerPoint.lng);
  }

  // ── G. 수동 체인 연결 ────────────────────────────────────────────
  void _showChainPicker(RevvRoute selected) {
    final svc = _routeSvc;
    if (svc == null) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _ChainPickerSheet(
        selected: selected,
        allRoutes: svc.routes.where((r) => r.id != selected.id).toList(),
        chained: svc.connectingRoutes,
        onAdd: svc.addManualChain,
        onRemove: svc.removeFromChain,
      ),
    );
  }

  // ── I. 히트맵 오버레이 ────────────────────────────────────────────
  void _toggleHeatmap(RevvRoute route) {
    setState(() => _heatmapMode = !_heatmapMode);
    _drawRoutes(_routeSvc!.routes, route);
  }

  Future<void> _drawHeatmapSegments(RevvRoute route) async {
    final nodes = route.nodes;
    if (nodes.length < 3 || _polyManager == null) return;

    // bearing diff rate 계산
    double bear(LatLng a, LatLng b) {
      final lat1 = a.lat * math.pi / 180;
      final lat2 = b.lat * math.pi / 180;
      final dLng = (b.lng - a.lng) * math.pi / 180;
      final y = math.sin(dLng) * math.cos(lat2);
      final x = math.cos(lat1) * math.sin(lat2) -
          math.sin(lat1) * math.cos(lat2) * math.cos(dLng);
      return math.atan2(y, x) * 180 / math.pi;
    }

    double diff(double b1, double b2) {
      double d = (b2 - b1).abs();
      return d > 180 ? 360 - d : d;
    }

    int _color(double rate) {
      if (rate < 30) return 0xFF3B82F6;
      if (rate < 100) return 0xFF22C55E;
      if (rate < 200) return 0xFFF59E0B;
      if (rate < 350) return 0xFFF97316;
      return 0xFFEF4444;
    }

    // 연속 같은 색 구간 묶어서 그리기
    int? curColor;
    var curGroup = <mbx.Position>[];

    Future<void> flush() async {
      if (curGroup.length >= 2 && curColor != null) {
        await _polyManager!.create(mbx.PolylineAnnotationOptions(
          geometry: mbx.LineString(coordinates: curGroup),
          lineColor: curColor!,
          lineWidth: 5.5,
          lineOpacity: 1.0,
        ));
      }
    }

    for (int i = 0; i < nodes.length - 2; i++) {
      final d = RevvRoute.haversineKm(nodes[i], nodes[i + 1]);
      final rate = d > 0.0001
          ? diff(bear(nodes[i], nodes[i + 1]),
                  bear(nodes[i + 1], nodes[i + 2])) /
              d
          : 0.0;
      final c = _color(rate);
      if (curColor == null) {
        curColor = c;
        curGroup = [mbx.Position(nodes[i].lng, nodes[i].lat)];
      } else if (c != curColor) {
        curGroup.add(mbx.Position(nodes[i].lng, nodes[i].lat));
        await flush();
        curColor = c;
        curGroup = [mbx.Position(nodes[i].lng, nodes[i].lat)];
      }
      curGroup.add(mbx.Position(nodes[i + 1].lng, nodes[i + 1].lat));
    }
    await flush();
  }

  // ── 화살표 네비게이션 ────────────────────────────────────────────
  void _prevRoute(RouteService svc) {
    if (svc.routes.isEmpty) return;
    final idx = svc.routes.indexWhere((r) => r.id == svc.selectedRoute?.id);
    final newIdx = ((idx <= 0 ? svc.routes.length : idx) - 1);
    svc.selectRoute(svc.routes[newIdx]);
  }

  void _nextRoute(RouteService svc) {
    if (svc.routes.isEmpty) return;
    final idx = svc.routes.indexWhere((r) => r.id == svc.selectedRoute?.id);
    final newIdx = (idx + 1) % svc.routes.length;
    svc.selectRoute(svc.routes[newIdx]);
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
                // 타이틀 / 커스텀 출발지 상태
                Expanded(
                  child: GestureDetector(
                    onTap: _customStart != null ? _resetCustomStart : null,
                    child: Container(
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: _customStart != null
                              ? AppColors.red.withValues(alpha: 0.6)
                              : Colors.white.withValues(alpha: 0.08),
                        ),
                      ),
                      child: Center(
                        child: _customStart != null
                            ? Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.place_rounded,
                                      size: 13, color: AppColors.red),
                                  const SizedBox(width: 5),
                                  Text(
                                    '커스텀 출발지  ✕',
                                    style: GoogleFonts.rajdhani(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.red,
                                      letterSpacing: 1,
                                    ),
                                  ),
                                ],
                              )
                            : Text(
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
                ),
                const SizedBox(width: 10),
                // 📍 출발점 핀 버튼
                GestureDetector(
                  onTap: () => setState(() => _pinStartMode = !_pinStartMode),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: _pinStartMode
                          ? AppColors.red.withValues(alpha: 0.9)
                          : Colors.black.withValues(alpha: 0.62),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _pinStartMode
                            ? AppColors.red
                            : Colors.white.withValues(alpha: 0.1),
                      ),
                    ),
                    child: const Icon(Icons.place_rounded,
                        size: 18, color: Colors.white),
                  ),
                ),
                const SizedBox(width: 8),
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

          // ── A. 핀 모드 오버레이 ──
          if (_pinStartMode)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: _onPinTap,
                child: Stack(
                  children: [
                    Container(color: Colors.black.withValues(alpha: 0.15)),
                    Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.place_rounded,
                              size: 40, color: AppColors.red),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.75),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: AppColors.red.withValues(alpha: 0.5)),
                            ),
                            child: Text(
                              '탭하여 출발지 설정',
                              style: GoogleFonts.rajdhani(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                  letterSpacing: 1),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // ── D. 구간 트리밍 패널 ──
          if (_trimMode && _trimBase != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _TrimPanel(
                route: _trimBase!,
                trimStart: _trimStart,
                trimEnd: _trimEnd,
                onChanged: _onTrimChanged,
                onApply: _applyTrim,
                onCancel: _cancelTrim,
              ),
            ),

          // 로딩 오버레이 — IgnorePointer로 버튼 터치 통과
          Consumer<RouteService>(
            builder: (context, svc, _) {
              if (!svc.isLoading) return const SizedBox.shrink();
              return Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    color: Colors.black.withOpacity(0.45),
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
                              connectingCount: svc.connectingRoutes.length,
                              totalChainKm: selected.distanceKm +
                                  svc.connectingRoutes.fold<double>(
                                      0, (s, r) => s + r.distanceKm),
                              onGo: () => svc.requestSprint(),
                              onClose: () => svc.deselectRoute(),
                              onTrim: () => _startTrim(selected),
                              onReverse: () => _reverseRoute(selected),
                              onFindSimilar: () => _findSimilar(selected),
                              onChain: () => _showChainPicker(selected),
                              onHeatmap: () => _toggleHeatmap(selected),
                              heatmapActive: _heatmapMode,
                            )
                          : const SizedBox.shrink(),
                    ),
                  ),
                );
              },
            ),
          ),

          // ── 왼쪽 이전 화살표 — 하단 인디케이터와 같은 높이 ──
          Positioned(
            left: 6,
            bottom: MediaQuery.of(context).padding.bottom + 10,
            child: Consumer<RouteService>(
              builder: (_, svc, __) => _ArrowBtn(
                icon: Icons.chevron_left_rounded,
                onTap: svc.routes.isEmpty ? null : () => _prevRoute(svc),
              ),
            ),
          ),

          // ── 오른쪽 다음 화살표 — 하단 인디케이터와 같은 높이 ──
          Positioned(
            right: 6,
            bottom: MediaQuery.of(context).padding.bottom + 10,
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
                final total = svc.routes.length;
                final idx = total == 0
                    ? 0
                    : svc.routes
                            .indexWhere((r) => r.id == svc.selectedRoute?.id) +
                        1;
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
                          margin:
                              const EdgeInsets.symmetric(horizontal: 10),
                          color: Colors.white24,
                        ),
                        // 반경 버튼
                        _RadiusBtn(km: 30, active: svc.searchRadiusKm == 30),
                        _RadiusBtn(km: 50, active: svc.searchRadiusKm == 50),
                        _RadiusBtn(km: 100, active: svc.searchRadiusKm == 100),
                        const SizedBox(width: 6),
                        GestureDetector(
                          onTap: () => context.read<RouteService>().shuffleRoutes(),
                          child: Icon(Icons.shuffle_rounded,
                              size: 16, color: AppColors.textHint),
                        ),
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
  final VoidCallback onTrim;
  final VoidCallback onReverse;
  final VoidCallback onFindSimilar;
  final VoidCallback onChain;
  final VoidCallback onHeatmap;
  final bool heatmapActive;

  const _RouteTooltip({
    required this.route,
    required this.connectingCount,
    required this.totalChainKm,
    required this.onGo,
    required this.onClose,
    required this.onTrim,
    required this.onReverse,
    required this.onFindSimilar,
    required this.onChain,
    required this.onHeatmap,
    required this.heatmapActive,
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
                // E/F/G/I 액션 버튼 행
                Row(
                  children: [
                    _IconAction(
                      icon: Icons.swap_horiz_rounded,
                      label: '반전',
                      onTap: onReverse,
                    ),
                    const SizedBox(width: 6),
                    _IconAction(
                      icon: Icons.travel_explore_rounded,
                      label: '유사탐색',
                      onTap: onFindSimilar,
                    ),
                    const SizedBox(width: 6),
                    _IconAction(
                      icon: Icons.add_link_rounded,
                      label: '체인',
                      onTap: onChain,
                    ),
                    const SizedBox(width: 6),
                    _IconAction(
                      icon: Icons.thermostat_rounded,
                      label: '히트맵',
                      onTap: onHeatmap,
                      active: heatmapActive,
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
                    // ✂️ 구간 트리밍 버튼
                    GestureDetector(
                      onTap: onTrim,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 7),
                        margin: const EdgeInsets.only(right: 6),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: const Icon(Icons.content_cut_rounded,
                            size: 14, color: Colors.white60),
                      ),
                    ),
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

// ── E/F/G/I 액션 아이콘 버튼 ─────────────────────────────────────
class _IconAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;
  const _IconAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: active
              ? AppColors.red.withValues(alpha: 0.2)
              : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: active
                ? AppColors.red.withValues(alpha: 0.6)
                : Colors.white12,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12,
                color: active ? AppColors.red : Colors.white54),
            const SizedBox(width: 4),
            Text(label,
                style: GoogleFonts.rajdhani(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: active ? AppColors.red : Colors.white54,
                    letterSpacing: 0.5)),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// G. 수동 체인 연결 피커 시트
// ══════════════════════════════════════════════════════════════════
class _ChainPickerSheet extends StatelessWidget {
  final RevvRoute selected;
  final List<RevvRoute> allRoutes;
  final List<RevvRoute> chained;
  final void Function(RevvRoute) onAdd;
  final void Function(String) onRemove;

  const _ChainPickerSheet({
    required this.selected,
    required this.allRoutes,
    required this.chained,
    required this.onAdd,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.55),
      decoration: const BoxDecoration(
        color: Color(0xFF141416),
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 핸들
          Container(
            width: 36, height: 4,
            margin: const EdgeInsets.only(top: 10, bottom: 12),
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Row(
              children: [
                const Icon(Icons.add_link_rounded,
                    size: 14, color: AppColors.red),
                const SizedBox(width: 8),
                Text('체인 연결',
                    style: GoogleFonts.rajdhani(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        letterSpacing: 1)),
                const Spacer(),
                if (chained.isNotEmpty)
                  Text(
                    '총 ${(selected.distanceKm + chained.fold<double>(0, (s, r) => s + r.distanceKm)).toStringAsFixed(0)}km',
                    style: GoogleFonts.orbitron(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.red),
                  ),
              ],
            ),
          ),
          const Divider(color: AppColors.divider, height: 1),
          Flexible(
            child: ListView.builder(
              padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).padding.bottom + 8),
              itemCount: allRoutes.length,
              itemBuilder: (_, i) {
                final r = allRoutes[i];
                final isChained = chained.any((c) => c.id == r.id);
                final diffColor = routeDiffColor(r.difficultyLevel);
                return ListTile(
                  dense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                  leading: Container(
                    width: 4, height: 36,
                    decoration: BoxDecoration(
                      color: diffColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  title: Text(r.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.rajdhani(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.white)),
                  subtitle: Text(
                      '${r.distanceDisplay}  ·  ${r.difficultyLabel}',
                      style: GoogleFonts.rajdhani(
                          fontSize: 10, color: AppColors.textHint)),
                  trailing: GestureDetector(
                    onTap: () =>
                        isChained ? onRemove(r.id) : onAdd(r),
                    child: Container(
                      width: 32, height: 32,
                      decoration: BoxDecoration(
                        color: isChained
                            ? AppColors.red.withValues(alpha: 0.15)
                            : AppColors.surface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isChained
                              ? AppColors.red.withValues(alpha: 0.5)
                              : AppColors.divider,
                        ),
                      ),
                      child: Icon(
                        isChained ? Icons.remove_rounded : Icons.add_rounded,
                        size: 16,
                        color: isChained ? AppColors.red : Colors.white54,
                      ),
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
// D. 구간 트리밍 패널
// ══════════════════════════════════════════════════════════════════
class _TrimPanel extends StatelessWidget {
  final RevvRoute route;
  final double trimStart;
  final double trimEnd;
  final void Function(double start, double end) onChanged;
  final VoidCallback onApply;
  final VoidCallback onCancel;

  const _TrimPanel({
    required this.route,
    required this.trimStart,
    required this.trimEnd,
    required this.onChanged,
    required this.onApply,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final kept = (trimEnd - trimStart) * route.distanceKm;
    return Container(
      padding: EdgeInsets.fromLTRB(
          16, 14, 16, MediaQuery.of(context).padding.bottom + 14),
      decoration: BoxDecoration(
        color: const Color(0xF2141416),
        border: const Border(
            top: BorderSide(color: AppColors.divider)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 헤더
          Row(
            children: [
              const Icon(Icons.content_cut_rounded,
                  size: 14, color: AppColors.red),
              const SizedBox(width: 8),
              Text(
                '구간 조절',
                style: GoogleFonts.rajdhani(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: 1),
              ),
              const Spacer(),
              Text(
                '${kept.toStringAsFixed(1)} km',
                style: GoogleFonts.orbitron(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.red),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // 슬라이더
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: AppColors.red,
              inactiveTrackColor: AppColors.surface,
              thumbColor: Colors.white,
              overlayColor: AppColors.red.withValues(alpha: 0.2),
              trackHeight: 3,
              thumbShape:
                  const RoundSliderThumbShape(enabledThumbRadius: 8),
            ),
            child: Column(
              children: [
                // 시작 슬라이더
                Row(
                  children: [
                    Text('시작',
                        style: GoogleFonts.rajdhani(
                            fontSize: 10,
                            color: AppColors.textHint,
                            letterSpacing: 1)),
                    Expanded(
                      child: Slider(
                        value: trimStart,
                        min: 0.0,
                        max: (trimEnd - 0.1).clamp(0.0, 0.9),
                        onChanged: (v) => onChanged(v, trimEnd),
                      ),
                    ),
                    Text(
                      '${(trimStart * route.distanceKm).toStringAsFixed(1)}km',
                      style: GoogleFonts.rajdhani(
                          fontSize: 10, color: AppColors.textSecondary),
                    ),
                  ],
                ),
                // 끝 슬라이더
                Row(
                  children: [
                    Text('  끝',
                        style: GoogleFonts.rajdhani(
                            fontSize: 10,
                            color: AppColors.textHint,
                            letterSpacing: 1)),
                    Expanded(
                      child: Slider(
                        value: trimEnd,
                        min: (trimStart + 0.1).clamp(0.1, 1.0),
                        max: 1.0,
                        onChanged: (v) => onChanged(trimStart, v),
                      ),
                    ),
                    Text(
                      '${(trimEnd * route.distanceKm).toStringAsFixed(1)}km',
                      style: GoogleFonts.rajdhani(
                          fontSize: 10, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          // 적용/취소 버튼
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: onCancel,
                  child: Container(
                    height: 38,
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.divider),
                    ),
                    child: Center(
                      child: Text('취소',
                          style: GoogleFonts.rajdhani(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textSecondary)),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: GestureDetector(
                  onTap: onApply,
                  child: Container(
                    height: 38,
                    decoration: BoxDecoration(
                      color: AppColors.red,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                            color: AppColors.red.withValues(alpha: 0.4),
                            blurRadius: 8)
                      ],
                    ),
                    child: Center(
                      child: Text('이 구간으로 설정',
                          style: GoogleFonts.rajdhani(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              letterSpacing: 0.5)),
                    ),
                  ),
                ),
              ),
            ],
          ),
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
      child: AnimatedOpacity(
        opacity: enabled ? 1.0 : 0.25,
        duration: const Duration(milliseconds: 200),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
          ),
          child: Icon(icon, size: 26, color: Colors.white),
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
          km == 30 ? 'NEAR' : km == 50 ? 'MID' : 'FAR',
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
