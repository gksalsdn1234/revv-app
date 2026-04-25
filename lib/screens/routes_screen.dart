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
import '../models/composite_route.dart';
import '../theme/text_styles.dart';
import 'route_wizard_screen.dart';
import 'route_edit_screen.dart';
import 'route_detail_screen.dart';
import '../widgets/revv_ui.dart';
import '../widgets/routes_selection_panel.dart';
import '../widgets/routes_screen_support.dart';

class RoutesScreen extends StatefulWidget {
  const RoutesScreen({super.key});

  @override
  State<RoutesScreen> createState() => _RoutesScreenState();
}

typedef _RoutePanelState = ({
  List<RevvRoute> routes,
  RevvRoute? selectedRoute,
  bool isLoadingInitial,
  String? routeDataStatusTitle,
  String? routeDataStatusBody,
  String routeDataSourceLabel,
  int lastCloudCandidateCount,
  int lastUsableCloudRouteCount,
  int connectingCount,
  double totalChainKm,
  bool isLoadingConnecting,
  bool hasActiveExtension,
});

class _RoutesScreenState extends State<RoutesScreen> {
  // ── 지도 ──────────────────────────────────────────────────────
  mbx.MapboxMap? _mapController;
  mbx.PolylineAnnotationManager? _polyManager;
  mbx.CircleAnnotationManager? _farRouteManager;
  mbx.Cancelable? _polyTapEvents;
  mbx.Cancelable? _farRouteTapEvents;
  final List<mbx.PolylineAnnotation> _polylines = [];
  final List<mbx.CircleAnnotation> _farRouteDots = [];
  final Map<String, RevvRoute> _annotationToRoute = {};
  final Map<String, RevvRoute> _circleToRoute = {};
  bool _styleLoaded = false;
  bool _isDrawing = false;
  String? _lastFlownRouteId;
  String? _lastRouteRenderKey;
  RouteService? _routeSvc;
  LocationService? _locationSvc;
  bool _initialRouteFetchRequested = false;
  bool _initialMapCenteredOnLiveLocation = false;
  bool _routeCardExpanded = false;

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
    _farRouteTapEvents?.cancel();
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
      await _farRouteManager?.deleteAll();
      _polylines.clear();
      _farRouteDots.clear();
      _annotationToRoute.clear();
      _circleToRoute.clear();
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
      final renderKey = _buildRouteRenderKey(_routeSvc!.routes, sel);
      // 인기 루트 닉네임 (3회 이상 주행)
      _namePopularRoutes(_routeSvc!.routes);
      if (sel != null && sel.id != _lastFlownRouteId) {
        _lastFlownRouteId = sel.id;
        _routeCardExpanded = false;
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
      if (renderKey != _lastRouteRenderKey) {
        _lastRouteRenderKey = renderKey;
        _drawRoutes(_routeSvc!.routes, sel);
      }
    }
  }

  String _buildRouteRenderKey(List<RevvRoute> routes, RevvRoute? selected) {
    final routeIds = routes.map((route) => route.id).join('|');
    return '${selected?.id ?? 'none'}::$routeIds';
  }

  // ── 지도 콜백 ──────────────────────────────────────────────────
  void _onMapCreated(mbx.MapboxMap controller) {
    _mapController = controller;
  }

  void _onMapTap(mbx.MapContentGestureContext tap) {
    final svc = _routeSvc;
    if (!mounted || svc == null || _activeTab != 0 || _trimMode) return;
    final lng = tap.point.coordinates.lng.toDouble();
    final lat = tap.point.coordinates.lat.toDouble();
    final nearest = _nearestRouteToPoint(LatLng(lat, lng), svc.routes);
    if (nearest == null) return;

    if (svc.selectedRoute?.id != nearest.route.id) {
      setState(() {
        _lastFlownRouteId = null;
        _routeCardExpanded = false;
      });
      svc.selectRoute(nearest.route);
    }
  }

  ({RevvRoute route, double distanceKm})? _nearestRouteToPoint(
    LatLng point,
    List<RevvRoute> routes,
  ) {
    RevvRoute? bestRoute;
    var bestDistanceKm = double.infinity;

    for (final route in routes) {
      if (route.nodes.length < 2) continue;
      for (var i = 0; i < route.nodes.length - 1; i++) {
        final distanceKm = _distanceToSegmentKm(
          point,
          route.nodes[i],
          route.nodes[i + 1],
        );
        if (distanceKm < bestDistanceKm) {
          bestDistanceKm = distanceKm;
          bestRoute = route;
        }
      }
    }

    // 손가락 터치를 감안해 선 위가 아니어도 근처면 선택되게 한다.
    if (bestRoute == null || bestDistanceKm > 0.45) return null;
    return (route: bestRoute, distanceKm: bestDistanceKm);
  }

  double _distanceToSegmentKm(LatLng point, LatLng start, LatLng end) {
    const latScale = 111.32;
    final lngScale =
        111.32 * math.cos(point.lat * math.pi / 180).abs().clamp(0.1, 1.0);

    final ax = (start.lng - point.lng) * lngScale;
    final ay = (start.lat - point.lat) * latScale;
    final bx = (end.lng - point.lng) * lngScale;
    final by = (end.lat - point.lat) * latScale;
    final dx = bx - ax;
    final dy = by - ay;
    final len2 = dx * dx + dy * dy;
    if (len2 == 0) return math.sqrt(ax * ax + ay * ay);

    final t = ((-(ax * dx + ay * dy)) / len2).clamp(0.0, 1.0);
    final closestX = ax + t * dx;
    final closestY = ay + t * dy;
    return math.sqrt(closestX * closestX + closestY * closestY);
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
    _farRouteManager = await _mapController?.annotations
        .createCircleAnnotationManager();
    _farRouteTapEvents?.cancel();
    _farRouteTapEvents = _farRouteManager?.tapEvents(
      onTap: (annotation) {
        final route = _circleToRoute[annotation.id];
        if (route != null && mounted) {
          setState(() => _routeCardExpanded = false);
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
      await _farRouteManager?.deleteAll();
      _polylines.clear();
      _farRouteDots.clear();
      _annotationToRoute.clear();
      _circleToRoute.clear();
      final distanceThresholdKm = _lineRenderDistanceThresholdKm();
      final unselected = routes.where((r) => r.id != selected?.id).toList();
      final selectedList = routes.where((r) => r.id == selected?.id).toList();
      for (final route in [...unselected, ...selectedList]) {
        final isSel = route.id == selected?.id;
        final renderAsDot =
            !isSel && route.distanceFromUser > distanceThresholdKm;
        if (renderAsDot) {
          await _drawFarRouteDot(route);
          continue;
        }
        final coords = route.nodes
            .map((n) => mbx.Position(n.lng, n.lat))
            .toList();
        final diffColor = _routeDiffColorInt(route.difficultyLevel);

        // I. 히트맵 모드: 선택 루트는 세그먼트별 컬러로 그림
        if (isSel && _heatmapMode) {
          await _drawHeatmapSegments(route);
          continue;
        }

        await _drawRoutePolylineStack(
          route: route,
          coords: coords,
          diffColor: diffColor,
          selected: isSel,
          dimmed: selected != null && !isSel,
        );
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
      await _farRouteManager?.deleteAll();
      _polylines.clear();
      _farRouteDots.clear();
      _annotationToRoute.clear();
      _circleToRoute.clear();
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
      await _drawPreviewHighlight(kept, diffColor);
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

  Future<void> _drawRoutePolylineStack({
    required RevvRoute route,
    required List<mbx.Position> coords,
    required int diffColor,
    required bool selected,
    required bool dimmed,
  }) async {
    if (_polyManager == null) return;

    Future<void> addLayer({
      required int color,
      required double width,
      required double opacity,
    }) async {
      final poly = await _polyManager!.create(
        mbx.PolylineAnnotationOptions(
          geometry: mbx.LineString(coordinates: coords),
          lineColor: color,
          lineWidth: width,
          lineOpacity: opacity,
        ),
      );
      _polylines.add(poly);
      _annotationToRoute[poly.id] = route;
    }

    if (selected) {
      await addLayer(color: 0xFF081114, width: 11.0, opacity: 0.58);
      await addLayer(
        color: _selectedOuterColorInt(diffColor),
        width: 7.4,
        opacity: 0.92,
      );
      await addLayer(
        color: _selectedInnerColorInt(diffColor),
        width: 3.2,
        opacity: 0.96,
      );
      return;
    }

    await addLayer(
      color: 0xFF101416,
      width: dimmed ? 6.0 : 6.4,
      opacity: dimmed ? 0.22 : 0.28,
    );
    await addLayer(
      color: _mutedRouteColorInt(diffColor),
      width: dimmed ? 2.9 : 3.4,
      opacity: dimmed ? 0.42 : 0.58,
    );
  }

  double _lineRenderDistanceThresholdKm() {
    final radius = _routeSvc?.searchRadiusKm ?? 50;
    return (radius * 0.38).clamp(26.0, 72.0);
  }

  Future<void> _drawFarRouteDot(RevvRoute route) async {
    final manager = _farRouteManager;
    if (manager == null) return;
    final diffColor = _routeDiffColorInt(route.difficultyLevel);
    final dot = await manager.create(
      mbx.CircleAnnotationOptions(
        geometry: mbx.Point(
          coordinates: mbx.Position(
            route.centerPoint.lng,
            route.centerPoint.lat,
          ),
        ),
        circleColor: _mutedRouteColorInt(diffColor),
        circleOpacity: 0.82,
        circleRadius: route.isLoop ? 6.5 : 5.5,
        circleStrokeColor: 0xFF0A1012,
        circleStrokeOpacity: 0.92,
        circleStrokeWidth: 2.4,
        circleBlur: route.isLoop ? 0.08 : 0.02,
        circleSortKey: route.routeRankScore,
      ),
    );
    _farRouteDots.add(dot);
    _circleToRoute[dot.id] = route;
  }

  Future<void> _drawPreviewHighlight(
    List<mbx.Position> coords,
    int diffColor,
  ) async {
    if (_polyManager == null) return;
    for (final layer in [
      (color: 0xFF081114, width: 10.5, opacity: 0.55),
      (color: _selectedOuterColorInt(diffColor), width: 7.0, opacity: 0.92),
      (color: _selectedInnerColorInt(diffColor), width: 3.0, opacity: 0.96),
    ]) {
      await _polyManager!.create(
        mbx.PolylineAnnotationOptions(
          geometry: mbx.LineString(coordinates: coords),
          lineColor: layer.color,
          lineWidth: layer.width,
          lineOpacity: layer.opacity,
        ),
      );
    }
  }

  // ── 루트 편집 화면 진입 ───────────────────────────────────────────
  Future<void> _openRouteEdit(RevvRoute route, RouteService svc) async {
    final result = await Navigator.push<RouteEditResult>(
      context,
      MaterialPageRoute(
        builder: (_) => RouteEditScreen(
          route: route,
          otherRoutes: svc.routes.where((r) => r.id != route.id).toList(),
        ),
      ),
    );
    if (result == null || !mounted) return;
    // 편집된 루트 선택 + 필요하면 분기 루트를 체인에 추가
    svc.selectRoute(result.route);
    final branch = result.branchRoute;
    if (branch != null) svc.addManualChain(branch);
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

  // ── G2. 자동 루트 확장 생성 ─────────────────────────────────────
  Future<void> _generateRouteExtension(RevvRoute selected) async {
    final svc = _routeSvc;
    if (svc == null) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    setState(() => _routeCardExpanded = false);
    final options = await svc.generateRouteExtensionOptions(selected);
    if (!mounted) return;
    if (options.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('자연스럽게 이어지는 후보를 찾지 못했어요.')));
      return;
    }
    final composite = options.length == 1
        ? svc.commitRouteExtensionOption(options.first)
        : await _showRouteExtensionOptions(options);
    if (!mounted || composite == null) return;
    setState(() {
      _routeCardExpanded = false;
      _heatmapMode = false;
    });
    _drawRoutes(svc.routes, svc.selectedRoute);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '확장 루트 생성 완료 · ${composite.totalDistanceKm.toStringAsFixed(0)}km',
        ),
      ),
    );
  }

  Future<CompositeRoute?> _showRouteExtensionOptions(
    List<RouteExtensionOption> options,
  ) {
    final svc = _routeSvc;
    if (svc == null) return Future.value(null);
    return showModalBottomSheet<CompositeRoute>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _RouteExtensionOptionsSheet(
        options: options,
        onSelect: (option) {
          Navigator.pop(context, svc.commitRouteExtensionOption(option));
        },
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
    setState(() => _routeCardExpanded = false);
    svc.selectRoute(svc.routes[newIdx]);
  }

  void _nextRoute(RouteService svc) {
    if (svc.routes.isEmpty) return;
    final idx = svc.routes.indexWhere((r) => r.id == svc.selectedRoute?.id);
    final newIdx = (idx + 1) % svc.routes.length;
    setState(() => _routeCardExpanded = false);
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
                  onTapListener: _onMapTap,
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      AppColors.bg.withValues(alpha: 0.34),
                      Colors.transparent,
                      Colors.transparent,
                      AppColors.bg.withValues(alpha: 0.48),
                    ],
                    stops: const [0.0, 0.16, 0.54, 1.0],
                  ),
                ),
              ),
            ),
          ),

          // ── 상단 미니 컨트롤 ──
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            left: 14,
            right: 14,
            child:
                Selector<
                  RouteService,
                  ({int routeCount, bool isLoadingInitial})
                >(
                  selector: (_, svc) => (
                    routeCount: svc.routes.length,
                    isLoadingInitial: svc.isLoadingInitial,
                  ),
                  builder: (context, data, _) {
                    return Row(
                      children: [
                        RoutesTapScale(
                          onTap: () => Navigator.pop(context),
                          child: const _RouteChromeCircle(
                            icon: Icons.arrow_back_ios_new_rounded,
                            iconSize: 15,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _RouteModeSwitch(
                            activeTab: _activeTab,
                            routeCount: data.routeCount,
                            onRoutes: () {
                              if (_activeTab == 0) return;
                              setState(() => _activeTab = 0);
                              final svc = _routeSvc;
                              if (svc != null && _styleLoaded) {
                                _drawRoutes(svc.routes, svc.selectedRoute);
                              }
                            },
                            onLoop: () {
                              if (_activeTab == 1) return;
                              setState(() {
                                _activeTab = 1;
                                _loopIdx = 0;
                              });
                              _activateLoopTab();
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        if (!data.isLoadingInitial) ...[
                          RoutesTapScale(
                            onTap: _searchHere,
                            child: const _RouteChromeCircle(
                              icon: Icons.search_rounded,
                              label: '여기서 찾기',
                              iconSize: 18,
                            ),
                          ),
                          const SizedBox(width: 10),
                        ],
                        RoutesTapScale(
                          onTap: () => RouteWizardSheet.show(context),
                          child: const _RouteChromeCircle(
                            icon: Icons.add_road_rounded,
                            label: '생성',
                            tinted: true,
                          ),
                        ),
                      ],
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
          Selector<RouteService, bool>(
            selector: (_, svc) => svc.isLoadingInitial,
            builder: (context, isLoadingInitial, _) {
              return Positioned.fill(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: isLoadingInitial
                      ? IgnorePointer(
                          key: const ValueKey('loading'),
                          child: Container(
                            color: Colors.black.withValues(alpha: 0.45),
                            child: Center(
                              child: RevvGlassCard(
                                padding: const EdgeInsets.fromLTRB(
                                  18,
                                  18,
                                  18,
                                  16,
                                ),
                                color: AppColors.panel.withValues(alpha: 0.92),
                                glow: true,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'ROUTE DISCOVERY',
                                      style: AppText.technicalLabel(
                                        size: 10,
                                        color: AppColors.primaryContainer,
                                        letterSpacing: 2,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'REVV가 주변 루트를 분석하고 있어요',
                                      style: AppText.body(
                                        size: 14,
                                        weight: FontWeight.w700,
                                        color: AppColors.textPrimary,
                                      ),
                                    ),
                                    const SizedBox(height: 14),
                                    const SizedBox(
                                      width: 220,
                                      child: LinearProgressIndicator(
                                        color: AppColors.primaryContainer,
                                        backgroundColor:
                                            AppColors.surfaceLowest,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        )
                      : const SizedBox.shrink(key: ValueKey('no-loading')),
                ),
              );
            },
          ),

          // 에러 메시지
          Selector<RouteService, String?>(
            selector: (_, svc) => svc.errorMessage,
            builder: (context, errorMessage, _) {
              if (errorMessage == null) return const SizedBox.shrink();
              return Positioned(
                top: MediaQuery.of(context).padding.top + 62,
                left: 16,
                right: 16,
                child: RevvGlassCard(
                  padding: const EdgeInsets.all(12),
                  color: AppColors.panel.withValues(alpha: 0.92),
                  child: Text(
                    errorMessage,
                    style: AppText.body(
                      size: 13,
                      weight: FontWeight.w600,
                      color: AppColors.textPrimary,
                      height: 1.35,
                    ),
                  ),
                ),
              );
            },
          ),

          Selector<
            RouteService,
            ({
              String? errorMessage,
              bool isRefreshingDiversity,
              String? backgroundStatusMessage,
            })
          >(
            selector: (_, svc) => (
              errorMessage: svc.errorMessage,
              isRefreshingDiversity: svc.isRefreshingDiversity,
              backgroundStatusMessage: svc.backgroundStatusMessage,
            ),
            builder: (context, data, _) {
              if (data.errorMessage != null) return const SizedBox.shrink();
              final showStatus =
                  data.isRefreshingDiversity ||
                  data.backgroundStatusMessage != null;
              if (!showStatus) return const SizedBox.shrink();
              final statusMessage = data.backgroundStatusMessage;
              return Positioned(
                top: MediaQuery.of(context).padding.top + 62,
                right: 14,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.64),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: AppColors.outlineVariant.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (data.isRefreshingDiversity)
                        const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            color: AppColors.primaryContainer,
                          ),
                        ),
                      if (data.isRefreshingDiversity) const SizedBox(width: 8),
                      Text(
                        statusMessage ?? '루트 갱신 중',
                        style: AppText.body(
                          size: 12,
                          weight: FontWeight.w700,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
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
              child: Selector<RouteService, _RoutePanelState>(
                selector: (_, svc) => (
                  routes: svc.routes,
                  selectedRoute: svc.selectedRoute,
                  isLoadingInitial: svc.isLoadingInitial,
                  routeDataStatusTitle: svc.routeDataStatusTitle,
                  routeDataStatusBody: svc.routeDataStatusBody,
                  routeDataSourceLabel: svc.routeDataSourceLabel,
                  lastCloudCandidateCount: svc.lastCloudCandidateCount,
                  lastUsableCloudRouteCount: svc.lastUsableCloudRouteCount,
                  connectingCount: svc.connectingRoutes.length,
                  totalChainKm:
                      svc.selectedCompositeRoute?.totalDistanceKm ??
                      (svc.selectedRoute?.distanceKm ?? 0),
                  isLoadingConnecting: svc.isLoadingConnecting,
                  hasActiveExtension: svc.selectedCompositeRoute != null,
                ),
                builder: (_, panel, __) {
                  final svc = _routeSvc;
                  if (panel.isLoadingInitial) {
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
                  final total = panel.routes.length;
                  final idx = total == 0
                      ? 0
                      : panel.routes
                            .indexWhere((r) => r.id == panel.selectedRoute?.id)
                            .clamp(0, total - 1);
                  final selected = panel.selectedRoute;
                  final onGo = svc == null
                      ? () {}
                      : () {
                          svc.requestSprint(
                            route: svc.selectedCompositeRoute
                                ?.toRouteProjection(),
                          );
                        };
                  if (total == 0) {
                    return RevvGlassCard(
                      padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
                      color: AppColors.panel.withValues(alpha: 0.90),
                      radius: 18,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.travel_explore_rounded,
                                size: 20,
                                color: AppColors.primaryContainer,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  panel.routeDataStatusTitle ??
                                      '아직 표시할 루트가 없어요',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppText.body(
                                    size: 15,
                                    weight: FontWeight.w900,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            panel.routeDataStatusBody ??
                                '지도를 움직인 뒤 여기서 다시 찾거나, 설정에서 탐색 반경을 넓혀보세요.',
                            style: AppText.body(
                              size: 12,
                              height: 1.3,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _RouteDataChip(
                                icon: Icons.storage_rounded,
                                label: panel.routeDataSourceLabel,
                              ),
                              if (panel.lastCloudCandidateCount > 0)
                                _RouteDataChip(
                                  icon: Icons.cloud_queue_rounded,
                                  label:
                                      '클라우드 ${panel.lastUsableCloudRouteCount}/${panel.lastCloudCandidateCount}',
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          RoutesTapScale(
                            onTap: _searchHere,
                            child: Container(
                              height: 42,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.primaryContainer,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Center(
                                child: Text(
                                  '여기서 찾기',
                                  style: AppText.body(
                                    size: 13,
                                    weight: FontWeight.w900,
                                    color: AppColors.onPrimary,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                  return GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onHorizontalDragEnd: (details) {
                      if (svc == null) return;
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
                      expanded: _routeCardExpanded,
                      connectingCount: panel.connectingCount,
                      totalChainKm: panel.totalChainKm,
                      isGeneratingExtension: panel.isLoadingConnecting,
                      hasActiveExtension: panel.hasActiveExtension,
                      heatmapActive: _heatmapMode,
                      onSaved: selected != null
                          ? () => _nameOnSave(selected)
                          : null,
                      onGo: onGo,
                      onExpand: () => setState(() => _routeCardExpanded = true),
                      onCollapse: () =>
                          setState(() => _routeCardExpanded = false),
                      onClose: () {
                        if (svc == null) return;
                        if (_routeCardExpanded) {
                          setState(() => _routeCardExpanded = false);
                        } else {
                          svc.deselectRoute();
                        }
                      },
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
                      onGenerate: selected != null
                          ? () => _generateRouteExtension(selected)
                          : null,
                      onHeatmap: selected != null
                          ? () => _toggleHeatmap(selected)
                          : null,
                      onEdit: selected != null && svc != null
                          ? () => _openRouteEdit(selected, svc)
                          : null,
                      onExclude: selected != null && svc != null
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

int _mutedRouteColorInt(int colorInt) {
  final color = Color(colorInt);
  return Color.lerp(const Color(0xFF33444A), color, 0.42)!.toARGB32();
}

int _selectedOuterColorInt(int colorInt) {
  final color = Color(colorInt);
  return Color.lerp(const Color(0xFF00E5FF), color, 0.68)!.toARGB32();
}

int _selectedInnerColorInt(int colorInt) {
  final color = Color(colorInt);
  return Color.lerp(Colors.white, color, 0.18)!.toARGB32();
}

class _RouteModeSwitch extends StatelessWidget {
  final int activeTab;
  final int routeCount;
  final VoidCallback onRoutes;
  final VoidCallback onLoop;

  const _RouteModeSwitch({
    required this.activeTab,
    required this.routeCount,
    required this.onRoutes,
    required this.onLoop,
  });

  @override
  Widget build(BuildContext context) {
    return RevvGlassCard(
      padding: const EdgeInsets.all(4),
      color: AppColors.panel.withValues(alpha: 0.76),
      radius: 999,
      child: Row(
        children: [
          _RouteModeButton(
            label: '루트',
            count: routeCount,
            active: activeTab == 0,
            onTap: onRoutes,
          ),
          _RouteModeButton(label: '루프', active: activeTab == 1, onTap: onLoop),
        ],
      ),
    );
  }
}

class _RouteModeButton extends StatelessWidget {
  final String label;
  final int? count;
  final bool active;
  final VoidCallback onTap;

  const _RouteModeButton({
    required this.label,
    required this.active,
    required this.onTap,
    this.count,
  });

  @override
  Widget build(BuildContext context) {
    final fg = active ? AppColors.onPrimary : AppColors.textSecondary;
    return Expanded(
      child: RoutesTapScale(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: active ? AppColors.primaryContainer : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Center(
            child: Text(
              count == null ? label : '$label $count',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.technicalLabel(
                size: 10,
                color: fg,
                letterSpacing: 1.8,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RouteChromeCircle extends StatelessWidget {
  final IconData icon;
  final String? label;
  final double iconSize;
  final bool tinted;

  const _RouteChromeCircle({
    required this.icon,
    this.label,
    this.iconSize = 18,
    this.tinted = false,
  });

  @override
  Widget build(BuildContext context) {
    final border = tinted
        ? AppColors.primaryContainer.withValues(alpha: 0.48)
        : AppColors.outlineVariant.withValues(alpha: 0.55);
    final color = tinted ? AppColors.primaryContainer : Colors.white;
    return ClipOval(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          width: label == null ? 48 : null,
          height: 48,
          padding: label == null
              ? EdgeInsets.zero
              : const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: AppColors.bg.withValues(alpha: 0.82),
            shape: label == null ? BoxShape.circle : BoxShape.rectangle,
            borderRadius: label == null ? null : BorderRadius.circular(999),
            border: Border.all(color: border),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 18,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: iconSize, color: color),
              if (label != null) ...[
                const SizedBox(width: 7),
                Text(
                  label!,
                  style: AppText.body(
                    size: 13,
                    weight: FontWeight.w900,
                    color: color,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _RouteDataChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _RouteDataChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.52),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: AppColors.outlineVariant.withValues(alpha: 0.28),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: AppColors.textHint),
          const SizedBox(width: 5),
          Text(
            label,
            style: AppText.body(
              size: 11,
              weight: FontWeight.w800,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// 통합 스와이프 루트 카드 — 최소 헤더 + 루트 상세 (선택 시)
// 좌우 스와이프로 이전/다음 루트 탐색
// ══════════════════════════════════════════════════════════════════
class _SwipeRouteCard extends StatelessWidget {
  final RevvRoute? selected;
  final int displayIdx;
  final int total;
  final bool expanded;
  final int connectingCount;
  final double totalChainKm;
  final bool isGeneratingExtension;
  final bool hasActiveExtension;
  final bool heatmapActive;
  final VoidCallback onGo;
  final VoidCallback onExpand;
  final VoidCallback onCollapse;
  final VoidCallback onClose;
  final VoidCallback? onTrim;
  final VoidCallback? onReverse;
  final VoidCallback? onFindSimilar;
  final VoidCallback? onChain;
  final VoidCallback? onGenerate;
  final VoidCallback? onHeatmap;
  final VoidCallback? onEdit;
  final VoidCallback? onExclude;
  final VoidCallback? onPreview;
  final VoidCallback? onSaved; // 북마크 저장 시 (저장→해제 아님)

  const _SwipeRouteCard({
    required this.selected,
    required this.displayIdx,
    required this.total,
    required this.expanded,
    required this.connectingCount,
    required this.totalChainKm,
    required this.isGeneratingExtension,
    required this.hasActiveExtension,
    required this.heatmapActive,
    required this.onGo,
    required this.onExpand,
    required this.onCollapse,
    required this.onClose,
    this.onTrim,
    this.onReverse,
    this.onFindSimilar,
    this.onChain,
    this.onGenerate,
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

    return GestureDetector(
      onVerticalDragEnd: (details) {
        final v = details.primaryVelocity ?? 0;
        if (v < -160) {
          onExpand();
        } else if (v > 160) {
          expanded ? onCollapse() : onClose();
        }
      },
      child: AnimatedSize(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        alignment: Alignment.bottomCenter,
        child: RevvGlassCard(
          padding: EdgeInsets.zero,
          color: AppColors.panel.withValues(alpha: 0.92),
          radius: 16,
          glow: true,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 난이도 컬러 밴드
                Container(height: 3, color: diffColor.withValues(alpha: 0.75)),
                // ── 미니 헤더: 현재 위치와 새로고침만 표시 ──
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  child: Row(
                    children: [
                      Text(
                        total == 0 ? 'ROUTES' : '${displayIdx + 1} / $total',
                        style: AppText.technicalLabel(
                          size: 10,
                          color: AppColors.primaryContainer,
                          letterSpacing: 1.8,
                        ),
                      ),
                      const Spacer(),
                      if (connectingCount > 0)
                        Text(
                          '+$connectingCount 연결 후보',
                          style: AppText.body(
                            size: 11,
                            weight: FontWeight.w700,
                            color: AppColors.textHint,
                          ),
                        ),
                      const SizedBox(width: 8),
                      RoutesTapScale(
                        onTap: () =>
                            context.read<RouteService>().shuffleRoutes(),
                        child: const Icon(
                          Icons.refresh_rounded,
                          size: 16,
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
                          expanded: expanded,
                          connectingCount: connectingCount,
                          totalChainKm: totalChainKm,
                          isGeneratingExtension: isGeneratingExtension,
                          hasActiveExtension: hasActiveExtension,
                          onGo: onGo,
                          onExpand: onExpand,
                          onCollapse: onCollapse,
                          onClose: onClose,
                          onTrim: onTrim,
                          onReverse: onReverse,
                          onFindSimilar: onFindSimilar,
                          onChain: onChain,
                          onGenerate: onGenerate,
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
      ),
    );
  }
}

class _RouteExtensionOptionsSheet extends StatelessWidget {
  final List<RouteExtensionOption> options;
  final ValueChanged<RouteExtensionOption> onSelect;

  const _RouteExtensionOptionsSheet({
    required this.options,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        decoration: BoxDecoration(
          color: const Color(0xF2141416),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '확장 생성 후보',
              style: AppText.body(
                size: 18,
                weight: FontWeight.w900,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '원하는 길이와 흐름을 골라 바로 합성 루트로 만들어요.',
              style: AppText.body(size: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 14),
            ...options.map(
              (option) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: RoutesTapScale(
                  onTap: () => onSelect(option),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: AppColors.outlineVariant.withValues(alpha: 0.24),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: AppColors.primaryContainer.withValues(
                              alpha: 0.12,
                            ),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const Icon(
                            Icons.auto_fix_high_rounded,
                            size: 18,
                            color: AppColors.primaryContainer,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                option.label,
                                style: AppText.body(
                                  size: 15,
                                  weight: FontWeight.w900,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${option.description} · ${option.candidate.route.name}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppText.body(
                                  size: 12,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(
                          Icons.chevron_right_rounded,
                          color: AppColors.textHint,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
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
