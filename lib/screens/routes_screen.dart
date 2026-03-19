import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mbx;
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/colors.dart';
import '../widgets/hud_bar.dart';
import '../widgets/routes_bottom_sheet.dart';
import '../services/location_service.dart';
import '../services/route_service.dart';
import '../services/mapbox_service.dart';
import '../services/poi_service.dart';
import '../services/home_location_service.dart';
import '../models/revv_route.dart';
import '../models/poi.dart';
import 'route_wizard_screen.dart';

class RoutesScreen extends StatefulWidget {
  /// 0 = ROUTES 탭, 1 = TRIP 탭
  final int initialTab;
  const RoutesScreen({super.key, this.initialTab = 0});

  @override
  State<RoutesScreen> createState() => _RoutesScreenState();
}

class _RoutesScreenState extends State<RoutesScreen> {
  // ── 지도 ──────────────────────────────────────────────────────
  mbx.MapboxMap? _mapController;
  mbx.PolylineAnnotationManager? _polyManager;
  mbx.PointAnnotationManager? _poiManager;
  final List<mbx.PolylineAnnotation> _polylines = [];
  // annotation.id → RevvRoute 매핑 (폴리라인 탭 선택용)
  final Map<String, RevvRoute> _annotationToRoute = {};
  bool _styleLoaded = false;
  bool _isDrawing = false;
  String? _lastPoiRouteId;
  String? _lastFlownRouteId;
  RouteService? _routeSvc;

  // ── 탭 ───────────────────────────────────────────────────────
  late int _tab; // 0=ROUTES, 1=TRIP

  // ── Trip Planner 상태 ─────────────────────────────────────────
  PoiCategory _selectedCategory = PoiCategory.cafe;
  List<Poi> _pois = [];
  bool _tripLoading = false;
  bool _tripSearched = false;

  // ── 집 위치 지도 핀 설정 모드 ─────────────────────────────────
  bool _settingHome = false;

  // ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _tab = widget.initialTab;
    mbx.MapboxOptions.setAccessToken(MapboxService.accessToken);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final loc = context.read<LocationService>();
      _routeSvc = context.read<RouteService>();
      // resetCache() 제거 — 캐시 유지로 매번 재탐색 방지
      _routeSvc!.fetchRoutes(loc.lat, loc.lng);
      _routeSvc!.addListener(_onRouteServiceChanged);
      if (_tab == 1) _searchPois();
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
      final newId = sel?.id;
      if (newId != null && newId != _lastPoiRouteId && _tab == 0) {
        _lastPoiRouteId = newId;
        _drawPoiPins(sel!);
      }
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
    // 폴리라인 탭 → 루트 선택 리스너 등록
    _polyManager?.addOnPolylineAnnotationClickListener(
      _PolylineClickHandler(_annotationToRoute, (route) {
        context.read<RouteService>().selectRoute(route);
      }),
    );
    _poiManager =
        await _mapController?.annotations.createPointAnnotationManager();
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
      _annotationToRoute.clear(); // 매핑 초기화
      final unselected = routes.where((r) => r.id != selected?.id).toList();
      final selectedList = routes.where((r) => r.id == selected?.id).toList();
      for (final route in [...unselected, ...selectedList]) {
        final isSel = route.id == selected?.id;
        final coords =
            route.nodes.map((n) => mbx.Position(n.lng, n.lat)).toList();
        final poly = await _polyManager!.create(
          mbx.PolylineAnnotationOptions(
            geometry: mbx.LineString(coordinates: coords),
            lineColor: isSel ? AppColors.red.value : 0xFFFFFFFF,
            lineWidth: isSel ? 5.5 : 4.0, // 미선택 4.0 → 탭 용이
            lineOpacity: isSel ? 1.0 : 0.28,
          ),
        );
        _polylines.add(poly);
        // annotation id → RevvRoute 매핑 저장 (탭 선택용)
        if (poly.id != null) {
          _annotationToRoute[poly.id!] = route;
        }
      }
    } finally {
      _isDrawing = false;
    }
  }

  // ── POI 핀 (ROUTES 탭: 루트 주변) ─────────────────────────────
  Future<void> _drawPoiPins(RevvRoute route) async {
    final manager = _poiManager;
    if (manager == null) return;
    await manager.deleteAll();
    final pois = await PoiService.searchNearby(
      route.centerPoint.lat,
      route.centerPoint.lng,
      radiusM: 8000,
      maxTotal: 20,
    );
    for (final poi in pois) {
      try {
        await manager.create(mbx.PointAnnotationOptions(
          geometry: mbx.Point(
              coordinates: mbx.Position(poi.lng, poi.lat)),
          textField: poi.category.emoji,
          textSize: 18.0,
          textColor: 0xFFFFFFFF,
        ));
      } catch (_) {}
    }
  }

  // ── POI 핀 (TRIP 탭: 현재 위치 주변) ──────────────────────────
  Future<void> _drawTripPoiPins(List<Poi> pois) async {
    final manager = _poiManager;
    if (manager == null) return;
    await manager.deleteAll();
    for (final poi in pois) {
      try {
        await manager.create(mbx.PointAnnotationOptions(
          geometry: mbx.Point(
              coordinates: mbx.Position(poi.lng, poi.lat)),
          textField: poi.category.emoji,
          textSize: 20.0,
          textColor: 0xFFFFFFFF,
        ));
      } catch (_) {}
    }
  }

  // ── Trip POI 검색 ───────────────────────────────────────────────
  Future<void> _searchPois() async {
    setState(() {
      _tripLoading = true;
      _pois = [];
    });
    final loc = context.read<LocationService>();
    final results =
        await PoiService.search(loc.lat, loc.lng, _selectedCategory);
    if (!mounted) return;
    setState(() {
      _pois = results;
      _tripLoading = false;
      _tripSearched = true;
    });
    _drawTripPoiPins(results);
  }

  // ── Google Maps 내비게이션 ─────────────────────────────────────
  Future<void> _navigateToPoi(Poi poi) async {
    final home = context.read<HomeLocationService>().home;
    final loc = context.read<LocationService>();
    String url;
    if (home != null) {
      url = 'https://www.google.com/maps/dir/?api=1'
          '&origin=${loc.lat},${loc.lng}'
          '&destination=${home.lat},${home.lng}'
          '&waypoints=${poi.lat},${poi.lng}'
          '&travelmode=driving';
    } else {
      url = 'https://www.google.com/maps/dir/?api=1'
          '&origin=${loc.lat},${loc.lng}'
          '&destination=${poi.lat},${poi.lng}'
          '&travelmode=driving';
    }
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  // ── 집 설정 — 지도 중앙 핀 모드 진입 ──────────────────────────
  void _enterSetHomeMode() {
    setState(() => _settingHome = true);
    // 현재 위치로 지도 이동
    final loc = context.read<LocationService>();
    _mapController?.flyTo(
      mbx.CameraOptions(
        center: mbx.Point(
          coordinates: mbx.Position(loc.lng, loc.lat),
        ),
        zoom: 14.0,
      ),
      mbx.MapAnimationOptions(duration: 600),
    );
  }

  Future<void> _confirmSetHome() async {
    if (_mapController == null) return;
    try {
      final state = await _mapController!.getCameraState();
      final center = state.center.coordinates;
      final lat = center.lat.toDouble();
      final lng = center.lng.toDouble();
      await context
          .read<HomeLocationService>()
          .setHome(LatLng(lat, lng), name: '집');
      if (mounted) {
        setState(() => _settingHome = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('집 위치를 저장했어요.',
                style: GoogleFonts.rajdhani(fontSize: 14)),
            backgroundColor: AppColors.panel,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('[RoutesScreen] 집 위치 저장 오류: $e');
    }
  }

  void _cancelSetHome() {
    setState(() => _settingHome = false);
  }

  // ── 탭 전환 ───────────────────────────────────────────────────
  void _switchTab(int tab) {
    if (_tab == tab) return;
    setState(() => _tab = tab);
    if (tab == 1) {
      if (!_tripSearched) {
        _searchPois();
      } else {
        _drawTripPoiPins(_pois);
      }
    } else {
      // ROUTES 탭으로 복귀: 선택 루트 주변 POI 복원
      final sel = _routeSvc?.selectedRoute;
      if (sel != null) _drawPoiPins(sel);
    }
  }

  // ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final loc = context.read<LocationService>();

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Stack(
          children: [
            // 지도 — 전체 화면
            mbx.MapWidget(
              styleUri: MapboxService.cruiseStyle,
              cameraOptions: mbx.CameraOptions(
                center: mbx.Point(
                    coordinates: mbx.Position(loc.lng, loc.lat)),
                zoom: 10.0,
                pitch: 0,
              ),
              onMapCreated: _onMapCreated,
              onStyleLoadedListener: _onStyleLoaded,
            ),
            // HUD 상단
            const Positioned(top: 0, left: 0, right: 0, child: HudBar()),
            // 루트 계획 버튼 (ROUTES 탭에서만)
            if (_tab == 0)
              Positioned(
                top: 56,
                right: 12,
                child: GestureDetector(
                  onTap: () => RouteWizardSheet.show(context),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: AppColors.panel.withOpacity(0.92),
                      borderRadius: BorderRadius.circular(4),
                      border:
                          Border.all(color: AppColors.red.withOpacity(0.5)),
                    ),
                    child: Text(
                      '🗺 루트 계획',
                      style: GoogleFonts.rajdhani(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
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
                  top: 80,
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
            // 집 위치 지도 핀 모드 오버레이
            if (_settingHome)
              Positioned.fill(
                child: IgnorePointer(
                  ignoring: false,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // 중앙 핀
                      const Icon(Icons.location_pin,
                          color: AppColors.red, size: 48),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 5),
                        decoration: BoxDecoration(
                          color: AppColors.panel.withValues(alpha: 0.92),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                              color: AppColors.red.withValues(alpha: 0.6)),
                        ),
                        child: Text(
                          '지도를 움직여 집 위치를 맞춰요',
                          style: GoogleFonts.rajdhani(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            // 집 설정 확인/취소 버튼 (핀 모드일 때)
            if (_settingHome)
              Positioned(
                bottom: 24,
                left: 24,
                right: 24,
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: _cancelSetHome,
                        child: Container(
                          padding:
                              const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                            color: AppColors.panel,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                                color: Colors.white.withValues(alpha: 0.15)),
                          ),
                          child: Text(
                            '취소',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.rajdhani(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppColors.gray,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: GestureDetector(
                        onTap: _confirmSetHome,
                        child: Container(
                          padding:
                              const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                            color: AppColors.red,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '🏠  이 위치를 집으로',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.rajdhani(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: 1,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            // 하단 패널 (ROUTES / TRIP 탭) — 핀 모드에선 숨김
            // 최대 높이 52% 제한 → 지도가 항상 위쪽에 보이도록
            if (!_settingHome)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.52,
                ),
                child: SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  child: _BottomPanel(
                    tab: _tab,
                    onTabChange: _switchTab,
                    routesChild: Consumer<RouteService>(
                      builder: (context, svc, _) {
                        if (_styleLoaded && svc.routes.isNotEmpty) {
                          WidgetsBinding.instance.addPostFrameCallback(
                              (_) => _drawRoutes(svc.routes, svc.selectedRoute));
                        }
                        return const RoutesBottomSheet();
                      },
                    ),
                    tripChild: _TripPanel(
                      selectedCategory: _selectedCategory,
                      pois: _pois,
                      loading: _tripLoading,
                      onCategoryChange: (cat) {
                        setState(() => _selectedCategory = cat);
                        _searchPois();
                      },
                      onNavigate: _navigateToPoi,
                      onSetHome: _enterSetHomeMode,
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

// ── 하단 탭 패널 ──────────────────────────────────────────────────

class _BottomPanel extends StatelessWidget {
  final int tab;
  final ValueChanged<int> onTabChange;
  final Widget routesChild;
  final Widget tripChild;

  const _BottomPanel({
    required this.tab,
    required this.onTabChange,
    required this.routesChild,
    required this.tripChild,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.panel,
        border: Border(top: BorderSide(color: AppColors.divider, width: 1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 탭 헤더
          Row(
            children: [
              _TabBtn(
                label: '🗺  ROUTES',
                active: tab == 0,
                onTap: () => onTabChange(0),
              ),
              _TabBtn(
                label: '📍  TRIP',
                active: tab == 1,
                onTap: () => onTabChange(1),
              ),
            ],
          ),
          // 탭 내용
          tab == 0 ? routesChild : tripChild,
        ],
      ),
    );
  }
}

class _TabBtn extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _TabBtn(
      {required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: active ? AppColors.red : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: GoogleFonts.rajdhani(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: active ? Colors.white : AppColors.gray,
              letterSpacing: 2,
            ),
          ),
        ),
      ),
    );
  }
}

// ── TRIP 패널 ─────────────────────────────────────────────────────

class _TripPanel extends StatelessWidget {
  final PoiCategory selectedCategory;
  final List<Poi> pois;
  final bool loading;
  final ValueChanged<PoiCategory> onCategoryChange;
  final ValueChanged<Poi> onNavigate;
  final VoidCallback onSetHome;

  const _TripPanel({
    required this.selectedCategory,
    required this.pois,
    required this.loading,
    required this.onCategoryChange,
    required this.onNavigate,
    required this.onSetHome,
  });

  @override
  Widget build(BuildContext context) {
    final home = context.watch<HomeLocationService>();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 헤더
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '어디 들를까요?',
                    style: GoogleFonts.orbitron(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    home.isSet
                        ? '들를 곳 선택 → 집까지 경로 안내'
                        : '들를 곳 선택 → 내비게이션 연결',
                    style: GoogleFonts.rajdhani(
                        fontSize: 11, color: AppColors.gray),
                  ),
                ],
              ),
              const Spacer(),
              if (!home.isSet)
                GestureDetector(
                  onTap: onSetHome,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      border: Border.all(
                          color: AppColors.red.withOpacity(0.4)),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '🏠 집 설정',
                      style: GoogleFonts.rajdhani(
                          fontSize: 11, color: AppColors.gray),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        // 카테고리 칩
        SizedBox(
          height: 34,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: PoiCategory.values.map((cat) {
              final selected = cat == selectedCategory;
              return GestureDetector(
                onTap: () => onCategoryChange(cat),
                child: Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: selected ? AppColors.red : AppColors.surface,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: selected
                          ? AppColors.red
                          : AppColors.red.withOpacity(0.2),
                    ),
                  ),
                  child: Text(
                    '${cat.emoji} ${cat.label}',
                    style: GoogleFonts.rajdhani(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: selected ? Colors.white : AppColors.gray,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 10),
        // POI 목록
        SizedBox(
          height: 200,
          child: loading
              ? const Center(
                  child: CircularProgressIndicator(color: AppColors.red))
              : pois.isEmpty
                  ? Center(
                      child: Text(
                        '근처에 ${selectedCategory.label}을 찾지 못했어요',
                        style: GoogleFonts.rajdhani(
                            fontSize: 13, color: AppColors.gray),
                      ),
                    )
                  : ListView.builder(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: pois.length,
                      itemBuilder: (_, i) => _PoiTile(
                        poi: pois[i],
                        homeSet: home.isSet,
                        onTap: () => onNavigate(pois[i]),
                      ),
                    ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

// ── 폴리라인 탭 → 루트 선택 리스너 ────────────────────────────────

class _PolylineClickHandler extends mbx.OnPolylineAnnotationClickListener {
  final Map<String, RevvRoute> annotationToRoute;
  final void Function(RevvRoute) onSelect;

  _PolylineClickHandler(this.annotationToRoute, this.onSelect);

  @override
  bool onPolylineAnnotationClick(mbx.PolylineAnnotation annotation) {
    final route = annotationToRoute[annotation.id];
    if (route != null) {
      onSelect(route);
      return true; // 이벤트 소비
    }
    return false;
  }
}

class _PoiTile extends StatelessWidget {
  final Poi poi;
  final bool homeSet;
  final VoidCallback onTap;
  const _PoiTile(
      {required this.poi, required this.homeSet, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.bg,
          borderRadius: BorderRadius.circular(4),
          border:
              Border.all(color: AppColors.red.withOpacity(0.15)),
        ),
        child: Row(
          children: [
            Text(poi.category.emoji,
                style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    poi.name,
                    style: GoogleFonts.rajdhani(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    '${poi.distanceKm.toStringAsFixed(1)} km',
                    style: GoogleFonts.rajdhani(
                        fontSize: 11, color: AppColors.gray),
                  ),
                ],
              ),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.red,
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                homeSet ? '여기 → 집' : '여기로',
                style: GoogleFonts.rajdhani(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: 1,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
