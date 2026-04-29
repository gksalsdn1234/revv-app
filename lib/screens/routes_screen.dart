import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
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
import '../theme/text_styles.dart';
import '../ui/revv_copy.dart';
import 'route_wizard_screen.dart';
import 'route_detail_screen.dart';
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
    final routeKeys = routes
        .map((route) => '${route.id}:${route.nodes.length}')
        .join('|');
    return '${selected?.id ?? 'none'}:${selected?.nodes.length ?? 0}::$routeKeys';
  }

  // ── 지도 콜백 ──────────────────────────────────────────────────
  void _onMapCreated(mbx.MapboxMap controller) {
    _mapController = controller;
  }

  void _onMapTap(mbx.MapContentGestureContext tap) {
    final svc = _routeSvc;
    if (!mounted || svc == null || _activeTab != 0) return;
    final lng = tap.point.coordinates.lng.toDouble();
    final lat = tap.point.coordinates.lat.toDouble();
    final nearest = _nearestRouteToPoint(LatLng(lat, lng), svc.routes);
    if (nearest == null) return;

    if (svc.selectedRoute?.id != nearest.route.id) {
      setState(() {
        _lastFlownRouteId = null;
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
      final previewLineIds = unselected.take(5).map((r) => r.id).toSet();
      for (final route in [...unselected, ...selectedList]) {
        final isSel = route.id == selected?.id;
        final renderAsDot =
            !isSel &&
            !previewLineIds.contains(route.id) &&
            route.distanceFromUser > distanceThresholdKm;
        if (renderAsDot) {
          await _drawFarRouteDot(route);
          continue;
        }
        final coords = route.nodes
            .map((n) => mbx.Position(n.lng, n.lat))
            .toList();
        final diffColor = _routeDiffColorInt(route.difficultyLevel);

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
      await addLayer(color: 0xFF051014, width: 11.6, opacity: 0.62);
      await addLayer(color: 0xFF12313A, width: 8.2, opacity: 0.74);
      await addLayer(color: 0xFF35D7F2, width: 5.2, opacity: 0.90);
      await addLayer(color: 0xFFE7FBFF, width: 1.35, opacity: 0.46);
      return;
    }

    await addLayer(
      color: 0xFF071014,
      width: dimmed ? 4.2 : 4.8,
      opacity: dimmed ? 0.15 : 0.20,
    );
    await addLayer(
      color: 0xFF6F858A,
      width: dimmed ? 1.55 : 1.9,
      opacity: dimmed ? 0.28 : 0.38,
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
        circleOpacity: 0.38,
        circleRadius: route.isLoop ? 5.2 : 4.3,
        circleStrokeColor: 0xFF071014,
        circleStrokeOpacity: 0.62,
        circleStrokeWidth: 1.5,
        circleBlur: route.isLoop ? 0.10 : 0.04,
        circleSortKey: route.routeRankScore,
      ),
    );
    _farRouteDots.add(dot);
    _circleToRoute[dot.id] = route;
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

          // ── CommandLayer: 지도 공간을 침범하지 않는 1줄 컨트롤 ──
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
                    return _RouteFinderCommandBar(
                      activeTab: _activeTab,
                      routeCount: data.routeCount,
                      searchEnabled: !data.isLoadingInitial,
                      onBack: () => Navigator.pop(context),
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
                      onSearchHere: _searchHere,
                      onCreate: () => RouteWizardSheet.show(context),
                    );
                  },
                ),
          ),

          // ── StatusLayer: 지도는 유지하고 상태만 얇게 표시 ──
          Selector<
            RouteService,
            ({
              String? errorMessage,
              bool isLoadingInitial,
              bool isRefreshingDiversity,
              String? backgroundStatusMessage,
            })
          >(
            selector: (_, svc) => (
              errorMessage: svc.errorMessage,
              isLoadingInitial: svc.isLoadingInitial,
              isRefreshingDiversity: svc.isRefreshingDiversity,
              backgroundStatusMessage: svc.backgroundStatusMessage,
            ),
            builder: (context, data, _) {
              final message =
                  data.errorMessage ??
                  (data.isLoadingInitial
                      ? RevvCopy.routeLoading
                      : data.backgroundStatusMessage);
              final busy = data.isLoadingInitial || data.isRefreshingDiversity;
              if (message == null && !busy) return const SizedBox.shrink();
              return Positioned(
                top: MediaQuery.of(context).padding.top + 62,
                left: 16,
                right: 16,
                child: Align(
                  alignment: Alignment.center,
                  child: _RouteFinderToast(
                    message: message ?? RevvCopy.routeRefresh,
                    busy: busy,
                    error: data.errorMessage != null,
                  ),
                ),
              );
            },
          ),

          // ── TicketLayer: 선택/탐색/주행 시작만 남긴 작은 티켓 ──
          if (_activeTab == 0)
            Positioned(
              bottom: MediaQuery.of(context).padding.bottom + 10,
              left: 14,
              right: 14,
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
                builder: (_, panel, _) {
                  final svc = _routeSvc;
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
                          final routeToStart =
                              svc.selectedCompositeRoute?.toRouteProjection() ??
                              svc.selectedRoute;
                          if (routeToStart == null) return;
                          svc.requestSprint(route: routeToStart);
                        };
                  if (total == 0 || selected == null) {
                    return _RouteFinderHintBar(
                      title: total == 0
                          ? (panel.routeDataStatusTitle ??
                                RevvCopy.noRoutesTitle)
                          : RevvCopy.selectRouteTitle,
                      body: total == 0
                          ? (panel.routeDataStatusBody ?? RevvCopy.noRoutesBody)
                          : RevvCopy.selectRouteBody,
                      sourceLabel: panel.routeDataSourceLabel,
                      onSearchHere: _searchHere,
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
                    child: _RouteTicketBar(
                      route: selected,
                      displayIdx: idx,
                      total: total,
                      onPrev: svc != null ? () => _prevRoute(svc) : null,
                      onNext: svc != null ? () => _nextRoute(svc) : null,
                      onGo: onGo,
                      onClose: () {
                        if (svc == null) return;
                        svc.deselectRoute();
                      },
                      onPreview: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => RouteDetailScreen(
                            routeId: selected.id,
                            brief: _currentBrief,
                            briefLoading: _briefLoading,
                          ),
                        ),
                      ),
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

int _mutedRouteColorInt(int colorInt) {
  final color = Color(colorInt);
  return Color.lerp(const Color(0xFF51676C), color, 0.18)!.toARGB32();
}

class _RouteFinderCommandBar extends StatelessWidget {
  final int activeTab;
  final int routeCount;
  final bool searchEnabled;
  final VoidCallback onBack;
  final VoidCallback onRoutes;
  final VoidCallback onLoop;
  final VoidCallback onSearchHere;
  final VoidCallback onCreate;

  const _RouteFinderCommandBar({
    required this.activeTab,
    required this.routeCount,
    required this.searchEnabled,
    required this.onBack,
    required this.onRoutes,
    required this.onLoop,
    required this.onSearchHere,
    required this.onCreate,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 7),
          decoration: BoxDecoration(
            color: const Color(0xE80F1214),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(
              color: AppColors.outlineVariant.withValues(alpha: 0.28),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.36),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            children: [
              _LensIconButton(
                icon: Icons.arrow_back_ios_new_rounded,
                onTap: onBack,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: _LensSegmentButton(
                        label: '루트 $routeCount',
                        active: activeTab == 0,
                        onTap: onRoutes,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: _LensSegmentButton(
                        label: '루프',
                        active: activeTab == 1,
                        onTap: onLoop,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              _LensTextButton(
                icon: Icons.my_location_rounded,
                label: '여기',
                onTap: searchEnabled ? onSearchHere : null,
              ),
              const SizedBox(width: 4),
              _LensIconButton(
                icon: Icons.add_rounded,
                onTap: onCreate,
                tinted: true,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RouteFinderToast extends StatelessWidget {
  final String message;
  final bool busy;
  final bool error;

  const _RouteFinderToast({
    required this.message,
    this.busy = false,
    this.error = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = error ? AppColors.red : AppColors.primaryContainer;
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 320),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.68),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: color.withValues(alpha: 0.32)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (busy)
                SizedBox(
                  width: 13,
                  height: 13,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.6,
                    color: color,
                  ),
                )
              else
                Icon(
                  error ? Icons.error_outline_rounded : Icons.radar_rounded,
                  size: 14,
                  color: color,
                ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  message,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.body(
                    size: 12,
                    weight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RouteFinderHintBar extends StatelessWidget {
  final String title;
  final String body;
  final String sourceLabel;
  final VoidCallback onSearchHere;

  const _RouteFinderHintBar({
    required this.title,
    required this.body,
    required this.sourceLabel,
    required this.onSearchHere,
  });

  @override
  Widget build(BuildContext context) {
    return _LensShell(
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.primaryContainer.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppColors.primaryContainer.withValues(alpha: 0.28),
              ),
            ),
            child: const Icon(
              Icons.travel_explore_rounded,
              color: AppColors.primaryContainer,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.body(
                    size: 15,
                    weight: FontWeight.w900,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '$body · $sourceLabel',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.body(
                    size: 11,
                    weight: FontWeight.w700,
                    color: AppColors.textHint,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          _LensTextButton(
            icon: Icons.my_location_rounded,
            label: '여기서 찾기',
            onTap: onSearchHere,
            prominent: true,
          ),
        ],
      ),
    );
  }
}

class _RouteTicketBar extends StatelessWidget {
  final RevvRoute route;
  final int displayIdx;
  final int total;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  final VoidCallback onGo;
  final VoidCallback onPreview;
  final VoidCallback onClose;

  const _RouteTicketBar({
    required this.route,
    required this.displayIdx,
    required this.total,
    required this.onGo,
    required this.onPreview,
    required this.onClose,
    this.onPrev,
    this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final badge = _routeFinderBadge(route) ?? '루트';
    return _LensShell(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _LensIconButton(
                icon: Icons.chevron_left_rounded,
                onTap: onPrev,
                compact: true,
              ),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          '${displayIdx + 1} / $total',
                          style: AppText.technicalLabel(
                            size: 10,
                            color: AppColors.primaryContainer,
                            letterSpacing: 1.6,
                          ),
                        ),
                        const SizedBox(width: 8),
                        _TinyLensPill(label: badge),
                        const Spacer(),
                        RoutesTapScale(
                          onTap: onClose,
                          child: const Icon(
                            Icons.close_rounded,
                            size: 17,
                            color: Colors.white54,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      route.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.body(
                        size: 17,
                        weight: FontWeight.w900,
                        color: AppColors.textPrimary,
                        letterSpacing: -0.35,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _TicketMetric(
                          icon: Icons.straighten_rounded,
                          label: route.distanceDisplay,
                        ),
                        const SizedBox(width: 8),
                        _TicketMetric(
                          icon: Icons.timer_outlined,
                          label: route.durationDisplay,
                        ),
                        const SizedBox(width: 8),
                        _TicketMetric(
                          icon: Icons.near_me_rounded,
                          label:
                              '${route.distanceFromUser.toStringAsFixed(0)}km',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _LensIconButton(
                icon: Icons.chevron_right_rounded,
                onTap: onNext,
                compact: true,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _TicketAction(
                  label: RevvCopy.detail,
                  icon: Icons.route_rounded,
                  onTap: onPreview,
                  primary: false,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: _TicketAction(
                  label: RevvCopy.startDrive,
                  icon: Icons.navigation_rounded,
                  onTap: onGo,
                  primary: true,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LensShell extends StatelessWidget {
  final Widget child;

  const _LensShell({required this.child});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 11, 12, 12),
          decoration: BoxDecoration(
            color: const Color(0xEA101315),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: AppColors.outlineVariant.withValues(alpha: 0.26),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.44),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

class _LensSegmentButton extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _LensSegmentButton({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return RoutesTapScale(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: 38,
        decoration: BoxDecoration(
          color: active ? AppColors.primaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Center(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.body(
              size: 12,
              weight: FontWeight.w900,
              color: active ? AppColors.onPrimary : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _LensIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final bool tinted;
  final bool compact;

  const _LensIconButton({
    required this.icon,
    this.onTap,
    this.tinted = false,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return RoutesTapScale(
      onTap: onTap,
      child: Container(
        width: compact ? 34 : 38,
        height: compact ? 34 : 38,
        decoration: BoxDecoration(
          color: tinted
              ? AppColors.primaryContainer
              : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(999),
          border: tinted
              ? null
              : Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Icon(
          icon,
          size: compact ? 21 : 18,
          color: tinted ? AppColors.onPrimary : AppColors.textPrimary,
        ),
      ),
    );
  }
}

class _LensTextButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool prominent;

  const _LensTextButton({
    required this.icon,
    required this.label,
    this.onTap,
    this.prominent = false,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final bg = prominent
        ? AppColors.primaryContainer
        : Colors.white.withValues(alpha: 0.06);
    final fg = prominent ? AppColors.onPrimary : AppColors.textPrimary;
    return RoutesTapScale(
      onTap: onTap,
      child: Opacity(
        opacity: enabled ? 1 : 0.42,
        child: Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(999),
            border: prominent
                ? null
                : Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: fg),
              const SizedBox(width: 6),
              Text(
                label,
                style: AppText.body(
                  size: 12,
                  weight: FontWeight.w900,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TinyLensPill extends StatelessWidget {
  final String label;

  const _TinyLensPill({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.primaryContainer.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: AppColors.primaryContainer.withValues(alpha: 0.22),
        ),
      ),
      child: Text(
        label,
        style: AppText.body(
          size: 10,
          weight: FontWeight.w900,
          color: AppColors.primaryContainer,
        ),
      ),
    );
  }
}

class _TicketMetric extends StatelessWidget {
  final IconData icon;
  final String label;

  const _TicketMetric({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Flexible(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: Colors.white54),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.body(
                size: 12,
                weight: FontWeight.w800,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TicketAction extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool primary;

  const _TicketAction({
    required this.label,
    required this.icon,
    required this.onTap,
    required this.primary,
  });

  @override
  Widget build(BuildContext context) {
    final bg = primary
        ? AppColors.primaryContainer
        : Colors.white.withValues(alpha: 0.06);
    final fg = primary ? AppColors.onPrimary : AppColors.textPrimary;
    return RoutesTapScale(
      onTap: onTap,
      child: Container(
        height: 42,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
          border: primary
              ? null
              : Border.all(color: Colors.white.withValues(alpha: 0.09)),
          boxShadow: primary
              ? [
                  BoxShadow(
                    color: AppColors.primaryContainer.withValues(alpha: 0.20),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: fg),
            const SizedBox(width: 7),
            Text(
              label,
              style: AppText.body(size: 13, weight: FontWeight.w900, color: fg),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// 통합 스와이프 루트 카드 — 최소 헤더 + 루트 상세 (선택 시)
// 좌우 스와이프로 이전/다음 루트 탐색
// ══════════════════════════════════════════════════════════════════
String? _routeFinderBadge(RevvRoute? route) {
  if (route == null) return null;
  if (route.isLoop) return '루프';
  if (route.distanceFromUser <= 18) return '근거리';
  if (route.distanceKm >= 24) return '긴 루트';
  switch (route.routeCharacter) {
    case 'tight_technical':
      return '타이트';
    case 'fast_sweeper':
      return '스위퍼';
    case 'rhythmic_flow':
      return '흐름';
    case 'hill_climb':
      return '업힐';
  }
  switch (route.curveStyle) {
    case 'SWEEPER':
      return '스위퍼';
    case 'SWITCHBACK':
      return '타이트';
  }
  return '믹스';
}
