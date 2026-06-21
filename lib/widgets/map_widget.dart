import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mbx;
import 'package:provider/provider.dart';
import '../models/revv_route.dart';
import '../services/location_service.dart';
import '../services/mapbox_service.dart';
import '../services/weather_service.dart';
import '../theme/colors.dart';

class MapWidget extends StatefulWidget {
  final bool isSprintMode;
  /// 현재위치 → 루트 시작점 내비 경로 (파란 선)
  final List<LatLng>? navPolyline;
  /// 선택한 드라이빙 루트 (빨간 선)
  final List<LatLng>? routePolyline;

  const MapWidget({
    super.key,
    this.isSprintMode = false,
    this.navPolyline,
    this.routePolyline,
  });

  @override
  State<MapWidget> createState() => _MapWidgetState();
}

class _MapWidgetState extends State<MapWidget> {
  mbx.MapboxMap? _mapController;
  mbx.PointAnnotationManager? _annotationManager;
  bool _styleLoaded = false;
  bool _locationPuckEnabled = false;
  LocationService? _locationService;

  // ── 카메라 업데이트 1-프레임 격리 ──────────────────────────────
  // LocationService notifyListeners (post-frame) → 모든 리스너 동기 실행:
  //   MapWidget._onLocationChanged → _moveCamera (Mapbox 네이티브 호출)
  //   SprintScreen._onLocation → setState (다음 프레임 dirty 마킹)
  // 문제: _moveCamera의 platform view 업데이트가 다음 프레임 layout 중 도착
  //   → !_debugDoingThisLayout assertion
  // 해결: 카메라 업데이트를 별도 addPostFrameCallback으로 1프레임 격리
  //   → setState 트리거 layout이 완전히 끝난 후 카메라 이동
  bool _cameraPending = false;

  @override
  void initState() {
    super.initState();
    mbx.MapboxOptions.setAccessToken(MapboxService.accessToken);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final loc = context.read<LocationService>();
    if (_locationService != loc) {
      _locationService?.removeListener(_onLocationChanged);
      _locationService = loc;
      _locationService!.addListener(_onLocationChanged);
    }
  }

  @override
  void didUpdateWidget(MapWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Sprint 모드 전환 시 스타일 URI가 바뀌어 Mapbox가 스타일을 재로드함
    // → _styleLoaded를 false로 초기화해야 _onStyleLoaded 재호출 대기
    if (oldWidget.isSprintMode != widget.isSprintMode) {
      _styleLoaded = false;
      _locationPuckEnabled = false;
    }

    if (_styleLoaded) {
      if (oldWidget.navPolyline != widget.navPolyline) {
        _drawPolyline('nav', widget.navPolyline ?? [], Colors.blue.value, 4.0);
      }
      if (oldWidget.routePolyline != widget.routePolyline) {
        _drawPolyline('route', widget.routePolyline ?? [], AppColors.orange.value, 5.5);
      }
    }
    // 스타일 재로드 중(_styleLoaded=false)에 polyline 변경이 오면
    // _onStyleLoaded가 완료될 때 widget의 최신값을 자동으로 그림
  }

  @override
  void dispose() {
    _locationService?.removeListener(_onLocationChanged);
    super.dispose();
  }

  void _onLocationChanged() {
    if (_locationService == null || !_styleLoaded) return;
    // 카메라 업데이트를 다음 프레임 post-frame으로 격리:
    // 현재 post-frame 사이클의 setState 들이 유발하는 layout이
    // 완전히 끝난 후 Mapbox 네이티브 호출 실행
    if (!_cameraPending) {
      _cameraPending = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _cameraPending = false;
        if (!mounted || !_styleLoaded) return;
        final loc = _locationService;
        if (loc != null) {
          _moveCamera(loc.lat, loc.lng, heading: loc.heading);
        }
      });
    }
  }

  void _onMapCreated(mbx.MapboxMap controller) {
    _mapController = controller;
  }

  Future<void> _onStyleLoaded(mbx.StyleLoadedEventData _) async {
    _styleLoaded = true;
    _locationPuckEnabled = false;
    _annotationManager =
        await _mapController?.annotations.createPointAnnotationManager();
    final loc = context.read<LocationService>();
    await _applyCustomStyle();
    await _moveCamera(loc.lat, loc.lng, heading: loc.heading, immediate: true);
    // 폴리라인 재그리기 (스타일 재로드 시)
    if (widget.navPolyline?.isNotEmpty == true) {
      await _drawPolyline('nav', widget.navPolyline!, Colors.blue.value, 4.0);
    }
    if (widget.routePolyline?.isNotEmpty == true) {
      await _drawPolyline('route', widget.routePolyline!, AppColors.red.value, 5.5);
    }
  }

  Future<void> _drawPolyline(
      String id, List<LatLng> points, int colorArgb, double width) async {
    final map = _mapController;
    if (map == null || !_styleLoaded) return;

    final sourceId = '$id-source';
    final casingId = '$id-casing-layer';
    final layerId = '$id-layer';

    try { await map.style.removeStyleLayer(layerId); } catch (_) {}
    try { await map.style.removeStyleLayer(casingId); } catch (_) {}
    try { await map.style.removeStyleSource(sourceId); } catch (_) {}

    if (points.isEmpty) return;

    final geoJson = jsonEncode({
      'type': 'Feature',
      'geometry': {
        'type': 'LineString',
        'coordinates': points.map((p) => [p.lng, p.lat]).toList(),
      },
      'properties': {},
    });

    try {
      await map.style.addSource(mbx.GeoJsonSource(id: sourceId, data: geoJson));
      // 검정 테두리 (casing) — 지도 배경과 구분
      await map.style.addLayer(mbx.LineLayer(
        id: casingId,
        sourceId: sourceId,
        lineColor: 0xFF000000,
        lineWidth: width + 3.0,
        lineOpacity: 0.85,
        lineCap: mbx.LineCap.ROUND,
        lineJoin: mbx.LineJoin.ROUND,
      ));
      // 메인 색상 레이어
      await map.style.addLayer(mbx.LineLayer(
        id: layerId,
        sourceId: sourceId,
        lineColor: colorArgb,
        lineWidth: width,
        lineOpacity: 1.0,
        lineCap: mbx.LineCap.ROUND,
        lineJoin: mbx.LineJoin.ROUND,
      ));
    } catch (e) {
      debugPrint('[MapWidget] polyline $id: $e');
    }
  }

  Future<void> _applyCustomStyle() async {
    final map = _mapController;
    if (map == null) return;

    // ── 나침반 ──────────────────────────────────────────────────────
    try {
      await map.compass.updateSettings(mbx.CompassSettings(
        enabled: true,
        opacity: 0.85,
      ));
    } catch (e) {
      debugPrint('[MapWidget] compass: $e');
    }

    // ── 위치 표시: 방향 화살표 + pulsing ───────────────────────────
    try {
      await map.location.updateSettings(mbx.LocationComponentSettings(
        enabled: true,
        pulsingEnabled: widget.isSprintMode,
        pulsingColor: widget.isSprintMode
            ? AppColors.red.withOpacity(0.35).value
            : 0xFF1E90FF,
        locationPuck: mbx.LocationPuck(
          locationPuck2D: mbx.LocationPuck2D(),
        ),
      ));
      _locationPuckEnabled = true;
    } catch (e) {
      debugPrint('[MapWidget] location layer: $e');
    }

    // ── 스타일 설정 (라이트/라벨 등) ──────────────────────────────
    if (!widget.isSprintMode) {
      for (final entry in {
        'showPointOfInterestLabels': false,
        'showTransitLabels': false,
        'showRoadLabels': true,
        'showPlaceLabels': false,
        'lightPreset': 'night',
      }.entries) {
        try {
          await map.style.setStyleImportConfigProperty(
              'basemap', entry.key, entry.value);
        } catch (_) {}
      }
    }
  }

  Future<void> _moveCamera(double lat, double lng,
      {double? heading, bool immediate = false}) async {
    if (!_styleLoaded || _mapController == null) return;

    final cameraOpts = mbx.CameraOptions(
      center: mbx.Point(coordinates: mbx.Position(lng, lat)),
      zoom: widget.isSprintMode ? 16.5 : 15.0,
      pitch: widget.isSprintMode ? 50.0 : 20.0,
      bearing: (widget.isSprintMode && heading != null) ? heading : null,
    );

    if (immediate) {
      // 즉각 이동 (스타일 로드 시 초기 위치)
      try { await _mapController!.setCamera(cameraOpts); } catch (_) {}
    } else if (widget.isSprintMode) {
      // Sprint 모드: 부드럽고 빠른 카메라 추적 (easeTo)
      try {
        await _mapController!.easeTo(
          cameraOpts,
          mbx.MapAnimationOptions(duration: 300),
        );
      } catch (_) {}
    } else {
      // Cruise 모드: flyTo (느린 이동 OK)
      try {
        await _mapController!.flyTo(
          cameraOpts,
          mbx.MapAnimationOptions(duration: 700),
        );
      } catch (_) {}
    }

    // LocationPuck이 비활성화됐으면 재활성화
    if (!_locationPuckEnabled && _styleLoaded) {
      try {
        await _mapController!.location.updateSettings(
          mbx.LocationComponentSettings(
            enabled: true,
            pulsingEnabled: widget.isSprintMode,
            locationPuck: mbx.LocationPuck(
              locationPuck2D: mbx.LocationPuck2D(),
            ),
          ),
        );
        _locationPuckEnabled = true;
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasPermission =
        context.select<LocationService, bool>((loc) => loc.hasPermission);

    if (!hasPermission) {
      return _MapFallback();
    }

    final loc = context.read<LocationService>();
    final weatherIcon = context.read<WeatherService>().weatherIcon;

    // ⚠ TLHC_VD + textureView: 에뮬레이터 GFXSTREAM 충돌 해결
    // 기본 HybridComposition은 SurfaceView를 Flutter 뷰 계층에 직접 임베드 →
    // 에뮬레이터에서 플랫폼 뷰 레이아웃 업데이트가 Flutter layout phase 중 발생 →
    // !_debugDoingThisLayout assertion + touch 먹통 유발.
    // TLHC_VD(Texture Layer Hybrid Composition + VirtualDisplay fallback) +
    // textureView=true → 텍스처 기반 합성으로 layout phase 간섭 차단.
    return mbx.MapWidget(
      styleUri: widget.isSprintMode
          ? MapboxService.sprintStyle(weatherIcon)
          : MapboxService.cruiseStyle,
      cameraOptions: mbx.CameraOptions(
        center: mbx.Point(coordinates: mbx.Position(loc.lng, loc.lat)),
        zoom: widget.isSprintMode ? 16.5 : 15.0,
        pitch: widget.isSprintMode ? 50.0 : 20.0,
      ),
      androidHostingMode: mbx.AndroidPlatformViewHostingMode.TLHC_VD,
      textureView: true,
      onMapCreated: _onMapCreated,
      onStyleLoadedListener: _onStyleLoaded,
    );
  }
}

class _MapFallback extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0D1117),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.location_off,
                color: AppColors.red.withOpacity(0.5), size: 32),
            const SizedBox(height: 8),
            Text(
              '위치 권한이 필요해요',
              style: TextStyle(
                color: AppColors.white.withOpacity(0.4),
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
