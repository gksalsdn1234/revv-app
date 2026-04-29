import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mbx;
import 'package:provider/provider.dart';
import '../models/revv_route.dart';
import '../services/location_service.dart';
import '../services/mapbox_service.dart';
import '../services/weather_service.dart';
import '../theme/colors.dart';

class _LineLayerSpec {
  final String id;
  final String sourceId;
  final int color;
  final double width;
  final double opacity;

  const _LineLayerSpec({
    required this.id,
    required this.sourceId,
    required this.color,
    required this.width,
    required this.opacity,
  });
}

class MapWidget extends StatefulWidget {
  final bool isSprintMode;

  /// 현재위치 → 루트 시작점 내비 경로 (파란 선)
  final List<LatLng>? navPolyline;

  /// 선택한 드라이빙 루트 (빨간 선)
  final List<LatLng>? routePolyline;

  /// 커브 밀도 히트맵 모드 (파랑→초록→노랑→주황→빨강)
  final bool showCurveHeatmap;

  /// 본 루트 진입 후 지도 배경 정보를 최소화하고 루트만 강조한다.
  final bool routeFocusMode;
  final int recenterSignal;

  const MapWidget({
    super.key,
    this.isSprintMode = false,
    this.navPolyline,
    this.routePolyline,
    this.showCurveHeatmap = false,
    this.routeFocusMode = false,
    this.recenterSignal = 0,
  });

  @override
  State<MapWidget> createState() => _MapWidgetState();
}

class _MapWidgetState extends State<MapWidget> {
  static const bool _disableMapbox = bool.fromEnvironment(
    'REVV_DISABLE_MAPBOX',
  );

  mbx.MapboxMap? _mapController;
  bool _styleLoaded = false;
  bool _locationPuckEnabled = false;
  LocationService? _locationService;

  // ── FollowPuckViewportState 비활성화 ──────────
  // iOS 실기기에서 스타일 로드 직후 viewport setState + location puck 조합이
  // 네이티브 EXC_BAD_ACCESS로 이어지는 케이스가 있어 수동 카메라 추적으로 고정한다.
  mbx.ViewportState? _viewportState;

  // ── 카메라 업데이트 1-프레임 격리 (viewport 비활성 구간 fallback) ──
  bool _cameraPending = false;
  final Map<String, Object?> _originalLayerVisibility = {};
  bool _routeFocusApplied = false;
  Uint8List? _puckTopImage;
  Uint8List? _puckBearingImage;
  Uint8List? _puckShadowImage;

  List<_LineLayerSpec> _buildLineLayers(
    String id,
    String sourceId,
    int colorArgb,
    double width,
  ) {
    final isRoute = id == 'route';
    final isNav = id == 'nav';

    if (isRoute) {
      return [
        _LineLayerSpec(
          id: '$id-shadow-layer',
          sourceId: sourceId,
          color: 0xCC05080D,
          width: width + 7.0,
          opacity: widget.routeFocusMode ? 0.96 : 0.90,
        ),
        _LineLayerSpec(
          id: '$id-track-layer',
          sourceId: sourceId,
          color: widget.routeFocusMode ? 0xFF0E2932 : 0xFF12242C,
          width: width + 2.4,
          opacity: 0.98,
        ),
        _LineLayerSpec(
          id: '$id-core-layer',
          sourceId: sourceId,
          color: widget.routeFocusMode ? 0xFF29E0FF : 0xFF19C8E6,
          width: width,
          opacity: 0.96,
        ),
        _LineLayerSpec(
          id: '$id-ribbon-layer',
          sourceId: sourceId,
          color: 0xFFEBFCFF,
          width: math.max(1.4, width * 0.28),
          opacity: widget.routeFocusMode ? 0.42 : 0.30,
        ),
      ];
    }

    if (isNav) {
      return [
        _LineLayerSpec(
          id: '$id-shadow-layer',
          sourceId: sourceId,
          color: 0x99060A10,
          width: width + 5.0,
          opacity: 0.82,
        ),
        _LineLayerSpec(
          id: '$id-track-layer',
          sourceId: sourceId,
          color: 0xFF1E2D4B,
          width: width + 1.8,
          opacity: 0.88,
        ),
        _LineLayerSpec(
          id: '$id-core-layer',
          sourceId: sourceId,
          color: 0xFF6DA3FF,
          width: width,
          opacity: 0.88,
        ),
        _LineLayerSpec(
          id: '$id-ribbon-layer',
          sourceId: sourceId,
          color: 0xFFDDEAFF,
          width: math.max(1.2, width * 0.22),
          opacity: 0.24,
        ),
      ];
    }

    return [
      _LineLayerSpec(
        id: '$id-shadow-layer',
        sourceId: sourceId,
        color: 0xCC000000,
        width: width + 3.0,
        opacity: 0.85,
      ),
      _LineLayerSpec(
        id: '$id-core-layer',
        sourceId: sourceId,
        color: colorArgb,
        width: width,
        opacity: 1.0,
      ),
    ];
  }

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
      _routeFocusApplied = false;
      _originalLayerVisibility.clear();
    }

    if (_styleLoaded) {
      if (oldWidget.recenterSignal != widget.recenterSignal) {
        _recenterOnUser();
      }
      if (oldWidget.routeFocusMode != widget.routeFocusMode) {
        _applyRouteFocusStyle();
        if (widget.routeFocusMode) {
          _drawPolyline('nav', const [], Colors.blue.toARGB32(), 4.0);
        } else if (widget.navPolyline?.isNotEmpty == true) {
          _drawPolyline(
            'nav',
            widget.navPolyline!,
            Colors.blue.toARGB32(),
            4.0,
          );
        }
        if (widget.routePolyline?.isNotEmpty == true &&
            !widget.showCurveHeatmap) {
          _drawPolyline(
            'route',
            widget.routePolyline!,
            AppColors.red.toARGB32(),
            5.5,
          );
        }
      }
      if (oldWidget.navPolyline != widget.navPolyline) {
        _drawPolyline(
          'nav',
          widget.routeFocusMode ? const [] : widget.navPolyline ?? [],
          Colors.blue.toARGB32(),
          4.0,
        );
      }
      if (oldWidget.routePolyline != widget.routePolyline ||
          oldWidget.showCurveHeatmap != widget.showCurveHeatmap) {
        if (widget.showCurveHeatmap &&
            widget.routePolyline?.isNotEmpty == true) {
          _drawCurveHeatmap(widget.routePolyline!);
        } else {
          _clearHeatmap();
          _drawPolyline(
            'route',
            widget.routePolyline ?? [],
            AppColors.red.toARGB32(),
            5.5,
          );
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
    // FollowPuckViewportState가 활성화돼 있으면 SDK가 자동 추적한다.
    // GPS 업데이트마다 viewport를 다시 생성하면 platform view 전체가 재빌드돼
    // 실기기에서 지도 프레임이 쉽게 떨어진다.
    if (_viewportState != null) {
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

  Future<Uint8List> _drawPuckImage({
    required double size,
    required void Function(Canvas canvas, Size size) painter,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final imageSize = Size(size, size);
    painter(canvas, imageSize);
    final picture = recorder.endRecording();
    final image = await picture.toImage(size.round(), size.round());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return bytes!.buffer.asUint8List();
  }

  Future<void> _ensureCustomPuckImages() async {
    if (_puckTopImage != null &&
        _puckBearingImage != null &&
        _puckShadowImage != null) {
      return;
    }

    _puckTopImage = await _drawPuckImage(
      size: 72,
      painter: (canvas, size) {
        final center = Offset(size.width / 2, size.height / 2);

        final ringPaint = Paint()
          ..color = const Color(0xFF12161C).withValues(alpha: 0.94)
          ..style = PaintingStyle.fill;
        final ringStroke = Paint()
          ..color = const Color(0x5537DFFF)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3;
        final corePaint = Paint()
          ..shader = ui.Gradient.radial(
            center,
            size.width * 0.24,
            const [Color(0xFF9CF3FF), Color(0xFF43D9FF)],
          );

        canvas.drawCircle(center, size.width * 0.18, ringPaint);
        canvas.drawCircle(center, size.width * 0.18, ringStroke);
        canvas.drawCircle(center, size.width * 0.10, corePaint);
      },
    );

    _puckBearingImage = await _drawPuckImage(
      size: 96,
      painter: (canvas, size) {
        final centerX = size.width / 2;
        final centerY = size.height / 2;
        final path = Path()
          ..moveTo(centerX, size.height * 0.08)
          ..lineTo(size.width * 0.77, size.height * 0.72)
          ..quadraticBezierTo(
            centerX,
            size.height * 0.60,
            size.width * 0.23,
            size.height * 0.72,
          )
          ..close();

        final glowPaint = Paint()
          ..color = const Color(0x3343D9FF)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
        final fillPaint = Paint()
          ..shader = ui.Gradient.linear(
            Offset(centerX, size.height * 0.10),
            Offset(centerX, size.height * 0.75),
            const [Color(0xFFB8F7FF), Color(0xFF26D7FF)],
          );
        final strokePaint = Paint()
          ..color = const Color(0xFF10151D)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..strokeJoin = StrokeJoin.round;

        canvas.drawPath(path, glowPaint);
        canvas.drawPath(path, fillPaint);
        canvas.drawPath(path, strokePaint);

        final center = Offset(centerX, centerY);
        final ring = Paint()
          ..color = const Color(0xE0141820);
        final ringStroke = Paint()
          ..color = const Color(0x8837DFFF)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5;
        canvas.drawCircle(center, size.width * 0.11, ring);
        canvas.drawCircle(center, size.width * 0.11, ringStroke);
      },
    );

    _puckShadowImage = await _drawPuckImage(
      size: 110,
      painter: (canvas, size) {
        final center = Offset(size.width / 2, size.height / 2);
        final shadowPaint = Paint()
          ..color = const Color(0x4417D9FF)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18);
        canvas.drawCircle(center, size.width * 0.18, shadowPaint);

        final haloPaint = Paint()
          ..shader = ui.Gradient.radial(
            center,
            size.width * 0.30,
            const [
              Color(0x2234E6FF),
              Color(0x08131A22),
              Color(0x00000000),
            ],
          );
        canvas.drawCircle(center, size.width * 0.28, haloPaint);
      },
    );
  }

  Future<void> _updateLocationSettings() async {
    final map = _mapController;
    if (map == null) return;
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      await map.location.updateSettings(
        mbx.LocationComponentSettings(
          enabled: true,
          pulsingEnabled: widget.isSprintMode,
          pulsingColor: widget.isSprintMode
              ? AppColors.red.withValues(alpha: 0.22).toARGB32()
              : const Color(0x3326D7FF).toARGB32(),
        ),
      );
      _locationPuckEnabled = true;
      return;
    }

    await _ensureCustomPuckImages();
    await map.location.updateSettings(
      mbx.LocationComponentSettings(
        enabled: true,
        pulsingEnabled: widget.isSprintMode,
        pulsingColor: widget.isSprintMode
            ? AppColors.red.withValues(alpha: 0.28).toARGB32()
            : const Color(0x3326D7FF).toARGB32(),
        locationPuck: mbx.LocationPuck(
          locationPuck2D: mbx.DefaultLocationPuck2D(
            topImage: _puckTopImage,
            bearingImage: _puckBearingImage,
            shadowImage: _puckShadowImage,
            opacity: 1.0,
          ),
        ),
      ),
    );
    _locationPuckEnabled = true;
  }

  void _activateFollowViewport() {
    final loc = _locationService;
    if (loc == null) return;
    _viewportState = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_styleLoaded) return;
      _moveCamera(loc.lat, loc.lng, heading: loc.heading, immediate: true);
    });
  }

  void _recenterOnUser() {
    final loc = _locationService;
    if (loc == null || !_styleLoaded) return;
    _activateFollowViewport();
    _moveCamera(loc.lat, loc.lng, heading: loc.heading, immediate: true);
  }

  Future<void> _onStyleLoaded(mbx.StyleLoadedEventData _) async {
    _styleLoaded = true;
    _locationPuckEnabled = false;
    _routeFocusApplied = false;
    _originalLayerVisibility.clear();
    await _applyCustomStyle();
    // 스타일 로드 완료 후 카메라를 현재 위치로 맞춘다.
    _activateFollowViewport();
    // 폴리라인 재그리기 (스타일 재로드 시)
    if (!widget.routeFocusMode && widget.navPolyline?.isNotEmpty == true) {
      await _drawPolyline(
        'nav',
        widget.navPolyline!,
        Colors.blue.toARGB32(),
        4.0,
      );
    }
    if (widget.routePolyline?.isNotEmpty == true) {
      if (widget.showCurveHeatmap) {
        await _drawCurveHeatmap(widget.routePolyline!);
      } else {
        await _drawPolyline(
          'route',
          widget.routePolyline!,
          AppColors.red.toARGB32(),
          5.5,
        );
      }
    }
  }

  Future<void> _drawPolyline(
    String id,
    List<LatLng> points,
    int colorArgb,
    double width,
  ) async {
    final map = _mapController;
    if (map == null || !_styleLoaded) return;

    final sourceId = '$id-source';
    final layerIds = [
      '$id-ribbon-layer',
      '$id-core-layer',
      '$id-track-layer',
      '$id-shadow-layer',
      '$id-layer',
      '$id-casing-layer',
    ];

    for (final layerId in layerIds) {
      try {
        await map.style.removeStyleLayer(layerId);
      } catch (_) {}
    }
    try {
      await map.style.removeStyleSource(sourceId);
    } catch (_) {}

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
      for (final layer in _buildLineLayers(id, sourceId, colorArgb, width)) {
        await map.style.addLayer(
          mbx.LineLayer(
            id: layer.id,
            sourceId: layer.sourceId,
            lineColor: layer.color,
            lineWidth: layer.width,
            lineOpacity: layer.opacity,
            lineCap: mbx.LineCap.ROUND,
            lineJoin: mbx.LineJoin.ROUND,
          ),
        );
      }
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
      try {
        await map.style.removeStyleLayer('$id-layer');
      } catch (_) {}
      try {
        await map.style.removeStyleSource('$id-source');
      } catch (_) {}
    }
  }

  static double _bearing(
    double lat1d,
    double lon1d,
    double lat2d,
    double lon2d,
  ) {
    final lat1 = lat1d * math.pi / 180;
    final lat2 = lat2d * math.pi / 180;
    final dLon = (lon2d - lon1d) * math.pi / 180;
    final y = math.sin(dLon) * math.cos(lat2);
    final x =
        math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLon);
    return math.atan2(y, x) * 180 / math.pi;
  }

  static double _bearingDiff(double b1, double b2) {
    final d = (b2 - b1).abs();
    return d > 180 ? 360 - d : d;
  }

  static double _haversineKm(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const r = 6371.0;
    final dLat = (lat2 - lat1) * math.pi / 180;
    final dLon = (lon2 - lon1) * math.pi / 180;
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180) *
            math.cos(lat2 * math.pi / 180) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
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
    try {
      await map.style.removeStyleLayer('route-layer');
    } catch (_) {}
    try {
      await map.style.removeStyleLayer('route-casing-layer');
    } catch (_) {}
    try {
      await map.style.removeStyleSource('route-source');
    } catch (_) {}
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
        curSeg = [
          [n.lng, n.lat],
        ];
      }
      curSeg!.add([n1.lng, n1.lat]);
    }
    if (curSeg != null && curSeg.length >= 2) {
      buckets[curBucket].add(curSeg);
    }

    // Draw each bucket as one GeoJSON FeatureCollection
    for (int b = 0; b < 4; b++) {
      if (buckets[b].isEmpty) continue;
      final features = buckets[b]
          .map(
            (coords) => {
              'type': 'Feature',
              'geometry': {'type': 'LineString', 'coordinates': coords},
              'properties': {},
            },
          )
          .toList();
      final geoJson = jsonEncode({
        'type': 'FeatureCollection',
        'features': features,
      });
      final sourceId = '${_hmIds[b]}-source';
      final layerId = '${_hmIds[b]}-layer';
      try {
        await map.style.addSource(
          mbx.GeoJsonSource(id: sourceId, data: geoJson),
        );
        await map.style.addLayer(
          mbx.LineLayer(
            id: layerId,
            sourceId: sourceId,
            lineColor: _hmColors[b],
            lineWidth: 5.5,
            lineOpacity: 1.0,
            lineCap: mbx.LineCap.ROUND,
            lineJoin: mbx.LineJoin.ROUND,
          ),
        );
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
      await map.compass.updateSettings(
        mbx.CompassSettings(
          enabled: true,
          opacity: 0.85,
          position: mbx.OrnamentPosition.BOTTOM_RIGHT,
          marginBottom: 120,
          marginRight: 14,
        ),
      );
    } catch (e) {
      debugPrint('[MapWidget] compass: $e');
    }

    // ── 위치 표시: 방향 화살표 + pulsing ───────────────────────────
    try {
      await _updateLocationSettings();
    } catch (e) {
      debugPrint('[MapWidget] location layer: $e');
    }

    // ── 스타일 설정 (라이트/라벨 등) ──────────────────────────────
    for (final entry in {
      'showPointOfInterestLabels': false,
      'showTransitLabels': false,
      'showRoadLabels': !widget.routeFocusMode,
      'showPlaceLabels': !widget.routeFocusMode,
      'lightPreset': 'night',
      if (widget.routeFocusMode) 'theme': 'monochrome',
    }.entries) {
      try {
        await map.style.setStyleImportConfigProperty(
          'basemap',
          entry.key,
          entry.value,
        );
      } catch (_) {}
    }

    await _applyRouteFocusStyle();
  }

  bool _isRevvOverlayLayer(String id) {
    return id.startsWith('route-') ||
        id.startsWith('nav-') ||
        id.startsWith('hm-');
  }

  Future<void> _applyRouteFocusStyle() async {
    final map = _mapController;
    if (map == null || !_styleLoaded) return;

    if (!widget.routeFocusMode) {
      if (!_routeFocusApplied && _originalLayerVisibility.isEmpty) return;
      final restoreEntries = Map<String, Object?>.from(
        _originalLayerVisibility,
      );
      for (final entry in restoreEntries.entries) {
        try {
          await map.style.setStyleLayerProperty(
            entry.key,
            'visibility',
            entry.value ?? 'visible',
          );
        } catch (_) {}
      }
      _originalLayerVisibility.clear();
      _routeFocusApplied = false;
      return;
    }

    if (_routeFocusApplied) return;
    try {
      final layers = await map.style.getStyleLayers();
      for (final layer in layers.whereType<mbx.StyleObjectInfo>()) {
        if (_isRevvOverlayLayer(layer.id)) continue;
        if (layer.type == 'background') continue;
        try {
          final original = await map.style.getStyleLayerProperty(
            layer.id,
            'visibility',
          );
          _originalLayerVisibility[layer.id] = original.value;
        } catch (_) {
          _originalLayerVisibility[layer.id] = null;
        }
        try {
          await map.style.setStyleLayerProperty(layer.id, 'visibility', 'none');
        } catch (_) {}
      }
      _routeFocusApplied = true;
    } catch (e) {
      debugPrint('[MapWidget] route focus style: $e');
    }
  }

  Future<void> _moveCamera(
    double lat,
    double lng, {
    double? heading,
    bool immediate = false,
  }) async {
    if (!_styleLoaded || _mapController == null) return;

    final cameraOpts = mbx.CameraOptions(
      center: mbx.Point(coordinates: mbx.Position(lng, lat)),
      zoom: widget.isSprintMode ? 16.5 : 15.0,
      pitch: widget.isSprintMode ? 50.0 : 20.0,
      bearing: (widget.isSprintMode && heading != null) ? heading : null,
    );

    if (immediate) {
      // 즉각 이동 (스타일 로드 시 초기 위치)
      try {
        await _mapController!.setCamera(cameraOpts);
      } catch (_) {}
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
        await _updateLocationSettings();
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasPermission = context.select<LocationService, bool>(
      (loc) => loc.hasPermission,
    );

    if (!hasPermission) {
      return _MapFallback();
    }

    if (_disableMapbox) {
      return const _MapFallback(
        icon: Icons.map_outlined,
        message: '지도 엔진 진단 모드',
      );
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
      textureView: true,
      onMapCreated: _onMapCreated,
      onStyleLoadedListener: _onStyleLoaded,
    );
  }
}

class _MapFallback extends StatelessWidget {
  final IconData icon;
  final String message;

  const _MapFallback({
    this.icon = Icons.location_off,
    this.message = '위치 권한이 필요해요',
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0D1117),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: AppColors.red.withValues(alpha: 0.5),
              size: 32,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: TextStyle(
                color: AppColors.white.withValues(alpha: 0.4),
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
