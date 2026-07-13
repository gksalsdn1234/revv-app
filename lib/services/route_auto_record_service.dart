import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/revv_route.dart';
import 'route_service.dart';
import 'run_session_service.dart';
import 'location_service.dart';

enum AutoRecordState { idle, armed, recording, claimed }

class AutoRecordFix {
  const AutoRecordFix({
    required this.point,
    required this.speedKmh,
    required this.accuracyM,
    required this.timestamp,
  });

  final LatLng point;
  final double speedKmh;
  final double accuracyM;
  final DateTime timestamp;
}

class RouteAutoRecordService extends ChangeNotifier {
  RouteAutoRecordService({
    required RouteService routes,
    required RunSessionService sessions,
    LocationService? location,
  }) : _routes = routes,
       _sessions = sessions,
       _location = location {
    _refreshArmedRoute();
  }

  static const double startRadiusKm = 0.08;
  static const double maxAccuracyM = 50;
  static const double minSpeedKmh = 8;
  static const Duration confirmationWindow = Duration(seconds: 5);

  final RouteService _routes;
  final RunSessionService _sessions;
  final LocationService? _location;
  bool _attached = false;
  AutoRecordState _state = AutoRecordState.idle;
  RevvRoute? _activeRoute;
  DateTime? _firstQualifyingAt;
  int _qualifyingFixes = 0;

  AutoRecordState get state => _state;
  RevvRoute? get activeRoute => _activeRoute;

  void attach() {
    if (_attached) return;
    _attached = true;
    _routes.addListener(_onRouteChanged);
    _location?.addListener(_onLocationChanged);
    _onRouteChanged();
  }

  void refreshArmedRoute() {
    _refreshArmedRoute();
    notifyListeners();
  }

  void handleFix(AutoRecordFix fix) {
    if (_state == AutoRecordState.claimed) return;
    if (_state == AutoRecordState.recording) {
      _sessions.recordPosition(fix.point.lat, fix.point.lng, fix.speedKmh);
      return;
    }

    final route = _routes.pendingGuideRoute;
    if (route == null || !_routes.hasFreshPendingGuide) {
      _setIdle();
      unawaited(_location?.stopArmedTracking());
      notifyListeners();
      return;
    }
    if (_sessions.isRecording) {
      _firstQualifyingAt = null;
      _qualifyingFixes = 0;
      return;
    }
    _activeRoute = route;
    _state = AutoRecordState.armed;
    final start = route.nodes.isEmpty ? route.centerPoint : route.nodes.first;
    final qualifies =
        fix.accuracyM <= maxAccuracyM &&
        fix.speedKmh >= minSpeedKmh &&
        RevvRoute.haversineKm(fix.point, start) <= startRadiusKm;
    if (!qualifies) {
      _firstQualifyingAt = null;
      _qualifyingFixes = 0;
      return;
    }

    _firstQualifyingAt ??= fix.timestamp;
    _qualifyingFixes++;
    final elapsed = fix.timestamp.difference(_firstQualifyingAt!);
    if (_qualifyingFixes < 2 || elapsed < confirmationWindow) return;

    _sessions.startSession(route);
    _sessions.recordPosition(fix.point.lat, fix.point.lng, fix.speedKmh);
    _state = AutoRecordState.recording;
    _routes.clearGuideToStart();
    notifyListeners();
  }

  bool claimRecording(String routeId) {
    if (_state != AutoRecordState.recording || _activeRoute?.id != routeId) {
      return false;
    }
    _state = AutoRecordState.claimed;
    notifyListeners();
    return true;
  }

  void claimManualDrive(String routeId) {
    if (_state == AutoRecordState.recording) return;
    if (_routes.pendingGuideRoute?.id == routeId) {
      _routes.clearGuideToStart();
    }
    _state = AutoRecordState.claimed;
    _activeRoute = null;
    _firstQualifyingAt = null;
    _qualifyingFixes = 0;
    unawaited(_location?.stopArmedTracking());
    notifyListeners();
  }

  void finish() {
    _refreshArmedRoute();
    if (_state == AutoRecordState.armed) {
      unawaited(_location?.startArmedTracking());
    } else {
      unawaited(_location?.stopArmedTracking());
    }
    notifyListeners();
  }

  void _onRouteChanged() {
    if (_state == AutoRecordState.recording ||
        _state == AutoRecordState.claimed) {
      return;
    }
    _refreshArmedRoute();
    if (_state == AutoRecordState.armed) {
      _location?.startArmedTracking();
    } else {
      _location?.stopArmedTracking();
    }
    notifyListeners();
  }

  void _onLocationChanged() {
    final position = _location?.currentPosition;
    if (position == null) return;
    handleFix(
      AutoRecordFix(
        point: LatLng(position.latitude, position.longitude),
        speedKmh: _location?.speedKmh ?? 0,
        accuracyM: position.accuracy,
        timestamp: position.timestamp,
      ),
    );
  }

  void _refreshArmedRoute() {
    final route = _routes.pendingGuideRoute;
    if (route == null || !_routes.hasFreshPendingGuide) {
      _setIdle();
      return;
    }
    _activeRoute = route;
    _state = AutoRecordState.armed;
  }

  void _setIdle() {
    _state = AutoRecordState.idle;
    _activeRoute = null;
    _firstQualifyingAt = null;
    _qualifyingFixes = 0;
  }

  @override
  void dispose() {
    if (_attached) {
      _routes.removeListener(_onRouteChanged);
      _location?.removeListener(_onLocationChanged);
    }
    super.dispose();
  }
}
