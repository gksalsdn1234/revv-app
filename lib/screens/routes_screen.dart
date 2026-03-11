import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mbx;
import 'package:provider/provider.dart';
import '../theme/colors.dart';
import '../widgets/hud_bar.dart';
import '../widgets/routes_bottom_sheet.dart';
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
  mbx.MapboxMap? _mapController;
  mbx.PolylineAnnotationManager? _polyManager;
  final List<mbx.PolylineAnnotation> _polylines = [];
  bool _styleLoaded = false;
  bool _isDrawing = false;
  RouteService? _routeSvc; // dispose()에서 context 없이 접근하기 위해 저장

  @override
  void initState() {
    super.initState();
    mbx.MapboxOptions.setAccessToken(MapboxService.accessToken);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final loc = context.read<LocationService>();
      _routeSvc = context.read<RouteService>();
      _routeSvc!.resetCache();
      _routeSvc!.fetchRoutes(loc.lat, loc.lng);
      _routeSvc!.addListener(_onRouteServiceChanged);
    });
  }

  @override
  void dispose() {
    _routeSvc?.removeListener(_onRouteServiceChanged);
    super.dispose();
  }

  void _onRouteServiceChanged() {
    if (!mounted || _routeSvc == null) return;
    if (_styleLoaded && !_routeSvc!.isLoading) {
      _drawRoutes(_routeSvc!.routes, _routeSvc!.selectedRoute);
    }
  }

  void _onMapCreated(mbx.MapboxMap controller) {
    _mapController = controller;
  }

  Future<void> _onStyleLoaded(mbx.StyleLoadedEventData _) async {
    _styleLoaded = true;
    _polyManager =
        await _mapController?.annotations.createPolylineAnnotationManager();

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

  Future<void> _drawRoutes(
      List<RevvRoute> routes, RevvRoute? selected) async {
    if (!_styleLoaded || _polyManager == null || _isDrawing) return;
    _isDrawing = true;

    try {
      // 기존 라인 전체 삭제 후 재생성
      await _polyManager!.deleteAll();
      _polylines.clear();

      // 비선택 루트 먼저 그리기 (선택 루트가 위에 오도록)
      final unselected = routes.where((r) => r.id != selected?.id).toList();
      final selectedList =
          routes.where((r) => r.id == selected?.id).toList();

      for (final route in [...unselected, ...selectedList]) {
        final isSel = route.id == selected?.id;
        final coords =
            route.nodes.map((n) => mbx.Position(n.lng, n.lat)).toList();

        final poly = await _polyManager!.create(
          mbx.PolylineAnnotationOptions(
            geometry: mbx.LineString(coordinates: coords),
            lineColor: isSel ? AppColors.red.value : 0xFFFFFFFF,
            lineWidth: isSel ? 5.0 : 2.0,
            lineOpacity: isSel ? 1.0 : 0.3,
          ),
        );
        _polylines.add(poly);
      }

      // 선택된 루트로 카메라 이동
      if (selected != null) {
        await _mapController?.flyTo(
          mbx.CameraOptions(
            center: mbx.Point(
              coordinates: mbx.Position(
                  selected.centerPoint.lng, selected.centerPoint.lat),
            ),
            zoom: 11.0,
            pitch: 0,
          ),
          mbx.MapAnimationOptions(duration: 800),
        );
      }
    } finally {
      _isDrawing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.read<LocationService>();

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Stack(
          children: [
            // 지도 — Consumer 밖에 위치, 재생성 안 됨
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
            // 루트 계획 버튼
            Positioned(
              top: 56,
              right: 12,
              child: GestureDetector(
                onTap: () => RouteWizardSheet.show(context),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: AppColors.panel.withOpacity(0.92),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: AppColors.red.withOpacity(0.5)),
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
            // 하단 시트 — 루트 선택 시 폴리라인도 업데이트
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Consumer<RouteService>(
                builder: (context, svc, _) {
                  // 루트 선택 변경 시 폴리라인 업데이트
                  if (_styleLoaded && svc.routes.isNotEmpty) {
                    WidgetsBinding.instance.addPostFrameCallback(
                        (_) => _drawRoutes(svc.routes, svc.selectedRoute));
                  }
                  return const RoutesBottomSheet();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
