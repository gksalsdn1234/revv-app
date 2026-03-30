import 'dart:convert';
import 'dart:math' as math;
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

  /// 커브 밀도 히트맵 모드 (파랑→초록→노랑→주황→빨강)
  final bool showCurveHeatmap;

  const MapWidget({
    super.key,
    this.isSprintMode = false,
    this.navPolyline,
    this.routePolyline,
    this.showCurveHeatmap = false,
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

  // ── FollowPuckViewportState: Mapbox 네이티브 위치 추적 ──────────
  // 수동 flyTo/easeTo 대신 SDK의 viewport 추적 기능 사용.
  // 스타일 로드 후 setState로 활성화 → SDK가 GPS 추적을 자동 처리.
  // 사용자 터치로 카메라 이탈 시에도 다음 GPS 업데이트로 재잠금.
  mbx.ViewportState? _viewportState;

  // ── 카메라 업데이트 1-프레임 격리 (viewport 비활성 구간 fallback) ──
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
      _viewportState = null; // 스타일 재로드 후 _onStyleLoaded에서 재활성화
    }

    if (_styleLoaded) {
      if (oldWidget.navPolyline != widget.navPolyline) {
        _drawPolyline('nav', widget.navPolyline ?? [], Colors.blue.value, 4.0);
      }
      if (oldWidget.routePolyline != widget.routePolyline ||
          oldWidget.showCurveHeatmap != widget.showCurveHeatmap) {
        if (widget.showCurveHeatmap && widget.routePolyline?.isNotEmpty == true) {
          _drawCurveHeatmap(widget.routePolyline!);
        } else {
          _clearHeatmap();
          _drawPolyline('route', widget.routePolyline ?? [], AppColors.red.value, 5.5);
        }
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
    // FollowPuckViewportState가 활성화돼 있으면 SDK가 자동 추적 → 수동 카메라 불필요.
    // 단, viewport가 아직 없거나 사용자가 이탈한 경우 수동 재잠금 (fallback).
    if (_viewportState != null) {
      // 사용자가 수동으로 지도를 이탈했을 때 GPS 업데이트마다 재잠금:
      // 새 ViewportState 인스턴스를 만들어 SDK equality 체크 통과 → transition 재호출
      if (!_cameraPending) {
        _cameraPending = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _cameraPending = false;
          if (!mounted || !_styleLoaded) return;
          setState(() {
            _viewportState = mbx.FollowPuckViewportState(
              zoom: widget.isSprintMode ? 16.5 : 15.0,
              pitch: widget.isSprintMode ? 50.0 : 20.0,
              bearing: const mbx.FollowPuckViewportStateBearingHeading(),
            );
          });
        });
      }
      return;
    }
    // viewport 비활성 구간 fallback: 수동 카메라 이동
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
    await _applyCustomStyle();
    // FollowPuckViewportState 활성화: 스타일 로드 완료 후 SDK 네이티브 추적 시작
    setState(() {
      _viewportState = mbx.FollowPuckViewportState(
        zoom: widget.isSprintMode ? 16.5 : 15.0,
        pitch: widget.isSprintMode ? 50.0 : 20.0,
        bearing: const mbx.FollowPuckViewportStateBearingHeading(),
      );
    });
    // 폴리라인 재그리기 (스타일 재로드 시)
    if (widget.navPolyline?.isNotEmpty == true) {
      await _drawPolyline('nav', widget.navPolyline!, Colors.blue.value, 4.0);
    }
    if (widget.routePolyline?.isNotEmpty == true) {
      if (widget.showCurveHeatmap) {
        await _drawCurveHeatmap(widget.routePolyline!);
      } else {
        await _drawPolyline('route', widget.routePolyline!, AppColors.red.value, 5.5);
      }
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

  // ── 커브 히트맵 레이어 ────────────────────────────────────────────
  static const _hmIds = ['hm-straight', 'hm-gentle', 'hm-medium', 'hm-tight'];
  static const _hmColors = [0xFF3B82F6, 0xFF22C55E, 0xFFF59E0B, 0xFFEF4444];

  Future<void> _clearHeatmap() async {
    final map = _mapController;
    if (map == null) return;
    for (final id in _hmIds) {
      try { await map.style.removeStyleLayer('$id-layer'); } catch (_) {}
      try { await map.style.removeStyleSource('$id-source'); } catch (_) {}
    }
  }

  static double _bearing(double lat1d, double lon1d, double lat2d, double lon2d) {
    final lat1 = lat1d * math.pi / 180;
    final lat2 = lat2d * math.pi / 180;
    final dLon = (lon2d - lon1d) * math.pi / 180;
    final y = math.sin(dLon) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLon);
    return math.atan2(y, x) * 180 / math.pi;
  }

  static double _bearingDiff(double b1, double b2) {
    final d = (b2 - b1).abs();
    return d > 180 ? 360 - d : d;
  }

  static double _haversineKm(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371.0;
    final dLat = (lat2 - lat1) * math.pi / 180;
    final dLon = (lon2 - lon1) * math.pi / 180;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180) * math.cos(lat2 * math.pi / 180) *
            math.sin(dLon / 2) * math.sin(dLon / 2);
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  // bucket: 0=straight(blue) 1=gentle(green) 2=medium(amber) 3=tight(red)
  static int _curveBucket(double ratePerKm) {
    if (ratePerKm < 60) return 0;
    if (ratePerKm < 200) return 1;
    if (ratePerKm < 400) return 2;
    return 3;
  }

  Future<void> _drawCurveHeatmap(List<LatLng> nodes) async {
    final map = _mapController;
    if (map == null || !_styleLoaded || nodes.length < 3) return;

    // Remove existing route + heatmap layers
    try { await map.style.removeStyleLayer('route-layer'); } catch (_) {}
    try { await map.style.removeStyleLayer('route-casing-layer'); } catch (_) {}
    try { await map.style.removeStyleSource('route-source'); } catch (_) {}
    await _clearHeatmap();

    // Build 4 bucket FeatureCollections (each bucket = list of LineString coordinates)
    final buckets = List.generate(4, (_) => <List<List<double>>>[]);
    List<List<double>>? curSeg;
    int curBucket = -1;

    for (int i = 0; i < nodes.length - 1; i++) {
      final n = nodes[i];
      final n1 = nodes[i + 1];

      // Compute curvature rate at node i (use i-1..i..i+1 bearing change)
      int bucket = 1; // default gentle
      if (i > 0 && i < nodes.length - 2) {
        final prev = nodes[i - 1];
        final b1 = _bearing(prev.lat, prev.lng, n.lat, n.lng);
        final b2 = _bearing(n.lat, n.lng, n1.lat, n1.lng);
        final dist = _haversineKm(prev.lat, prev.lng, n1.lat, n1.lng);
        final rate = dist > 0.00001 ? _bearingDiff(b1, b2) / dist : 0.0;
        bucket = _curveBucket(rate);
      }

      if (bucket != curBucket) {
        if (curSeg != null && curSeg.length >= 2) {
          buckets[curBucket].add(curSeg);
        }
        curBucket = bucket;
        curSeg = [[n.lng, n.lat]];
      }
      curSeg!.add([n1.lng, n1.lat]);
    }
    if (curSeg != null && curSeg.length >= 2) {
      buckets[curBucket].add(curSeg);
    }

    // Draw each bucket as one GeoJSON FeatureCollection
    for (int b = 0; b < 4; b++) {
      if (buckets[b].isEmpty) continue;
      final features = buckets[b].map((coords) => {
        'type': 'Feature',
        'geometry': {'type': 'LineString', 'coordinates': coords},
        'properties': {},
      }).toList();
      final geoJson = jsonEncode({'type': 'FeatureCollection', 'features': features});
      final sourceId = '${_hmIds[b]}-source';
      final layerId = '${_hmIds[b]}-layer';
      try {
        await map.style.addSource(mbx.GeoJsonSource(id: sourceId, data: geoJson));
        await map.style.addLayer(mbx.LineLayer(
          id: layerId,
          sourceId: sourceId,
          lineColor: _hmColors[b],
          lineWidth: 5.5,
          lineOpacity: 1.0,
          lineCap: mbx.LineCap.ROUND,
          lineJoin: mbx.LineJoin.ROUND,
        ));
      } catch (e) {
        debugPrint('[MapWidget] heatmap bucket $b: $e');
      }
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
        position: mbx.OrnamentPosition.BOTTOM_RIGHT,
        marginBottom: 120,
        marginRight: 14,
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
      // FollowPuckViewportState: 스타일 로드 후 활성화 → Mapbox 네이티브 GPS 추적
      viewport: _viewportState,
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
