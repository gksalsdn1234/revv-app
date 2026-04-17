import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mbx;
import 'package:provider/provider.dart';
import '../theme/colors.dart';
import '../services/location_service.dart';
import '../services/route_service.dart';
import '../services/mapbox_service.dart';
import '../services/home_location_service.dart';
import '../services/loop_route_service.dart';
import '../services/route_brief_service.dart';
import '../services/weather_service.dart';
import '../services/revv_ai_service.dart';
import '../services/jarvis_service.dart';
import '../services/settings_service.dart';
import '../models/revv_route.dart';
import '../models/loop_route.dart';
import 'route_wizard_screen.dart';
import 'route_edit_screen.dart';
import 'route_detail_screen.dart';
import '../widgets/routes_selection_panel.dart';
import '../widgets/routes_screen_support.dart';

class RoutesScreen extends StatefulWidget {
  const RoutesScreen({super.key});

  @override
  State<RoutesScreen> createState() => _RoutesScreenState();
}

class _RoutesScreenState extends State<RoutesScreen> {
  // ── 지도 ──────────────────────────────────────────────────────
  mbx.MapboxMap? _mapController;
  mbx.PolylineAnnotationManager? _polyManager;
  mbx.Cancelable? _polyTapEvents;
  final List<mbx.PolylineAnnotation> _polylines = [];
  final Map<String, RevvRoute> _annotationToRoute = {};
  bool _styleLoaded = false;
  bool _isDrawing = false;
  String? _lastFlownRouteId;
  RouteService? _routeSvc;
  LocationService? _locationSvc;
  bool _initialRouteFetchRequested = false;
  bool _initialMapCenteredOnLiveLocation = false;

  // ── D. 구간 트리밍 ────────────────────────────────────────────
  bool _trimMode = false;
  double _trimStart = 0.0;
  double _trimEnd = 1.0;
  RevvRoute? _trimBase;

  // ── I. 히트맵 오버레이 ────────────────────────────────────────
  bool _heatmapMode = false;

  // ── LOOP 탭 ───────────────────────────────────────────────────
  int _activeTab = 0; // 0=ROUTES, 1=LOOP, 2=CIRCUIT
  final LoopRouteService _loopSvc = LoopRouteService();
  bool _loopFromHome = false;
  int _loopIdx = 0;
  String? _loopBrief;
  bool _loopBriefLoading = false;

  // ── AI 루트 브리핑 (화면 진입 후 최초 1회만) ──────────────────
  final RouteBriefService _briefSvc = RouteBriefService();
  String? _currentBrief;
  bool _briefLoading = false;
  bool _briefShownOnce = false; // 한 번 표시되면 이후 재트리거 없음

  @override
  void initState() {
    super.initState();
    mbx.MapboxOptions.setAccessToken(MapboxService.accessToken);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _locationSvc = context.read<LocationService>();
      _routeSvc = context.read<RouteService>();
      _routeSvc!.addListener(_onRouteServiceChanged);
      _locationSvc!.addListener(_onLocationChanged);
      _primeInitialRoutes();
    });
  }

  @override
  void dispose() {
    _routeSvc?.removeListener(_onRouteServiceChanged);
    _locationSvc?.removeListener(_onLocationChanged);
    _loopSvc.removeListener(_onLoopServiceChanged);
    _polyTapEvents?.cancel();
    _loopSvc.dispose();
    super.dispose();
  }

  Future<void> _primeInitialRoutes() async {
    final loc = _locationSvc;
    final svc = _routeSvc;
    if (!mounted || loc == null || svc == null || _initialRouteFetchRequested) {
      return;
    }

    await loc.requestPermission();
    if (loc.hasPermission) {
      await loc.startTracking();
    }
    final anchor = await loc.ensureLiveLocation(
      timeout: const Duration(seconds: 6),
    );
    if (!mounted || anchor == null || _initialRouteFetchRequested) return;

    _initialRouteFetchRequested = true;
    svc.resetCache();
    _centerMapOnLocation(anchor, animated: _styleLoaded);
    await svc.fetchRoutes(anchor.lat, anchor.lng);
  }

  void _onLocationChanged() {
    if (!mounted) return;
    final anchor = _locationSvc?.liveLatLng;
    if (anchor == null) return;

    if (!_initialRouteFetchRequested) {
      _primeInitialRoutes();
      return;
    }

    if (!_initialMapCenteredOnLiveLocation &&
        (_routeSvc?.routes.isEmpty ?? true)) {
      _centerMapOnLocation(anchor, animated: _styleLoaded);
    }
  }

  void _centerMapOnLocation(LatLng anchor, {required bool animated}) {
    _initialMapCenteredOnLiveLocation = true;
    if (_mapController == null) return;
    final camera = mbx.CameraOptions(
      center: mbx.Point(coordinates: mbx.Position(anchor.lng, anchor.lat)),
      zoom: 10.0,
      pitch: 0,
    );
    if (animated) {
      _mapController!.flyTo(camera, mbx.MapAnimationOptions(duration: 600));
    } else {
      _mapController!.setCamera(camera);
    }
  }

  void _onLoopServiceChanged() {
    if (!mounted) return;
    setState(() {});
    if (_activeTab == 1 && _styleLoaded && _loopSvc.loops.isNotEmpty) {
      _loopIdx = _loopIdx.clamp(0, _loopSvc.loops.length - 1);
      _drawLoopRoutes(_loopSvc.loops[_loopIdx]);
      // 루프 빌드 완료 → AI 설명 fetch
      if (!_loopSvc.isBuilding) _fetchLoopBrief(_loopSvc.loops[_loopIdx]);
    }
  }

  Future<void> _fetchLoopBrief(LoopRoute loop) async {
    if (!mounted) return;
    setState(() {
      _loopBrief = null;
      _loopBriefLoading = true;
    });
    final weather = context.read<WeatherService>();
    final brief = await RevvAiService().describeLoop(
      loop,
      weatherDesc: weather.weatherDesc,
      roadCondition: weather.roadCondition,
      tempCelsius: weather.tempCelsius,
    );
    if (mounted) {
      setState(() {
        _loopBrief = brief;
        _loopBriefLoading = false;
      });
    }
  }

  Future<void> _fetchBrief(RevvRoute route) async {
    if (_briefShownOnce) return; // 이미 1회 표시됨 → 재트리거 없음
    if (mounted) {
      setState(() {
        _briefLoading = true;
        _currentBrief = null;
      });
    }
    final weather = context.read<WeatherService>();
    final brief = await _briefSvc.getBriefing(route: route, weather: weather);
    if (mounted) {
      setState(() {
        _currentBrief = brief;
        _briefLoading = false;
        _briefShownOnce = true;
      });
      // 음소거 아니면 TTS로도 읽어줌
      if (brief.isNotEmpty && !context.read<SettingsService>().ttsMuted) {
        context.read<JarvisService>().speak(brief);
      }
    }
  }

  /// 3회 이상 주행한 루트에 자동 닉네임 (fire-and-forget)
  void _namePopularRoutes(List<RevvRoute> routes) {
    final svc = _routeSvc;
    if (svc == null) return;
    for (final r in routes.where((r) => r.runCount >= 3)) {
      RevvAiService().nameRoute(r).then((name) {
        if (name != null && mounted) svc.renameRoute(r.id, name);
      });
    }
  }

  /// 북마크 시 닉네임 즉시 생성
  void _nameOnSave(RevvRoute route) {
    final svc = _routeSvc;
    if (svc == null) return;
    RevvAiService().nameRoute(route).then((name) {
      if (name != null && mounted) svc.renameRoute(route.id, name);
    });
  }

  void _activateLoopTab() {
    final routes = _routeSvc?.routes ?? [];
    final loc = context.read<LocationService>();
    final home = context.read<HomeLocationService>().home;
    final origin = (_loopFromHome && home != null)
        ? home
        : LatLng(loc.lat, loc.lng);
    _loopSvc.addListener(_onLoopServiceChanged);
    _loopSvc.reset();
    _loopSvc.buildLoops(routes, origin);
  }

  Future<void> _drawLoopRoutes(LoopRoute loop) async {
    if (!_styleLoaded || _polyManager == null || _isDrawing) return;
    _isDrawing = true;
    try {
      await _polyManager!.deleteAll();
      _polylines.clear();
      _annotationToRoute.clear();
      for (int i = 0; i < loop.segments.length; i++) {
        final seg = loop.segments[i];
        final coords = seg.nodes
            .map((n) => mbx.Position(n.lng, n.lat))
            .toList();
        final diffColor = _routeDiffColorInt(seg.difficultyLevel);
        final poly = await _polyManager!.create(
          mbx.PolylineAnnotationOptions(
            geometry: mbx.LineString(coordinates: coords),
            lineColor: i == 0 ? 0xFFFFFFFF : diffColor,
            lineWidth: i == 0 ? 6.5 : 4.5,
            lineOpacity: 1.0,
          ),
        );
        _polylines.add(poly);
      }
    } finally {
      _isDrawing = false;
    }
    // 전체 루프가 보이도록 첫 세그먼트 중심으로 flyTo
    if (loop.segments.isNotEmpty) {
      final c = loop.segments.first.centerPoint;
      _mapController?.flyTo(
        mbx.CameraOptions(
          center: mbx.Point(coordinates: mbx.Position(c.lng, c.lat)),
          zoom: 9.5,
          pitch: 0,
        ),
        mbx.MapAnimationOptions(duration: 900),
      );
    }
  }

  // ── 루트 서비스 리스너 ──────────────────────────────────────────
  void _onRouteServiceChanged() {
    if (!mounted || _routeSvc == null) return;
    if (_activeTab != 0) return; // LOOP 탭에서는 무시
    if (_styleLoaded && !_routeSvc!.isLoading) {
      final sel = _routeSvc!.selectedRoute;
      // 인기 루트 닉네임 (3회 이상 주행)
      _namePopularRoutes(_routeSvc!.routes);
      if (sel != null && sel.id != _lastFlownRouteId) {
        _lastFlownRouteId = sel.id;
        // AI 브리핑 fetch
        _fetchBrief(sel);
        _mapController?.flyTo(
          mbx.CameraOptions(
            center: mbx.Point(
              coordinates: mbx.Position(
                sel.centerPoint.lng,
                sel.centerPoint.lat,
              ),
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
    _polyManager = await _mapController?.annotations
        .createPolylineAnnotationManager();
    _polyTapEvents?.cancel();
    _polyTapEvents = _polyManager?.tapEvents(
      onTap: (annotation) {
        final route = _annotationToRoute[annotation.id];
        if (route != null && mounted) {
          context.read<RouteService>().selectRoute(route);
        }
      },
    );
    await _applyCustomStyle();
    if (!mounted) return;
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
        await map.style.setStyleImportConfigProperty(
          'basemap',
          entry.key,
          entry.value,
        );
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
        final coords = route.nodes
            .map((n) => mbx.Position(n.lng, n.lat))
            .toList();
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
        _annotationToRoute[poly.id] = route;
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
        final coords = route.nodes
            .map((n) => mbx.Position(n.lng, n.lat))
            .toList();
        await _polyManager!.create(
          mbx.PolylineAnnotationOptions(
            geometry: mbx.LineString(coordinates: coords),
            lineColor: _routeDiffColorInt(route.difficultyLevel),
            lineWidth: 4.5,
            lineOpacity: 0.4,
          ),
        );
      }
      final allCoords = base.nodes
          .map((n) => mbx.Position(n.lng, n.lat))
          .toList();
      // 잘려나갈 앞 부분 (회색)
      if (s > 1) {
        await _polyManager!.create(
          mbx.PolylineAnnotationOptions(
            geometry: mbx.LineString(coordinates: allCoords.sublist(0, s + 1)),
            lineColor: 0xFF444444,
            lineWidth: 4.0,
            lineOpacity: 0.5,
          ),
        );
      }
      // 살아남는 구간 (흰색+컬러)
      final kept = allCoords.sublist(s, e);
      final diffColor = _routeDiffColorInt(base.difficultyLevel);
      await _polyManager!.create(
        mbx.PolylineAnnotationOptions(
          geometry: mbx.LineString(coordinates: kept),
          lineColor: 0xFFFFFFFF,
          lineWidth: 7.0,
          lineOpacity: 1.0,
        ),
      );
      await _polyManager!.create(
        mbx.PolylineAnnotationOptions(
          geometry: mbx.LineString(coordinates: kept),
          lineColor: diffColor,
          lineWidth: 4.5,
          lineOpacity: 1.0,
        ),
      );
      // 잘려나갈 뒷 부분 (회색)
      if (e < allCoords.length - 1) {
        await _polyManager!.create(
          mbx.PolylineAnnotationOptions(
            geometry: mbx.LineString(coordinates: allCoords.sublist(e)),
            lineColor: 0xFF444444,
            lineWidth: 4.0,
            lineOpacity: 0.5,
          ),
        );
      }
    } finally {
      _isDrawing = false;
    }
  }

  // ── 루트 편집 화면 진입 ───────────────────────────────────────────
  Future<void> _openRouteEdit(RevvRoute route, RouteService svc) async {
    final result =
        await Navigator.push<({RevvRoute trimmed, RevvRoute branch})>(
          context,
          MaterialPageRoute(
            builder: (_) => RouteEditScreen(
              route: route,
              otherRoutes: svc.routes.where((r) => r.id != route.id).toList(),
            ),
          ),
        );
    if (result == null || !mounted) return;
    // 트리밍된 루트 선택 + 분기 루트를 체인에 추가
    svc.selectRoute(result.trimmed);
    svc.addManualChain(result.branch);
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
    setState(() => _lastFlownRouteId = null);
    _routeSvc?.fetchRoutes(route.centerPoint.lat, route.centerPoint.lng);
  }

  // ── H. 지도 중심으로 재검색 ──────────────────────────────────────
  Future<void> _searchHere() async {
    final camera = await _mapController?.getCameraState();
    if (camera == null) return;
    final center = camera.center;
    final lat = center.coordinates.lat.toDouble();
    final lng = center.coordinates.lng.toDouble();
    setState(() => _lastFlownRouteId = null);
    _routeSvc?.resetCache();
    _routeSvc?.fetchRoutes(lat, lng);
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
        chained: svc.manualChainedRoutes,
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
      final x =
          math.cos(lat1) * math.sin(lat2) -
          math.sin(lat1) * math.cos(lat2) * math.cos(dLng);
      return math.atan2(y, x) * 180 / math.pi;
    }

    double diff(double b1, double b2) {
      double d = (b2 - b1).abs();
      return d > 180 ? 360 - d : d;
    }

    int colorForRate(double rate) {
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
        await _polyManager!.create(
          mbx.PolylineAnnotationOptions(
            geometry: mbx.LineString(coordinates: curGroup),
            lineColor: curColor,
            lineWidth: 5.5,
            lineOpacity: 1.0,
          ),
        );
      }
    }

    for (int i = 0; i < nodes.length - 2; i++) {
      final d = RevvRoute.haversineKm(nodes[i], nodes[i + 1]);
      final rate = d > 0.0001
          ? diff(
                  bear(nodes[i], nodes[i + 1]),
                  bear(nodes[i + 1], nodes[i + 2]),
                ) /
                d
          : 0.0;
      final c = colorForRate(rate);
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
    final initialCenter = loc.bestKnownLatLng;

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
                      coordinates: mbx.Position(
                        initialCenter?.lng ?? 0.0,
                        initialCenter?.lat ?? 0.0,
                      ),
                    ),
                    zoom: 10.0,
                    pitch: 0,
                  ),
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
                RoutesTapScale(
                  onTap: () => Navigator.pop(context),
                  child: ClipOval(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.78),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.25),
                          ),
                        ),
                        child: const Icon(
                          Icons.arrow_back_ios_new_rounded,
                          size: 15,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                // 탭 토글: ROUTES | LOOP
                Expanded(
                  child: Container(
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.08),
                      ),
                    ),
                    child: Row(
                      children: [
                        RoutesTabButton(
                          label: 'ROUTES',
                          active: _activeTab == 0,
                          onTap: () {
                            if (_activeTab == 0) return;
                            setState(() => _activeTab = 0);
                            final svc = _routeSvc;
                            if (svc != null && _styleLoaded) {
                              _drawRoutes(svc.routes, svc.selectedRoute);
                            }
                          },
                        ),
                        RoutesTabButton(
                          label: 'LOOP',
                          active: _activeTab == 1,
                          onTap: () {
                            if (_activeTab == 1) return;
                            setState(() {
                              _activeTab = 1;
                              _loopIdx = 0;
                            });
                            _activateLoopTab();
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                // 루트 wizard
                RoutesTapScale(
                  onTap: () => RouteWizardSheet.show(context),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.62),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppColors.red.withValues(alpha: 0.5),
                      ),
                    ),
                    child: const Icon(
                      Icons.add_road_rounded,
                      size: 18,
                      color: AppColors.red,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── 지도 중심 재검색 버튼 ──
          Positioned(
            top: MediaQuery.of(context).padding.top + 62,
            left: 0,
            right: 0,
            child: Consumer<RouteService>(
              builder: (_, svc, __) {
                if (svc.isLoadingInitial) return const SizedBox.shrink();
                return Center(
                  child: RoutesTapScale(
                    onTap: _searchHere,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.75),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: AppColors.red.withValues(alpha: 0.6),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.red.withValues(alpha: 0.25),
                            blurRadius: 10,
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.search_rounded,
                            size: 13,
                            color: AppColors.red,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '이 지역 검색',
                            style: GoogleFonts.rajdhani(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              letterSpacing: 1,
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

          // 로딩 오버레이 — FadeTransition으로 부드럽게 등장/사라짐
          Consumer<RouteService>(
            builder: (context, svc, _) {
              return AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: svc.isLoadingInitial
                    ? Positioned.fill(
                        key: const ValueKey('loading'),
                        child: IgnorePointer(
                          child: Container(
                            color: Colors.black.withValues(alpha: 0.45),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  'REVV가 주변 루트를 분석하고 있어요',
                                  style: GoogleFonts.rajdhani(
                                    fontSize: 14,
                                    color: Colors.white,
                                  ),
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
                      )
                    : const SizedBox.shrink(key: ValueKey('no-loading')),
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
                      color: AppColors.red.withValues(alpha: 0.5),
                    ),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    svc.errorMessage!,
                    style: GoogleFonts.rajdhani(
                      fontSize: 13,
                      color: Colors.white,
                    ),
                  ),
                ),
              );
            },
          ),

          Consumer<RouteService>(
            builder: (context, svc, _) {
              final showStatus =
                  svc.isRefreshingDiversity ||
                  svc.backgroundStatusMessage != null ||
                  svc.currentSearchRadiusKm > 0;
              if (!showStatus) return const SizedBox.shrink();
              final statusMessage = svc.backgroundStatusMessage;
              return Positioned(
                top: MediaQuery.of(context).padding.top + 106,
                right: 14,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.72),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.08),
                        ),
                      ),
                      child: Text(
                        svc.searchStatusLabel,
                        style: GoogleFonts.rajdhani(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Colors.white70,
                        ),
                      ),
                    ),
                    if (statusMessage != null) const SizedBox(height: 8),
                    if (statusMessage != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.72),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.08),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (svc.isRefreshingDiversity)
                              const SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(
                                  strokeWidth: 1.5,
                                  color: AppColors.red,
                                ),
                              ),
                            if (svc.isRefreshingDiversity)
                              const SizedBox(width: 8),
                            Text(
                              statusMessage,
                              style: GoogleFonts.rajdhani(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Colors.white70,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              );
            },
          ),

          // ── 하단 카드 (ROUTES 탭) ──
          if (_activeTab == 0)
            Positioned(
              bottom: MediaQuery.of(context).padding.bottom + 8,
              left: 12,
              right: 12,
              child: Consumer<RouteService>(
                builder: (_, svc, __) {
                  if (svc.isLoadingInitial) {
                    return const Center(
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.red,
                        ),
                      ),
                    );
                  }
                  final total = svc.routes.length;
                  final idx = total == 0
                      ? 0
                      : svc.routes
                            .indexWhere((r) => r.id == svc.selectedRoute?.id)
                            .clamp(0, total - 1);
                  final selected = svc.selectedRoute;
                  if (total == 0) {
                    return Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: const Color(0xF0141416),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.08),
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '아직 주변 와인딩 루트를 충분히 찾지 못했어요',
                            style: GoogleFonts.rajdhani(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            svc.backgroundStatusMessage ??
                                '반경을 넓히거나 조건을 완화해 더 많은 루트를 찾는 중이에요.',
                            style: GoogleFonts.rajdhani(
                              fontSize: 13,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                  return GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onHorizontalDragEnd: (details) {
                      final v = details.primaryVelocity ?? 0;
                      if (v < -200) {
                        _nextRoute(svc);
                      } else if (v > 200) {
                        _prevRoute(svc);
                      }
                    },
                    child: _SwipeRouteCard(
                      selected: selected,
                      displayIdx: idx,
                      total: total,
                      searchRadiusKm: svc.searchRadiusKm,
                      connectingCount: svc.connectingRoutes.length,
                      totalChainKm:
                          svc.selectedCompositeRoute?.totalDistanceKm ??
                          (selected?.distanceKm ?? 0),
                      heatmapActive: _heatmapMode,
                      onSaved: selected != null
                          ? () => _nameOnSave(selected)
                          : null,
                      onGo: () => svc.requestSprint(
                        route: svc.selectedCompositeRoute?.toRouteProjection(),
                      ),
                      onClose: () => svc.deselectRoute(),
                      onTrim: selected != null
                          ? () => _startTrim(selected)
                          : null,
                      onReverse: selected != null
                          ? () => _reverseRoute(selected)
                          : null,
                      onFindSimilar: selected != null
                          ? () => _findSimilar(selected)
                          : null,
                      onChain: selected != null
                          ? () => _showChainPicker(selected)
                          : null,
                      onHeatmap: selected != null
                          ? () => _toggleHeatmap(selected)
                          : null,
                      onEdit: selected != null
                          ? () => _openRouteEdit(selected, svc)
                          : null,
                      onExclude: selected != null
                          ? () => svc.excludeRoute(selected)
                          : null,
                      onPreview: selected != null
                          ? () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => RouteDetailScreen(
                                  routeId: selected.id,
                                  brief: _currentBrief,
                                  briefLoading: _briefLoading,
                                ),
                              ),
                            )
                          : null,
                    ),
                  );
                },
              ),
            ),

          // ── 하단 카드 (LOOP 탭) ──
          if (_activeTab == 1)
            Positioned(
              bottom: MediaQuery.of(context).padding.bottom + 8,
              left: 12,
              right: 12,
              child: RoutesLoopTabPanel(
                loopSvc: _loopSvc,
                loopIdx: _loopIdx,
                loopFromHome: _loopFromHome,
                loopBrief: _loopBrief,
                loopBriefLoading: _loopBriefLoading,
                onLoopSelected: (idx) {
                  setState(() => _loopIdx = idx);
                  if (_loopSvc.loops.isNotEmpty) {
                    _drawLoopRoutes(_loopSvc.loops[idx]);
                  }
                },
                onHomeToggled: (val) {
                  setState(() => _loopFromHome = val);
                  _activateLoopTab();
                },
                onGo: () {
                  if (_loopSvc.loops.isEmpty) return;
                  final loop = _loopSvc.loops[_loopIdx];
                  if (loop.segments.isEmpty) return;
                  final svc = _routeSvc;
                  if (svc == null) return;
                  svc.selectRoute(loop.segments.first);
                  svc.requestSprint();
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
// 통합 스와이프 루트 카드 — 카운터+반경 헤더 + 루트 상세 (선택 시)
// 좌우 스와이프로 이전/다음 루트 탐색
// ══════════════════════════════════════════════════════════════════
class _SwipeRouteCard extends StatelessWidget {
  final RevvRoute? selected;
  final int displayIdx;
  final int total;
  final int searchRadiusKm;
  final int connectingCount;
  final double totalChainKm;
  final bool heatmapActive;
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
  final VoidCallback? onSaved; // 북마크 저장 시 (저장→해제 아님)

  const _SwipeRouteCard({
    required this.selected,
    required this.displayIdx,
    required this.total,
    required this.searchRadiusKm,
    required this.connectingCount,
    required this.totalChainKm,
    required this.heatmapActive,
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
    final route = selected;
    final diffColor = route != null
        ? _routeDiffColor(route.difficultyLevel)
        : AppColors.red;

    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      alignment: Alignment.bottomCenter,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xF0141416),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.08),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.6),
              blurRadius: 20,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(15),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 난이도 컬러 밴드
              Container(height: 3, color: diffColor.withValues(alpha: 0.75)),
              // ── 헤더: 카운터 + 반경 버튼 ──
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Text(
                      '추천 루트',
                      style: GoogleFonts.orbitron(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: Text(
                        total == 0 ? '— / —' : '${displayIdx + 1} / $total',
                        style: GoogleFonts.rajdhani(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '탐색 반경',
                      style: GoogleFonts.rajdhani(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textHint,
                      ),
                    ),
                    const SizedBox(width: 6),
                    RoutesRadiusButton(km: 30, active: searchRadiusKm == 30),
                    RoutesRadiusButton(km: 50, active: searchRadiusKm == 50),
                    RoutesRadiusButton(km: 100, active: searchRadiusKm == 100),
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: () => context.read<RouteService>().shuffleRoutes(),
                      child: const Icon(
                        Icons.refresh_rounded,
                        size: 15,
                        color: AppColors.textHint,
                      ),
                    ),
                  ],
                ),
              ),
              // ── 루트 상세 (루트 선택 시만) — AnimatedSwitcher 진입 페이드 ──
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                transitionBuilder: (child, anim) => FadeTransition(
                  opacity: anim,
                  child: SlideTransition(
                    position:
                        Tween(
                          begin: const Offset(0, 0.06),
                          end: Offset.zero,
                        ).animate(
                          CurvedAnimation(
                            parent: anim,
                            curve: Curves.easeOutCubic,
                          ),
                        ),
                    child: child,
                  ),
                ),
                child: route == null
                    ? const SizedBox.shrink(key: ValueKey('no-route'))
                    : RoutesSelectionPanel(
                        route: route,
                        diffColor: diffColor,
                        connectingCount: connectingCount,
                        totalChainKm: totalChainKm,
                        onGo: onGo,
                        onClose: onClose,
                        onTrim: onTrim,
                        onReverse: onReverse,
                        onFindSimilar: onFindSimilar,
                        onChain: onChain,
                        onHeatmap: onHeatmap,
                        onEdit: onEdit,
                        onExclude: onExclude,
                        onPreview: onPreview,
                        onSaved: onSaved,
                      ),
              ),
            ],
          ),
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
        maxHeight: MediaQuery.of(context).size.height * 0.55,
      ),
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
            width: 36,
            height: 4,
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
                const Icon(
                  Icons.add_link_rounded,
                  size: 14,
                  color: AppColors.red,
                ),
                const SizedBox(width: 8),
                Text(
                  '체인 연결',
                  style: GoogleFonts.rajdhani(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: 1,
                  ),
                ),
                const Spacer(),
                if (chained.isNotEmpty)
                  Text(
                    '총 ${(selected.distanceKm + chained.fold<double>(0, (s, r) => s + r.distanceKm)).toStringAsFixed(0)}km',
                    style: GoogleFonts.orbitron(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.red,
                    ),
                  ),
              ],
            ),
          ),
          const Divider(color: AppColors.divider, height: 1),
          Flexible(
            child: ListView.builder(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).padding.bottom + 8,
              ),
              itemCount: allRoutes.length,
              itemBuilder: (_, i) {
                final r = allRoutes[i];
                final isChained = chained.any((c) => c.id == r.id);
                final diffColor = _routeDiffColor(r.difficultyLevel);
                return ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 2,
                  ),
                  leading: Container(
                    width: 4,
                    height: 36,
                    decoration: BoxDecoration(
                      color: diffColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  title: Text(
                    r.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.rajdhani(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  subtitle: Text(
                    '${r.distanceDisplay}  ·  ${r.difficultyLabel}',
                    style: GoogleFonts.rajdhani(
                      fontSize: 10,
                      color: AppColors.textHint,
                    ),
                  ),
                  trailing: GestureDetector(
                    onTap: () => isChained ? onRemove(r.id) : onAdd(r),
                    child: Container(
                      width: 32,
                      height: 32,
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
        16,
        14,
        16,
        MediaQuery.of(context).padding.bottom + 14,
      ),
      decoration: BoxDecoration(
        color: const Color(0xF2141416),
        border: const Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 헤더
          Row(
            children: [
              const Icon(
                Icons.content_cut_rounded,
                size: 14,
                color: AppColors.red,
              ),
              const SizedBox(width: 8),
              Text(
                '구간 조절',
                style: GoogleFonts.rajdhani(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: 1,
                ),
              ),
              const Spacer(),
              Text(
                '${kept.toStringAsFixed(1)} km',
                style: GoogleFonts.orbitron(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.red,
                ),
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
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
            ),
            child: Column(
              children: [
                // 시작 슬라이더
                Row(
                  children: [
                    Text(
                      '시작',
                      style: GoogleFonts.rajdhani(
                        fontSize: 10,
                        color: AppColors.textHint,
                        letterSpacing: 1,
                      ),
                    ),
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
                        fontSize: 10,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
                // 끝 슬라이더
                Row(
                  children: [
                    Text(
                      '  끝',
                      style: GoogleFonts.rajdhani(
                        fontSize: 10,
                        color: AppColors.textHint,
                        letterSpacing: 1,
                      ),
                    ),
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
                        fontSize: 10,
                        color: AppColors.textSecondary,
                      ),
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
                      child: Text(
                        '취소',
                        style: GoogleFonts.rajdhani(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textSecondary,
                        ),
                      ),
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
                          blurRadius: 8,
                        ),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        '이 구간으로 설정',
                        style: GoogleFonts.rajdhani(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          letterSpacing: 0.5,
                        ),
                      ),
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
