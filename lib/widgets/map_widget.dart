import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mbx;
import 'package:provider/provider.dart';
import '../services/location_service.dart';
import '../services/mapbox_service.dart';
import '../theme/colors.dart';

class MapWidget extends StatefulWidget {
  final bool isSprintMode;
  const MapWidget({super.key, this.isSprintMode = false});

  @override
  State<MapWidget> createState() => _MapWidgetState();
}

class _MapWidgetState extends State<MapWidget> {
  mbx.MapboxMap? _mapController;
  mbx.PointAnnotationManager? _annotationManager;
  bool _styleLoaded = false;
  LocationService? _locationService;

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
  void dispose() {
    _locationService?.removeListener(_onLocationChanged);
    super.dispose();
  }

  void _onLocationChanged() {
    final loc = _locationService;
    if (loc != null && _styleLoaded) {
      _moveCamera(loc.lat, loc.lng);
    }
  }

  void _onMapCreated(mbx.MapboxMap controller) {
    _mapController = controller;
  }

  Future<void> _onStyleLoaded(mbx.StyleLoadedEventData _) async {
    _styleLoaded = true;
    _annotationManager =
        await _mapController?.annotations.createPointAnnotationManager();
    final loc = context.read<LocationService>();
    await _moveCamera(loc.lat, loc.lng);
    await _applyCustomStyle();
  }

  Future<void> _applyCustomStyle() async {
    final map = _mapController;
    if (map == null) return;

    // ── 나침반 활성화 ─────────────────────────────────────────────────
    try {
      await map.compass.updateSettings(mbx.CompassSettings(
        enabled: true,
        opacity: 0.85,
      ));
    } catch (e) {
      debugPrint('[MapWidget] compass: $e');
    }

    // ── 위치 표시: Waze 스타일 방향 화살표 ────────────────────────────
    try {
      await map.location.updateSettings(mbx.LocationComponentSettings(
        enabled: true,
        pulsingEnabled: false,
        locationPuck: mbx.LocationPuck(
          locationPuck2D: mbx.LocationPuck2D(),
        ),
      ));
    } catch (e) {
      debugPrint('[MapWidget] location layer: $e');
    }
  }

  Future<void> _moveCamera(double lat, double lng) async {
    if (!_styleLoaded || _mapController == null) return;
    await _mapController!.flyTo(
      mbx.CameraOptions(
        center: mbx.Point(coordinates: mbx.Position(lng, lat)),
        zoom: widget.isSprintMode ? 16.0 : 15.0,
        pitch: widget.isSprintMode ? 60.0 : 30.0,
      ),
      mbx.MapAnimationOptions(duration: 800),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasPermission =
        context.select<LocationService, bool>((loc) => loc.hasPermission);

    if (!hasPermission) {
      return _MapFallback();
    }

    final loc = context.read<LocationService>();
    return mbx.MapWidget(
      styleUri: widget.isSprintMode
          ? MapboxService.sprintStyle
          : MapboxService.cruiseStyle,
      cameraOptions: mbx.CameraOptions(
        center: mbx.Point(coordinates: mbx.Position(loc.lng, loc.lat)),
        zoom: widget.isSprintMode ? 16.0 : 15.0,
        pitch: widget.isSprintMode ? 60.0 : 30.0,
      ),
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
